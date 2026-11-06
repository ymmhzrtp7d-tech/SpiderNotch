//
//  Preferences.swift
//  SpiderNotch
//
//  Every setting SpiderNotch remembers. They're saved in UserDefaults,
//  macOS's built-in storage for small app settings.
//

import Foundation
import ServiceManagement

enum Preferences {
    /// The names the settings are saved under.
    enum Key {
        static let enabled = "enabled"
        static let stickerSize = "stickerSize"
        static let webLength = "webLength"
        static let swing = "swing"
        static let bounce = "bounce"
        static let virtualNotch = "virtualNotch"
        static let launchAtLogin = "launchAtLogin"
        static let hasSaidHello = "hasSaidHello"

        // Characters and appearance (1.2)
        static let characterID = "characterID"
        static let animationSpeed = "animationSpeed"
        static let entrance = "entranceStyle"
        static let floatAmount = "floatAmount"
        static let border = "borderStyle"
        static let position = "stickerPosition"
        static let migratedLegacySticker = "migratedLegacySticker"

        // Now Playing (1.2)
        static let nowPlaying = "nowPlayingEnabled"

        // Cocoon, the file hub (1.4)
        static let cocoonEnabled = "cocoonEnabled"
        static let cocoonOpenOnHover = "cocoonOpenOnHover"
        static let cocoonRecentHours = "cocoonRecentHours"
        static let cocoonShowDownloads = "cocoonShowDownloads"

        // Update announcements (1.4)
        static let updateNotify = "updateNotifyEnabled"
        static let updateRemindAfter = "updateRemindAfter"
        static let updateLastSeenVersion = "updateLastSeenVersion"
        static let updateAnnouncedVersion = "updateAnnouncedVersion"

        // Which part of the Settings window was open last.
        static let settingsSection = "settingsSection"
        static let libraryCategory = "libraryCategory"
    }

    /// The values used until you change something.
    enum Default {
        static let enabled = true
        static let stickerSize: Double = 78
        static let webLength: Double = 72
        static let swing: Double = 1.0
        static let bounce: Double = 0.55
        static let virtualNotch = true
        static let characterID = "builtin:spider"
        static let animationSpeed: Double = 1.0
        static let entrance = EntranceStyle.thread.rawValue
        static let floatAmount: Double = 1.0
        static let border = BorderStyle.white.rawValue
        static let position = StickerPosition.center.rawValue
        static let nowPlaying = true
        static let cocoonEnabled = true
        static let cocoonOpenOnHover = true
        static let cocoonRecentHours: Double = 24
        static let cocoonShowDownloads = false
        static let updateNotify = true
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.enabled: Default.enabled,
            Key.stickerSize: Default.stickerSize,
            Key.webLength: Default.webLength,
            Key.swing: Default.swing,
            Key.bounce: Default.bounce,
            Key.virtualNotch: Default.virtualNotch,
            Key.launchAtLogin: false,
            Key.characterID: Default.characterID,
            Key.animationSpeed: Default.animationSpeed,
            Key.entrance: Default.entrance,
            Key.floatAmount: Default.floatAmount,
            Key.border: Default.border,
            Key.position: Default.position,
            Key.nowPlaying: Default.nowPlaying,
            Key.cocoonEnabled: Default.cocoonEnabled,
            Key.cocoonOpenOnHover: Default.cocoonOpenOnHover,
            Key.cocoonRecentHours: Default.cocoonRecentHours,
            Key.cocoonShowDownloads: Default.cocoonShowDownloads,
            Key.updateNotify: Default.updateNotify,
            Key.settingsSection: "library",
            Key.libraryCategory: "all",
        ])
    }
}

/// How the character arrives at the notch (and leaves again).
enum EntranceStyle: String, CaseIterable, Identifiable {
    /// Drops down on a silk thread and climbs back up (the classic spider).
    case thread
    /// Peeks out from under the notch and slides back in.
    case peek
    /// Pops out with a springy bounce and floats, then shrinks away.
    case pop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thread: return "Drop on a Thread"
        case .peek: return "Peek Out"
        case .pop: return "Pop & Float"
        }
    }
}

/// The edge drawn around every character, like a die-cut sticker.
enum BorderStyle: String, CaseIterable, Identifiable {
    case none
    case white
    case outline
    case glow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .white: return "White Sticker Edge"
        case .outline: return "Dark Outline"
        case .glow: return "Soft Glow"
        }
    }
}

/// Where the character hangs: under the middle of the notch, or near one of its corners.
enum StickerPosition: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }
}

/// A snapshot of all the settings at one moment.
struct SpiderSettings: Equatable {
    var enabled: Bool
    var stickerSize: CGFloat
    var webLength: CGFloat
    var swing: CGFloat
    var bounce: CGFloat
    var virtualNotch: Bool
    var speed: CGFloat
    var entrance: EntranceStyle
    var floatAmount: CGFloat
    var border: BorderStyle
    var position: StickerPosition
    var characterID: String
    var nowPlaying: Bool

