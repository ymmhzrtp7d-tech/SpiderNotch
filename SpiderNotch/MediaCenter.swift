//
//  MediaCenter.swift
//  SpiderNotch
//
//  Gathers everything that's playing into one list of "media sessions", picks
//  the one to show (the playing one, or the most recent), and sends your
//  button presses to the right place:
//
//    the system Now Playing helper  → any app that tells macOS what it plays
//    Music / Spotify AppleScript    → those apps directly (even when they're
//                                     not the one macOS is showing)
//    JavaScript in a browser tab    → that tab's video or audio
//
//  It never invents anything: if nothing reports media, there's no session,
//  and the notch shows your character as usual.
//

import AppKit

/// One thing that's playing (or was playing recently).
struct MediaSession: Identifiable {
    enum Source {
        /// The system Now Playing (the app macOS is showing in Control Center).
        case system
        /// Music or Spotify, heard through their own broadcasts.
        case app
        /// A browser tab found with JavaScript.
        case tab
    }

    let id: String
    var source: Source
    var appBundleID: String
    var appName: String
    var title: String
    var artist: String?
    var album: String?
    /// "YouTube", "SoundCloud"... for media playing in a browser.
    var siteName: String?
    var artwork: NSImage?
    var duration: Double?
    var elapsedAtStamp: Double?
    var stamp: Date
    var isPlaying: Bool
    var lastActive: Date
    var tab: BrowserTab?
    /// True if the system Now Playing helper can control it.
    var isSystemSession: Bool
    /// Wide (16:9) pictures: videos.
    var isVideo: Bool

    /// Where playback is right now (moves along by itself while playing).
    func elapsed(at date: Date = Date()) -> Double? {
        guard let start = elapsedAtStamp else { return nil }
        var value = start + (isPlaying ? date.timeIntervalSince(stamp) : 0)
        if let duration = duration, duration > 0 {
            value = min(value, duration)
        }
        return max(value, 0)
    }

    var canSeek: Bool {
        (duration ?? 0) > 0 && elapsedAtStamp != nil
    }

    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// "Artist — Album", or the channel name for videos.
    var subtitle: String {
        [artist, album].compactMap { value in
            guard let value = value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " — ")
    }

    /// "YouTube · Google Chrome", or just "Spotify".
    var sourceLine: String {
        if let site = siteName, !site.isEmpty, site != appName {
            return "\(site) · \(appName)"
        }
        return appName
    }
}

/// What the Settings window shows about Now Playing.
struct MediaStatusReport {
    enum State {
        case good, waiting, off, problem
    }

    struct AppEntry: Identifiable {
        let bundleID: String
        let name: String
        let detail: String
        let state: State
        let canAsk: Bool
        var id: String { bundleID }
    }

    var systemState = State.waiting
    var systemDetail = "Starting…"
    var currentTitle: String?
    var apps: [AppEntry] = []
}

@MainActor
final class MediaCenter {
    static let shared = MediaCenter()

    let system = SystemNowPlaying()
    let music = MusicAppWatcher(kind: .music)
    let spotify = MusicAppWatcher(kind: .spotify)

    /// Everything playing, the best first.
    private(set) var sessions: [MediaSession] = []
    /// The session you picked in the island's source switcher (nil = automatic).
    private(set) var pinnedID: String?
    /// Called on every change.
    var onChange: (@MainActor () -> Void)?

    /// How long paused media keeps showing at the notch.
    let pausedTimeout: TimeInterval = 10 * 60

