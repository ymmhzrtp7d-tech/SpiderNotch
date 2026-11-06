//
//  UpdateCenter.swift
//  SpiderNotch
//
//  Everything about telling people that SpiderNotch got better:
//    • Update status for Settings → Update Center (installed vs latest version,
//      what's new, release history from GitHub Releases).
//    • The quiet "A New Update Is Available!" card, the menu bar dot, and the
//      "What's new" card after an update installed.
//
//  Installing is always done by Sparkle (Updater.swift), which checks every
//  update's signature. This file only *shows* information: the release history
//  comes from GitHub's public API, and nothing from it is ever installed.
//

import AppKit
import Combine

/// One published version.
struct ReleaseInfo: Identifiable, Equatable {
    var id: String { version }
    let version: String
    let title: String
    let date: Date?
    /// Release notes as Markdown (from GitHub), or plain lines.
    let notes: String
    let url: URL?
    let isPrerelease: Bool

    var highlights: [String] { ReleaseNotes.highlights(fromMarkdown: notes) }
}

/// How big an update is, from the version numbers (semantic versioning).
enum UpdateKind: Equatable {
    case major, feature, fixes

    var label: String {
        switch self {
        case .major: return "Major update"
        case .feature: return "New features"
        case .fixes: return "Bug fixes and improvements"
        }
    }

    var symbol: String {
        switch self {
        case .major: return "star.circle.fill"
        case .feature: return "sparkles"
        case .fixes: return "wrench.and.screwdriver.fill"
        }
    }
}

