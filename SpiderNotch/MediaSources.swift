//
//  MediaSources.swift
//  SpiderNotch
//
//  App-specific media integrations. Different apps share what they play in
//  different ways, so each gets its own code:
//
//  • Music and Spotify broadcast every track change to the whole Mac
//    ("distributed notifications"). Listening needs no permission at all.
//    Their AppleScript commands (play/pause, next, seek, show the track) need
//    your OK once ("SpiderNotch wants to control Spotify").
//  • Web browsers: Safari and Chromium browsers (Chrome, Edge, Brave, Vivaldi)
//    let SpiderNotch list their tabs (title + address) with AppleScript, to find
//    the tab that's playing and bring it forward. With the browser's
//    "Allow JavaScript from Apple Events" option on, SpiderNotch can also read
//    and control the <video>/<audio> in that tab directly.
//  • Firefox and other apps: only what the system Now Playing helper reports.
//

import AppKit

/// The commands the island's buttons send.
enum MediaCommand: String {
    case toggle, play, pause, next, previous
}

// MARK: - Music and Spotify

/// What Music or Spotify last told us about its current track.
struct AppTrack {
    var title: String
    var artist: String?
    var album: String?
    var duration: Double?
    var position: Double?
    var stamp: Date
    var isPlaying: Bool
    /// spotify:track:… (Spotify only)
    var trackURI: String?
    var artwork: NSImage?
    var artworkURL: String?
}

@MainActor
final class MusicAppWatcher {
    enum Kind {
        case music, spotify
    }

    let kind: Kind
    let bundleID: String
    private(set) var track: AppTrack?
    var onChange: (@MainActor () -> Void)?
    private var observer: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?
    private var refreshing = false

    init(kind: Kind) {
        self.kind = kind
        bundleID = kind == .music ? "com.apple.Music" : "com.spotify.client"
    }