    static func current() -> SpiderSettings {
        let defaults = UserDefaults.standard
        return SpiderSettings(
            enabled: defaults.bool(forKey: Preferences.Key.enabled),
            stickerSize: clamp(defaults.double(forKey: Preferences.Key.stickerSize), 40, 160),
            webLength: clamp(defaults.double(forKey: Preferences.Key.webLength), 20, 240),
            swing: clamp(defaults.double(forKey: Preferences.Key.swing), 0, 2),
            bounce: clamp(defaults.double(forKey: Preferences.Key.bounce), 0, 1),
            virtualNotch: defaults.bool(forKey: Preferences.Key.virtualNotch),
            speed: clamp(defaults.double(forKey: Preferences.Key.animationSpeed), 0.5, 2),
            entrance: EntranceStyle(rawValue: defaults.string(forKey: Preferences.Key.entrance) ?? "") ?? .thread,
            floatAmount: clamp(defaults.double(forKey: Preferences.Key.floatAmount), 0, 2),
            border: BorderStyle(rawValue: defaults.string(forKey: Preferences.Key.border) ?? "") ?? .white,
            position: StickerPosition(rawValue: defaults.string(forKey: Preferences.Key.position) ?? "") ?? .center,
            characterID: defaults.string(forKey: Preferences.Key.characterID) ?? Preferences.Default.characterID,
            nowPlaying: defaults.bool(forKey: Preferences.Key.nowPlaying)
        )
    }

    /// The same settings with nothing that affects how the character looks or moves.
    var motionAndLooks: SpiderSettings {
        var copy = self
        copy.enabled = true
        copy.nowPlaying = true
        copy.characterID = ""
        copy.border = .none
        return copy
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> CGFloat {
        CGFloat(min(max(value, low), high))
    }
}

/// Turning "Launch at login" on and off (uses macOS's Login Items).
enum LoginItem {
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Facts about this copy of the app.
enum AppInfo {
    /// The version people see, like "1.2.0" (set by the build scripts from the VERSION file).
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    /// The build number, like "202611061136" (always goes up; Sparkle compares it).
    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    /// The GitHub repository, like "owner/SpiderNotch" (written in by the build
    /// scripts from scripts/release.conf).
    static var repository: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "SpiderNotchRepository") as? String) ?? ""
        return value.isEmpty ? "ymmhzrtp7d-tech/SpiderNotch" : value
    }

    static var repositoryURL: URL { URL(string: "https://github.com/\(repository)")! }
    static var releasesURL: URL { repositoryURL.appendingPathComponent("releases") }
    static var changelogURL: URL { repositoryURL.appendingPathComponent("blob/main/CHANGELOG.md") }
    static var privacyURL: URL { repositoryURL.appendingPathComponent("blob/main/PRIVACY.md") }
    static var licenseURL: URL { repositoryURL.appendingPathComponent("blob/main/LICENSE") }
    static var helpURL: URL { repositoryURL.appendingPathComponent("blob/main/docs/TROUBLESHOOTING.md") }

    /// Opens a new GitHub issue with the bug report form, pre-filled with this Mac's details.
    static var bugReportURL: URL {
        var parts = URLComponents(url: repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        parts.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: "\(version) (\(build))"),
            URLQueryItem(name: "macos", value: "macOS \(os), \(machineKind)"),
        ]
        return parts.url!
    }

    static var featureRequestURL: URL {
        var parts = URLComponents(url: repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "template", value: "feature_request.yml")]
        return parts.url!
    }

    /// "Apple silicon" or "Intel".
    static var machineKind: String {
        #if arch(arm64)
        return "Apple silicon"
        #else
        return "Intel"
        #endif
    }

    /// Where Sparkle looks for updates (nil if this build has no feed).
    static var feedURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !value.isEmpty else { return nil }
        return URL(string: value)
    }

    /// The public update key (nil if this build has none).
    static var updateKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !value.isEmpty else { return nil }
        return value
    }

    /// SpiderNotch's own folder in ~/Library/Application Support.
    static var supportFolder: URL {
        // Automated UI checks run with their own folder, so they never touch your stickers or Cocoon.
        if ProcessInfo.processInfo.arguments.contains("-SpiderNotchSupportFolder"),
           let override = UserDefaults.standard.string(forKey: "SpiderNotchSupportFolder") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SpiderNotch", isDirectory: true)
    }
}

extension Notification.Name {
    /// Posted when the character changes (you picked another one, or edited a sticker).
    static let spiderNotchStickerChanged = Notification.Name("SpiderNotchStickerChanged")
    /// Posted when you ask for a test drop. `object` may be a character ID to try out.
    static let spiderNotchDemo = Notification.Name("SpiderNotchDemo")
    /// Posted when your saved stickers change (added, renamed, deleted).
    static let spiderNotchStickersChanged = Notification.Name("SpiderNotchStickersChanged")
    /// Posted when the media that's playing changes.
    static let spiderNotchMediaChanged = Notification.Name("SpiderNotchMediaChanged")
}