    private var started = false
    private var lastPlaying: [String: Date] = [:]
    private var tabForTitle: [String: BrowserTab] = [:]
    private var tabLookups = Set<String>()
    private var thumbnails: [String: NSImage] = [:]
    private var tabSessions: [MediaSession] = []
    private var optimistic: [String: (playing: Bool, until: Date)] = [:]
    private var optimisticSeek: [String: (position: Double, at: Date, until: Date)] = [:]
    private var scanTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        system.onChange = { [weak self] in self?.rebuild() }
        music.onChange = { [weak self] in self?.rebuild() }
        spotify.onChange = { [weak self] in self?.rebuild() }
        system.start()
        music.start()
        spotify.start()
        startBrowserScanning()
    }

    func stop() {
        system.stop()
        scanTask?.cancel()
    }

    // MARK: - Which session to show

    /// The session the island shows: the one you picked, or the best one.
    var currentSession: MediaSession? {
        if let pinned = pinnedID, let session = sessions.first(where: { $0.id == pinned }) {
            return session
        }
        return sessions.first
    }

    /// Something worth showing when you hover the notch: playing, or paused
    /// less than ten minutes ago.
    var hasSomethingToShow: Bool {
        let now = Date()
        return sessions.contains { $0.isPlaying || now.timeIntervalSince($0.lastActive) < pausedTimeout }
    }

    func pin(_ id: String?) {
        pinnedID = id
        changed()
    }

    // MARK: - Building the list

    private func rebuild() {
        let now = Date()
        var list: [MediaSession] = []

        // 1. The system Now Playing (what Control Center shows).
        if let info = system.info, !info.title.isEmpty {
            let bundle = info.appBundleID ?? "unknown"
            var session = MediaSession(id: "app:\(bundle)", source: .system, appBundleID: bundle,
                                       appName: MediaCenter.appName(for: bundle),
                                       title: info.title, artist: info.artist, album: info.album,
                                       siteName: nil, artwork: info.artwork, duration: info.duration,
                                       elapsedAtStamp: info.elapsed, stamp: info.timestamp,
                                       isPlaying: info.isPlaying, lastActive: info.timestamp,
                                       tab: nil, isSystemSession: true, isVideo: false)
            if let watcher = watcher(for: bundle), let track = watcher.track, track.title == info.title {
                session.album = session.album ?? track.album
                session.artwork = session.artwork ?? track.artwork
                session.duration = session.duration ?? track.duration
            }
            if Browsers.isBrowser(bundle) {
                attachTab(to: &session)
            }
            list.append(session)
        }

        // 2. Music and Spotify, even when macOS is showing something else.
        for watcher in [music, spotify] {
            guard let track = watcher.track, !list.contains(where: { $0.appBundleID == watcher.bundleID }) else { continue }
            list.append(MediaSession(id: "app:\(watcher.bundleID)", source: .app, appBundleID: watcher.bundleID,
                                     appName: watcher.appName, title: track.title, artist: track.artist,
                                     album: track.album, siteName: nil, artwork: track.artwork,
                                     duration: track.duration, elapsedAtStamp: track.position, stamp: track.stamp,
                                     isPlaying: track.isPlaying, lastActive: track.stamp, tab: nil,
                                     isSystemSession: false, isVideo: false))
        }

        // 3. Browser tabs found with JavaScript (only when the system helper can't help).
        for tabSession in tabSessions where !list.contains(where: { $0.title == tabSession.title }) {
            list.append(tabSession)
        }

        // When did each one last play? And show your button presses straight away.
        for index in list.indices {
            let id = list[index].id
            if let guess = optimistic[id], guess.until > now {
                // Freeze the position at "now" before flipping, so the time doesn't jump.
                let elapsed = list[index].elapsed(at: now)
                list[index].isPlaying = guess.playing
                if let elapsed = elapsed {
                    list[index].elapsedAtStamp = elapsed
                    list[index].stamp = now
                }
            }
            if let seek = optimisticSeek[id], seek.until > now {
                list[index].elapsedAtStamp = seek.position + (list[index].isPlaying ? now.timeIntervalSince(seek.at) : 0)
                list[index].stamp = now
            }
            if list[index].isPlaying {
                lastPlaying[id] = now
            }
            if let last = lastPlaying[id], last > list[index].lastActive {
                list[index].lastActive = last
            }
        }
        list.sort { first, second in
            if first.isPlaying != second.isPlaying {
                return first.isPlaying
            }
            return first.lastActive > second.lastActive
        }
        sessions = list
        if let pinned = pinnedID, !list.contains(where: { $0.id == pinned }) {
            pinnedID = nil
        }
        changed()
    }

    private func changed() {
        onChange?()
        NotificationCenter.default.post(name: .spiderNotchMediaChanged, object: nil)
    }

    private func watcher(for bundleID: String) -> MusicAppWatcher? {
        if bundleID == music.bundleID { return music }
        if bundleID == spotify.bundleID { return spotify }
        return nil
    }

    static func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return "Media"
    }

    // MARK: - Browser tabs

    /// Adds what we know about the browser tab that plays this (website, thumbnail).
    private func attachTab(to session: inout MediaSession) {
        let key = "\(session.appBundleID)|\(session.title)"
        if let tab = tabForTitle[key] {
            session.tab = tab
            session.siteName = tab.siteName
            session.isVideo = tab.isVideoSite
            if session.artwork == nil, let thumbnail = thumbnails[tab.url] {
                session.artwork = thumbnail
            }
        } else {
            lookUpTab(for: session, ask: false)
        }
    }

    /// Finds the tab that plays a session (only asks for permission if `ask` is true).
    private func lookUpTab(for session: MediaSession, ask: Bool, then: (@MainActor (BrowserTab?) -> Void)? = nil) {
        let bundle = session.appBundleID
        let title = session.title
        let artist = session.artist
        let key = "\(bundle)|\(title)"
        guard Browsers.canListTabs(bundle) else {
            then?(nil)
            return
        }
        if !ask && tabLookups.contains(key) {
            return
        }
        tabLookups.insert(key)
        DispatchQueue.global(qos: .userInitiated).async {
            let permission = ask ? ScriptRunner.requestPermission(for: bundle) : ScriptRunner.permission(for: bundle)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard permission == .granted else {
                    self.tabLookups.remove(key)
                    then?(nil)
                    return
                }
                BrowserTabs.list(bundleID: bundle) { result in
                    let tab: BrowserTab?
                    if case .success(let tabs) = result {
                        tab = BrowserTabs.bestMatch(title: title, artist: artist, in: tabs)
                    } else {
                        tab = nil
                    }
                    if let tab = tab {
                        self.tabForTitle[key] = tab
                        self.loadThumbnail(for: tab)
                        self.rebuild()
                    } else {
                        self.tabLookups.remove(key)
                    }
                    then?(tab)
                }
            }
        }
    }

    private func loadThumbnail(for tab: BrowserTab) {
        guard thumbnails[tab.url] == nil, let url = tab.youTubeThumbnailURL else { return }
        let address = tab.url
        ArtworkLoader.load(url) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.thumbnails[address] = image
            self.rebuild()
        }
    }

    /// When the system helper isn't available, look for playing videos in browser
    /// tabs with JavaScript every few seconds (only browsers you've allowed, and
    /// only if their "Allow JavaScript from Apple Events" option is on).
    private func startBrowserScanning() {
        scanTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self = self else { return }
                if case .unavailable = self.system.status {
                    self.scanBrowsers()
                } else if !self.tabSessions.isEmpty {
                    self.tabSessions = []
                    self.rebuild()
                }
            }
        }
    }

    private func scanBrowsers() {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }.filter { Browsers.canListTabs($0) }
        guard !running.isEmpty else {
            if !tabSessions.isEmpty {
                tabSessions = []
                rebuild()
            }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let allowed = running.filter { ScriptRunner.permission(for: $0) == .granted }
            Task { @MainActor [weak self] in
                self?.scanTabs(in: allowed)
            }
        }
    }

    private func scanTabs(in browsers: [String]) {
        var found: [MediaSession] = []
        var remaining = browsers.count
        guard remaining > 0 else {
            tabSessions = []
            rebuild()
            return
        }
        func finishedOne() {
            remaining -= 1
            if remaining == 0 {
                tabSessions = found
                rebuild()
            }
        }
        for bundle in browsers {
            BrowserTabs.list(bundleID: bundle) { [weak self] result in
                guard let self = self, case .success(let tabs) = result else {
                    finishedOne()
                    return
                }
                let candidates = tabs.filter { $0.isMediaSite }
                var pending = candidates.count
                if pending == 0 {
                    finishedOne()
                    return
                }
                for tab in candidates {
                    BrowserTabs.runJavaScript(BrowserTabs.mediaStateScript, in: tab, timeout: 3) { result in
                        if case .success(let json) = result, let session = self.session(fromJavaScript: json, tab: tab) {
                            found.append(session)
                        }
                        pending -= 1
                        if pending == 0 {
                            finishedOne()
                        }
                    }
                }
            }
        }
    }

    private func session(fromJavaScript json: String, tab: BrowserTab) -> MediaSession? {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["title"] as? String, !title.isEmpty
        else { return nil }
        let playing = object["playing"] as? Bool ?? false
        let duration = (object["duration"] as? NSNumber)?.doubleValue
        let time = (object["time"] as? NSNumber)?.doubleValue
        var artwork = thumbnails[tab.url]
        if artwork == nil {
            loadThumbnail(for: tab)
            if let address = object["artwork"] as? String, let url = URL(string: address), url.scheme == "https" {
                ArtworkLoader.load(url) { [weak self] image in
                    guard let self = self, let image = image else { return }
                    self.thumbnails[tab.url] = image
                }
            }
            artwork = nil
        }
        let artist = object["artist"] as? String
        let album = object["album"] as? String
        return MediaSession(id: "tab:\(tab.bundleID):\(tab.windowID):\(tab.index)", source: .tab,
                            appBundleID: tab.bundleID, appName: MediaCenter.appName(for: tab.bundleID),
                            title: title, artist: (artist?.isEmpty ?? true) ? nil : artist,
                            album: (album?.isEmpty ?? true) ? nil : album, siteName: tab.siteName,
                            artwork: artwork, duration: (duration ?? 0) > 0 ? duration : nil,
                            elapsedAtStamp: time, stamp: Date(), isPlaying: playing,
                            lastActive: playing ? Date() : Date().addingTimeInterval(-60),
                            tab: tab, isSystemSession: false, isVideo: tab.isVideoSite)
    }

    // MARK: - Controls

    func perform(_ command: MediaCommand, on session: MediaSession) {
        if command == .toggle || command == .play || command == .pause {
            let playing = command == .toggle ? !session.isPlaying : command == .play
            optimistic[session.id] = (playing, Date().addingTimeInterval(1.5))
            rebuild()
        }
        if session.isSystemSession && system.canSendCommands {
            switch command {
            case .toggle: system.send(.toggle)
            case .play: system.send(.play)
            case .pause: system.send(.pause)
            case .next: system.send(.next)
            case .previous: system.send(.previous)
            }
            return
        }
        if let watcher = watcher(for: session.appBundleID) {
            watcher.send(command)
            return
        }
        if let tab = session.tab {
            BrowserTabs.runJavaScript(BrowserTabs.controlScript(command), in: tab, timeout: 10) { [weak self] result in
                if case .failure(.javaScriptOff) = result {
                    Alerts.show(title: "Turn on JavaScript from Apple Events",
                                message: "To control this tab, \(session.appName) needs one option turned on. In Chrome, Edge or Brave: View › Developer › Allow JavaScript from Apple Events. In Safari: Develop › Allow JavaScript from Apple Events.")
                }
                self?.scanBrowsersSoon()
            }
        }
    }

    func seek(_ session: MediaSession, to seconds: Double) {
        optimisticSeek[session.id] = (seconds, Date(), Date().addingTimeInterval(1.5))
        rebuild()
        if session.isSystemSession && system.canSendCommands {
            system.seek(to: seconds)
        } else if let watcher = watcher(for: session.appBundleID) {
            watcher.seek(to: seconds)
        } else if let tab = session.tab {
            BrowserTabs.runJavaScript(BrowserTabs.seekScript(seconds), in: tab, timeout: 10) { [weak self] _ in
                self?.scanBrowsersSoon()
            }
        }
    }

    private func scanBrowsersSoon() {
        if case .unavailable = system.status {
            scanBrowsers()
        }
    }

    // MARK: - Opening where it plays

    /// Brings the app (and the exact tab or track) that plays this to the front.
    func openSource(of session: MediaSession) {
        let bundle = session.appBundleID
        let fallback: @MainActor () -> Void = {
            MediaCenter.bringForward(bundleID: bundle)
        }
        if let watcher = watcher(for: bundle) {
            watcher.showTrack(fallback: fallback)
            if watcher.kind == .spotify {
                fallback()
            }
            return
        }
        if Browsers.canListTabs(bundle) {
            if let tab = session.tab {
                BrowserTabs.show(tab) { shown in
                    if !shown {
                        fallback()
                    }
                }
                return
            }
            // Ask for permission now (you clicked), then find and show the tab.
            lookUpTab(for: session, ask: true) { tab in
                guard let tab = tab else {
                    fallback()
                    return
                }
                BrowserTabs.show(tab) { shown in
                    if !shown {
                        fallback()
                    }
                }
            }
            return
        }
        fallback()
    }

    /// Brings an app forward the way the Dock does (always works).
    static func bringForward(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, app.isHidden {
            app.unhide()
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    // MARK: - Permissions and status (for Settings)

    func askPermission(for bundleID: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ScriptRunner.requestPermission(for: bundleID)
            Task { @MainActor in
                NotificationCenter.default.post(name: .spiderNotchMediaChanged, object: nil)
            }
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func statusReport() -> MediaStatusReport {
        var report = MediaStatusReport()
        switch system.status {
        case .starting:
            report.systemState = .waiting
            report.systemDetail = "Starting…"
        case .working:
            report.systemState = .good
            report.systemDetail = system.hasSeenMedia
                ? "Working: any app that tells macOS what it plays shows up."
                : "Ready. Play something to see it here."
        case .unavailable(let reason):
            report.systemState = .problem
            report.systemDetail = "\(reason) Music and Spotify still work, and browser tabs work with JavaScript from Apple Events turned on."
        }
        if let current = currentSession {
            report.currentTitle = "\(current.title) (\(current.sourceLine))"
        }

        var bundles = ["com.apple.Music", "com.spotify.client", "com.apple.Safari", "com.google.Chrome"]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, Browsers.canListTabs(id), !bundles.contains(id) {
                bundles.append(id)
            }
        }
        for bundle in bundles {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil else { continue }
            let name = MediaCenter.appName(for: bundle)
            let entry: MediaStatusReport.AppEntry
            switch ScriptRunner.permission(for: bundle) {
            case .granted:
                entry = .init(bundleID: bundle, name: name, detail: "Allowed", state: .good, canAsk: false)
            case .notAsked:
                entry = .init(bundleID: bundle, name: name, detail: "Not asked yet. Click Allow, or just click its song at the notch.",
                              state: .waiting, canAsk: true)
            case .denied:
                entry = .init(bundleID: bundle, name: name, detail: "Not allowed. Turn it on in Automation Settings.",
                              state: .problem, canAsk: false)
            case .appNotRunning:
                entry = .init(bundleID: bundle, name: name, detail: "Open \(name) to check or allow.", state: .off, canAsk: false)
            case .unknown:
                entry = .init(bundleID: bundle, name: name, detail: "Unknown", state: .off, canAsk: false)
            }
            report.apps.append(entry)
        }
        return report
    }
}