    var appName: String {
        kind == .music ? "Music" : "Spotify"
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func start() {
        let name = kind == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged"
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil,
                                                                       queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated {
                self?.received(info)
            }
        }
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let quitID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self = self, quitID == self.bundleID else { return }
                self.track = nil
                self.onChange?()
            }
        }
        // Nothing is broadcast until something changes, so ask once now (only if
        // you've already allowed it: this never shows a permission prompt).
        refreshIfAllowed()
    }

    private func received(_ info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else {
            track = nil
            onChange?()
            return
        }
        var updated = track ?? AppTrack(title: title, stamp: Date(), isPlaying: false)
        let sameTrack = updated.title == title && updated.artist == (info["Artist"] as? String)
        updated.title = title
        updated.artist = info["Artist"] as? String
        updated.album = info["Album"] as? String
        updated.isPlaying = state == "Playing"
        updated.stamp = Date()
        if kind == .music {
            if let total = info["Total Time"] as? NSNumber {
                updated.duration = total.doubleValue / 1000
            }
            if !sameTrack {
                updated.position = 0
                updated.artwork = nil
            }
        } else {
            if let total = info["Duration"] as? NSNumber {
                updated.duration = total.doubleValue / 1000
            }
            if let position = info["Playback Position"] as? NSNumber {
                updated.position = position.doubleValue
            }
            updated.trackURI = info["Track ID"] as? String
            if !sameTrack {
                updated.artwork = nil
                updated.artworkURL = nil
            }
        }
        track = updated
        onChange?()
        if !sameTrack || updated.artwork == nil {
            refreshIfAllowed()
        }
    }

    /// Reads position and artwork with AppleScript, if you've allowed it.
    func refreshIfAllowed() {
        guard isRunning, !refreshing else { return }
        let bundleID = self.bundleID
        DispatchQueue.global(qos: .utility).async {
            let permission = ScriptRunner.permission(for: bundleID)
            Task { @MainActor [weak self] in
                if permission == .granted {
                    self?.refreshNow()
                }
            }
        }
    }

    private func refreshNow() {
        refreshing = true
        let script: String
        if kind == .music {
            script = """
            tell application id "com.apple.Music"
                if player state is stopped then return "stopped"
                set fs to character id 31
                set t to current track
                return (player state as text) & fs & (name of t) & fs & (artist of t) & fs & (album of t) & fs & (duration of t) & fs & (player position as text)
            end tell
            """
        } else {
            script = """
            tell application id "com.spotify.client"
                if player state is stopped then return "stopped"
                set fs to character id 31
                set t to current track
                return (player state as text) & fs & (name of t) & fs & (artist of t) & fs & (album of t) & fs & ((duration of t) / 1000) & fs & (player position as text) & fs & (artwork url of t) & fs & (spotify url of t)
            end tell
            """
        }
        ScriptRunner.run(script, timeout: 3) { [weak self] result in
            guard let self = self else { return }
            self.refreshing = false
            guard case .success(let text) = result else { return }
            self.applyStatus(text)
        }
    }

    private func applyStatus(_ text: String) {
        if text == "stopped" || text.isEmpty {
            track = nil
            onChange?()
            return
        }
        let parts = text.components(separatedBy: "\u{1F}")
        guard parts.count >= 6, !parts[1].isEmpty else { return }
        var updated = track ?? AppTrack(title: parts[1], stamp: Date(), isPlaying: false)
        let sameTrack = updated.title == parts[1]
        updated.title = parts[1]
        updated.artist = parts[2].isEmpty ? nil : parts[2]
        updated.album = parts[3].isEmpty ? nil : parts[3]
        updated.duration = MusicAppWatcher.number(parts[4])
        updated.position = MusicAppWatcher.number(parts[5])
        updated.stamp = Date()
        updated.isPlaying = parts[0] == "playing"
        if !sameTrack {
            updated.artwork = nil
        }
        if kind == .spotify, parts.count >= 8 {
            updated.trackURI = parts[7].isEmpty ? updated.trackURI : parts[7]
            let artworkURL = parts[6]
            if !artworkURL.isEmpty && (artworkURL != updated.artworkURL || updated.artwork == nil) {
                updated.artworkURL = artworkURL
                loadArtwork(from: artworkURL)
            }
        }
        track = updated
        onChange?()
        if kind == .music && updated.artwork == nil {
            loadMusicArtwork()
        }
    }

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func loadArtwork(from address: String) {
        guard let url = URL(string: address), url.scheme == "https" else { return }
        ArtworkLoader.load(url) { [weak self] image in
            guard let self = self, let image = image, self.track?.artworkURL == address else { return }
            self.track?.artwork = image
            self.onChange?()
        }
    }

    /// Music doesn't share artwork as a link, so the picture is written to a file first.
    private func loadMusicArtwork() {
        let file = AppInfo.supportFolder.appendingPathComponent("Helper/music-artwork.bin")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        tell application id "com.apple.Music"
            if player state is stopped then return ""
            if (count of artworks of current track) is 0 then return ""
            set d to raw data of artwork 1 of current track
        end tell
        set f to open for access (POSIX file \(ScriptRunner.quoted(file.path))) with write permission
        set eof f to 0
        write d to f
        close access f
        return "ok"
        """
        let title = track?.title
        ScriptRunner.run(script, timeout: 4) { [weak self] result in
            guard let self = self, case .success(let text) = result, text == "ok",
                  self.track?.title == title,
                  let data = try? Data(contentsOf: file), let image = NSImage(data: data)
            else { return }
            self.track?.artwork = image
            self.onChange?()
        }
    }

    // MARK: Commands (AppleScript)

    func send(_ command: MediaCommand) {
        let verb: String
        switch command {
        case .toggle: verb = "playpause"
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        // A longer time limit: the first time, macOS asks you for permission.
        ScriptRunner.run("tell application id \"\(bundleID)\" to \(verb)", timeout: 30) { [weak self] _ in
            self?.refreshIfAllowed()
        }
    }

    func seek(to seconds: Double) {
        let value = String(format: "%.2f", max(seconds, 0))
        ScriptRunner.run("tell application id \"\(bundleID)\" to set player position to \(value)", timeout: 30) { [weak self] _ in
            self?.refreshIfAllowed()
        }
    }

    /// Shows the playing track in the app.
    func showTrack(fallback: @escaping @MainActor () -> Void) {
        if kind == .spotify {
            if let uri = track?.trackURI, let url = URL(string: uri) {
                NSWorkspace.shared.open(url)
            } else {
                fallback()
            }
            return
        }
        let script = """
        tell application id "com.apple.Music"
            activate
            reveal current track
        end tell
        """
        ScriptRunner.run(script, timeout: 30) { result in
            if case .failure = result {
                fallback()
            }
        }
    }
}

/// Downloads small pictures (album covers, video thumbnails) and remembers them.
@MainActor
enum ArtworkLoader {
    private static var cache: [URL: NSImage] = [:]

    static func load(_ url: URL, completion: @escaping @MainActor (NSImage?) -> Void) {
        if let cached = cache[url] {
            completion(cached)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            Task { @MainActor in
                if let image = image {
                    if cache.count > 40 {
                        cache.removeAll()
                    }
                    cache[url] = image
                }
                completion(image)
            }
        }.resume()
    }
}

// MARK: - Web browsers

enum BrowserFamily {
    /// Safari: tabs, and "do JavaScript".
    case safari
    /// Chrome, Edge, Brave, Vivaldi, Chromium: tabs, and "execute javascript".
    case chromium
    /// Firefox and others: no tab access from other apps.
    case other
}

enum Browsers {
    static let families: [String: BrowserFamily] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.beta": .chromium,
        "com.google.Chrome.dev": .chromium,
        "com.google.Chrome.canary": .chromium,
        "org.chromium.Chromium": .chromium,
        "com.brave.Browser": .chromium,
        "com.brave.Browser.beta": .chromium,
        "com.brave.Browser.nightly": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.microsoft.edgemac.Beta": .chromium,
        "com.microsoft.edgemac.Dev": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .other,
        "company.thebrowser.Browser": .other,
        "org.mozilla.firefox": .other,
        "org.mozilla.firefoxdeveloperedition": .other,
        "org.mozilla.nightly": .other,
        "app.zen-browser.zen": .other,
    ]

    static func family(of bundleID: String) -> BrowserFamily? {
        families[bundleID]
    }

    static func isBrowser(_ bundleID: String) -> Bool {
        families[bundleID] != nil
    }

    /// Browsers that let SpiderNotch see their tabs.
    static func canListTabs(_ bundleID: String) -> Bool {
        guard let family = families[bundleID] else { return false }
        return family != .other
    }
}

/// One browser tab.
struct BrowserTab: Equatable {
    let bundleID: String
    let windowID: String
    let index: Int
    let title: String
    let url: String
    let isFrontTab: Bool

    var host: String {
        (URL(string: url)?.host ?? "").lowercased()
    }

    /// A friendly name for the website ("YouTube", "SoundCloud"...).
    var siteName: String {
        BrowserTab.siteName(forHost: host)
    }

    static func siteName(forHost host: String) -> String {
        if let known = knownSiteName(forHost: host) {
            return known
        }
        var short = host
        if short.hasPrefix("www.") {
            short.removeFirst(4)
        }
        return short
    }

    /// True for well-known music and video sites.
    var isMediaSite: Bool {
        BrowserTab.knownSiteName(forHost: host) != nil
    }

    static func knownSiteName(forHost host: String) -> String? {
        let names: [(String, String)] = [
            ("music.youtube.com", "YouTube Music"), ("youtube.com", "YouTube"), ("youtu.be", "YouTube"),
            ("open.spotify.com", "Spotify"), ("soundcloud.com", "SoundCloud"), ("music.apple.com", "Apple Music"),
            ("tv.apple.com", "Apple TV"), ("netflix.com", "Netflix"), ("twitch.tv", "Twitch"), ("vimeo.com", "Vimeo"),
            ("primevideo.com", "Prime Video"), ("disneyplus.com", "Disney+"), ("bandcamp.com", "Bandcamp"),
            ("deezer.com", "Deezer"), ("tidal.com", "TIDAL"), ("music.amazon.com", "Amazon Music"),
            ("dailymotion.com", "Dailymotion"), ("bilibili.com", "bilibili"), ("tiktok.com", "TikTok"),
        ]
        for (domain, name) in names where host == domain || host.hasSuffix("." + domain) {
            return name
        }
        return nil
    }

    /// Video sites: their pictures are wide (16:9) thumbnails.
    var isVideoSite: Bool {
        ["YouTube", "Netflix", "Twitch", "Vimeo", "Prime Video", "Disney+", "Apple TV", "Dailymotion", "bilibili", "TikTok"]
            .contains(siteName)
    }

    /// The YouTube video's ID, if this tab is a YouTube video.
    var youTubeVideoID: String? {
        guard let components = URLComponents(string: url), siteName == "YouTube" else { return nil }
        if host.hasSuffix("youtu.be") {
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        if let id = components.queryItems?.first(where: { $0.name == "v" })?.value, !id.isEmpty {
            return id
        }
        let pieces = components.path.split(separator: "/")
        if pieces.count >= 2, ["shorts", "live", "embed"].contains(String(pieces[0])) {
            return String(pieces[1])
        }
        return nil
    }

    var youTubeThumbnailURL: URL? {
        youTubeVideoID.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }

    /// AppleScript that points at this tab.
    var scriptReference: String {
        "tab \(index) of window id \(windowID)"
    }
}

@MainActor
enum BrowserTabs {
    private static let fieldSeparator = "\u{1F}"
    private static let recordSeparator = "\u{1E}"

    /// Lists every tab of a browser (title and address). Needs the Automation permission.
    static func list(bundleID: String, timeout: TimeInterval = 4,
                     completion: @escaping @MainActor (Result<[BrowserTab], ScriptError>) -> Void) {
        guard let family = Browsers.family(of: bundleID), family != .other else {
            completion(.failure(.failed("This browser doesn't share its tabs.")))
            return
        }
        let titleProperty = family == .safari ? "name" : "title"
        let frontTab = family == .safari ? "index of current tab of w" : "active tab index of w"
        let script = """
        set fs to character id 31
        set rs to character id 30
        set out to ""
        tell application id \(ScriptRunner.quoted(bundleID))
            repeat with w in windows
                try
                    set wid to (id of w) as text
                    set ts to \(titleProperty) of every tab of w
                    set us to URL of every tab of w
                    set fi to \(frontTab)
                    repeat with i from 1 to count of ts
                        set t to item i of ts
                        if t is missing value then set t to ""
                        set u to item i of us
                        if u is missing value then set u to ""
                        set out to out & wid & fs & i & fs & t & fs & u & fs & ((i = fi) as text) & rs
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        ScriptRunner.run(script, timeout: timeout) { result in
            switch result {
            case .success(let text):
                completion(.success(parse(text, bundleID: bundleID)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func parse(_ text: String, bundleID: String) -> [BrowserTab] {
        text.components(separatedBy: recordSeparator).compactMap { record in
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count >= 5, let index = Int(fields[1]) else { return nil }
            return BrowserTab(bundleID: bundleID, windowID: fields[0], index: index, title: fields[2],
                              url: fields[3], isFrontTab: fields[4] == "true")
        }
    }

    /// Picks the tab that's most likely playing a title (from the system Now Playing).
    static func bestMatch(title: String, artist: String?, in tabs: [BrowserTab]) -> BrowserTab? {
        let wanted = normalize(title)
        var best: (tab: BrowserTab, score: Int)?
        for tab in tabs {
            var score = 0
            let tabTitle = normalize(tab.title)
            if wanted.count >= 3 && tabTitle.contains(wanted) {
                score += 10
            } else if wanted.count >= 8 && wanted.contains(tabTitle) && tabTitle.count >= 6 {
                score += 6
            }
            if let artist = artist, artist.count >= 3, tabTitle.contains(normalize(artist)) {
                score += 2
            }
            if tab.isMediaSite {
                score += 3
            }
            if tab.isFrontTab {
                score += 1
            }
            if score >= 4 && score > (best?.score ?? 0) {
                best = (tab, score)
            }
        }
        return best?.tab
    }

    private static func normalize(_ text: String) -> String {
        var value = text.lowercased()
        // "(3) Video title - YouTube" → "video title"
        if value.hasPrefix("("), let close = value.firstIndex(of: ")") {
            value = String(value[value.index(after: close)...])
        }
        for suffix in [" - youtube", " - youtube music", " | soundcloud", " - spotify"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Brings the tab to the front: selects it, raises its window, activates the browser.
    static func show(_ tab: BrowserTab, completion: @escaping @MainActor (Bool) -> Void) {
        let family = Browsers.family(of: tab.bundleID) ?? .other
        let select = family == .safari
            ? "set current tab of w to tab \(tab.index) of w"
            : "set active tab index of w to \(tab.index)"
        let unminimize = family == .safari ? "set miniaturized of w to false" : "set minimized of w to false"
        let script = """
        tell application id \(ScriptRunner.quoted(tab.bundleID))
            set w to window id \(tab.windowID)
            try
                \(unminimize)
            end try
            \(select)
            set index of w to 1
            activate
        end tell
        """
        ScriptRunner.run(script, timeout: 30) { result in
            if case .success = result {
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    // MARK: JavaScript in a tab (needs "Allow JavaScript from Apple Events")

    static func runJavaScript(_ code: String, in tab: BrowserTab, timeout: TimeInterval = 4,
                              completion: @escaping @MainActor (Result<String, ScriptError>) -> Void) {
        let family = Browsers.family(of: tab.bundleID) ?? .other
        let oneLine = code.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        let script: String
        switch family {
        case .safari:
            script = "tell application id \(ScriptRunner.quoted(tab.bundleID)) to do JavaScript \(ScriptRunner.quoted(oneLine)) in \(tab.scriptReference)"
        case .chromium:
            script = "tell application id \(ScriptRunner.quoted(tab.bundleID)) to execute (\(tab.scriptReference)) javascript \(ScriptRunner.quoted(oneLine))"
        case .other:
            completion(.failure(.failed("This browser can't run JavaScript from other apps.")))
            return
        }
        ScriptRunner.run(script, timeout: timeout, completion: completion)
    }

    /// Finds the main <video> or <audio> on the page (the playing one if any).
    private static let findMedia = """
    var list = Array.prototype.slice.call(document.querySelectorAll('video, audio'));
    var m = list.filter(function (e) { return !e.paused && !e.ended; })[0]
         || list.filter(function (e) { return e.currentTime > 0; })[0] || list[0];
    """

    /// JavaScript that describes what the page is playing, as JSON ("" if nothing).
    static let mediaStateScript = """
    (function () {
    \(findMedia)
    if (!m) { return ''; }
    var md = navigator.mediaSession ? navigator.mediaSession.metadata : null;
    var art = '';
    if (md && md.artwork && md.artwork.length) { art = md.artwork[md.artwork.length - 1].src; }
    return JSON.stringify({ playing: !m.paused && !m.ended, time: m.currentTime,
      duration: isFinite(m.duration) ? m.duration : 0,
      title: (md && md.title) ? md.title : document.title,
      artist: (md && md.artist) ? md.artist : '', album: (md && md.album) ? md.album : '', artwork: art });
    })()
    """

    /// JavaScript that controls the page's video or audio.
    static func controlScript(_ command: MediaCommand) -> String {
        let action: String
        switch command {
        case .toggle: action = "if (m.paused) { m.play(); } else { m.pause(); }"
        case .play: action = "m.play();"
        case .pause: action = "m.pause();"
        case .next:
            action = "var b = document.querySelector('.ytp-next-button, ytmusic-player-bar .next-button, [data-testid=\"control-button-skip-forward\"]'); if (b) { b.click(); }"
        case .previous:
            action = "var p = document.querySelector('ytmusic-player-bar .previous-button, [data-testid=\"control-button-skip-back\"]'); if (p) { p.click(); } else { m.currentTime = 0; }"
        }
        return "(function () { \(findMedia) if (!m) { return 'none'; } \(action) return 'ok'; })()"
    }

    static func seekScript(_ seconds: Double) -> String {
        "(function () { \(findMedia) if (!m) { return 'none'; } m.currentTime = \(String(format: "%.2f", max(seconds, 0))); return 'ok'; })()"
    }
}