enum ReleaseNotes {
    /// Compares versions like 1.10.0 > 1.9.2, and 1.4.0 > 1.4.0-beta.2.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func split(_ v: String) -> ([Int], String?) {
            let clean = v.hasPrefix("v") ? String(v.dropFirst()) : v
            let parts = clean.split(separator: "-", maxSplits: 1).map(String.init)
            let numbers = parts[0].split(separator: ".").map { Int($0) ?? 0 }
            return (numbers, parts.count > 1 ? parts[1] : nil)
        }
        let (na, pa) = split(a)
        let (nb, pb) = split(b)
        for i in 0..<max(na.count, nb.count) {
            let x = i < na.count ? na[i] : 0
            let y = i < nb.count ? nb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        switch (pa, pb) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending // 1.4.0 is newer than 1.4.0-beta.1
        case (_, nil): return .orderedAscending
        case let (x?, y?): return x.compare(y, options: .numeric)
        }
    }

    static func kind(from installed: String, to new: String) -> UpdateKind {
        func numbers(_ v: String) -> [Int] {
            let clean = v.hasPrefix("v") ? String(v.dropFirst()) : v
            return (clean.split(separator: "-").first ?? "").split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
        }
        let a = numbers(installed), b = numbers(new)
        if b[0] > a[0] { return .major }
        if b[0] == a[0] && b[1] > a[1] { return .feature }
        return .fixes
    }

    /// The first few bullet points, without Markdown marks: "**Cocoon**: keep…" → "Cocoon: keep…".
    static func highlights(fromMarkdown markdown: String, limit: Int = 4) -> [String] {
        var bullets: [String] = []
        var current: String?
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if let item = current { bullets.append(item) }
                current = String(line.dropFirst(2))
            } else if !line.isEmpty, raw.hasPrefix("  "), current != nil, !line.hasPrefix("#") {
                current! += " " + line
            } else {
                if let item = current { bullets.append(item) }
                current = nil
                if line.hasPrefix("---") { break } // the download instructions start here
            }
        }
        if let item = current { bullets.append(item) }
        return bullets.prefix(limit).map(plain)
    }

    /// Bullet points from Sparkle's HTML release notes (<li>…</li>).
    static func highlights(fromHTML html: String, limit: Int = 4) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<li>(.*?)</li>", options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).prefix(limit).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            return decodeEntities(String(html[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Turns HTML notes into Markdown-ish bullets (so both sources look the same).
    static func markdown(fromHTML html: String) -> String {
        highlights(fromHTML: html, limit: 50).map { "- " + $0 }.joined(separator: "\n")
    }

    private static func plain(_ s: String) -> String {
        var text = s.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        // Long bullets are shortened at the end of their first sentence.
        if text.count > 150, let end = text.range(of: ". ") {
            text = String(text[..<end.lowerBound]) + "."
        }
        return text
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// Reads GitHub's "list releases" answer. Drafts are skipped.
    static func parseGitHubReleases(_ data: Data) -> [ReleaseInfo] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return list.compactMap { entry in
            guard (entry["draft"] as? Bool) != true, let tag = entry["tag_name"] as? String else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return ReleaseInfo(version: version,
                               title: (entry["name"] as? String) ?? "SpiderNotch \(version)",
                               date: (entry["published_at"] as? String).flatMap { iso.date(from: $0) },
                               notes: (entry["body"] as? String) ?? "",
                               url: (entry["html_url"] as? String).flatMap(URL.init(string:)),
                               isPrerelease: (entry["prerelease"] as? Bool) ?? false)
        }
    }

    /// The notes for this version, built into the app from CHANGELOG.md.
    static func bundledNotes() -> String? {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

@MainActor
final class UpdateCenter: ObservableObject {
    static let shared = UpdateCenter()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    /// The newer version Sparkle found (verified feed), if any.
    @Published private(set) var available: ReleaseInfo?
    /// Every published version, newest first (from GitHub Releases).
    @Published private(set) var history: [ReleaseInfo] = []
    @Published private(set) var historyError: String?
    @Published private(set) var isLoadingHistory = false
    private var lastHistoryLoad = Date.distantPast

    private let defaults = UserDefaults.standard

    var installedVersion: String { AppInfo.version }

    /// The newest stable version we know of (installed one if nothing newer).
    var latestVersion: String {
        if let available = available { return available.version }
        if let newest = history.first(where: { !$0.isPrerelease }),
           ReleaseNotes.compare(newest.version, installedVersion) == .orderedDescending {
            return newest.version
        }
        return installedVersion
    }

    var notifyEnabled: Bool {
        get { defaults.bool(forKey: Preferences.Key.updateNotify) }
        set { defaults.set(newValue, forKey: Preferences.Key.updateNotify); objectWillChange.send() }
    }

    private var remindAfter: Date? {
        get { defaults.object(forKey: Preferences.Key.updateRemindAfter) as? Date }
        set { defaults.set(newValue, forKey: Preferences.Key.updateRemindAfter) }
    }

    // MARK: - From Sparkle

    func checkStarted() {
        status = .checking
    }

    /// Sparkle found a newer, correctly signed version in the update feed.
    func found(version: String, title: String?, date: Date?, htmlNotes: String?) {
        let notes = htmlNotes.map(ReleaseNotes.markdown(fromHTML:)) ?? ""
        let fromHistory = history.first { $0.version == version }
        available = ReleaseInfo(version: version,
                                title: title ?? "SpiderNotch \(version)",
                                date: date ?? fromHistory?.date,
                                notes: notes.isEmpty ? (fromHistory?.notes ?? "") : notes,
                                url: fromHistory?.url ?? AppInfo.releasesURL.appendingPathComponent("tag/v\(version)"),
                                isPrerelease: version.contains("-"))
        status = .available
    }

    func noUpdateFound() {
        available = nil
        status = .upToDate
        UpdateAnnouncementPanel.shared.hide()
    }

    func failed(_ message: String) {
        status = .failed(message)
    }

    // MARK: - Announcing

    /// Called when Sparkle found an update in the background. Shows the quiet
    /// card, unless you turned it off or asked to be reminded later.
    func announceIfAppropriate() {
        guard let release = available, notifyEnabled else { return }
        if let later = remindAfter, later > Date() { return }
        defaults.set(release.version, forKey: Preferences.Key.updateAnnouncedVersion)
        UpdateAnnouncementPanel.shared.show(.available(release, kind: ReleaseNotes.kind(from: installedVersion, to: release.version)))
    }

    /// "Update Now": Sparkle shows the update window (download, verify, install, relaunch).
    func updateNow() {
        UpdateAnnouncementPanel.shared.hide()
        remindAfter = nil
        Updater.shared.checkForUpdates()
    }

    /// "Remind Me Later": quiet for a day.
    func remindLater() {
        remindAfter = Date().addingTimeInterval(24 * 3600)
        UpdateAnnouncementPanel.shared.hide()
    }

    /// Sparkle's own update window took over (or the update finished).
    func userSawUpdate() {
        UpdateAnnouncementPanel.shared.hide()
    }

    func showReleaseNotes() {
        UpdateAnnouncementPanel.shared.hide()
        NotificationCenter.default.post(name: .spiderNotchOpenSettings, object: "updates")
    }

    // MARK: - After an update

    /// On launch: if SpiderNotch was just updated, say what's new (once).
    func showWhatsNewIfUpdated() {
        let current = installedVersion
        let lastSeen = defaults.string(forKey: Preferences.Key.updateLastSeenVersion)
        defaults.set(current, forKey: Preferences.Key.updateLastSeenVersion)
        guard let previous = lastSeen, ReleaseNotes.compare(current, previous) == .orderedDescending else { return }
        remindAfter = nil
        let notes = ReleaseNotes.bundledNotes() ?? ""
        let release = ReleaseInfo(version: current, title: "SpiderNotch \(current)", date: nil, notes: notes,
                                  url: AppInfo.releasesURL.appendingPathComponent("tag/v\(current)"), isPrerelease: false)
        UpdateAnnouncementPanel.shared.show(.updated(release, kind: ReleaseNotes.kind(from: previous, to: current)), after: 2.5)
    }

    // MARK: - Release history (GitHub)

    /// Loads the list of releases from GitHub (at most every 10 minutes unless forced).
    func loadHistory(force: Bool = false) {
        guard !isLoadingHistory, force || Date().timeIntervalSince(lastHistoryLoad) > 600 else { return }
        isLoadingHistory = true
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppInfo.repository)/releases?per_page=30")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SpiderNotch/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let releases = data.map(ReleaseNotes.parseGitHubReleases) ?? []
            Task { @MainActor in
                let center = UpdateCenter.shared
                center.isLoadingHistory = false
                center.lastHistoryLoad = Date()
                if let error = error {
                    center.historyError = "Couldn't reach GitHub: \(error.localizedDescription)"
                } else if code != 200 {
                    center.historyError = code == 403 ? "GitHub is busy right now (rate limit). Try again later." : "GitHub answered with error \(code)."
                } else {
                    center.historyError = nil
                    center.history = releases.sorted { ReleaseNotes.compare($0.version, $1.version) == .orderedDescending }
                }
            }
        }.resume()
    }
}

extension Notification.Name {
    /// Opens Settings; `object` is the section ("updates", "cocoon"…).
    static let spiderNotchOpenSettings = Notification.Name("SpiderNotchOpenSettings")
}
