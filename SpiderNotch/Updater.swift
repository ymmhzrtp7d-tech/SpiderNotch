//
//  Updater.swift
//  SpiderNotch
//
//  Automatic updates, powered by Sparkle (https://sparkle-project.org).
//
//  How it works:
//    • The app reads its update feed address (SUFeedURL) and the public half of
//      the update signing key (SUPublicEDKey) from Info.plist. The build scripts
//      write both in, from scripts/release.conf.
//    • The feed is `appcast.xml`, attached to the newest GitHub Release. Every
//      download it lists carries an EdDSA signature; Sparkle refuses anything
//      that doesn't match the public key built into this app.
//    • Settings and stickers live outside the app (UserDefaults and
//      ~/Library/Application Support/SpiderNotch), so an update never touches them.
//
//  If the app is built without Sparkle (for example from the Xcode project
//  without the framework), everything here still compiles: update checks just
//  open the GitHub Releases page instead.
//

import AppKit
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

/// The one place the rest of the app talks to about updates.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// True when Sparkle is built in and the feed is configured.
    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?

    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    private var observers: [AnyCancellable] = []
    #endif

    private override init() {
        super.init()
    }

    /// Starts Sparkle. Call once, after the app has finished launching.
    func start() {
        #if canImport(Sparkle)
        guard AppInfo.feedURL != nil, AppInfo.updateKey != nil else {
            NSLog("SpiderNotch: updates are off (no SUFeedURL/SUPublicEDKey in Info.plist).")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        let updater = controller.updater
        observers = [
            updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
                .sink { [weak self] value in self?.canCheckForUpdates = value },
            updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
                .sink { [weak self] value in self?.lastCheck = value },
        ]
        #endif
    }

    /// "Check for Updates…": shows Sparkle's window with the result.
    func checkForUpdates() {
        #if canImport(Sparkle)
        if let controller = controller {
            NSApp.activate()
            controller.checkForUpdates(nil)
            return
        }
        #endif
        // No updater built in: send people to the download page.
        NSWorkspace.shared.open(AppInfo.releasesURL)
    }

    /// Check quietly once a day (on by default).
    var automaticallyChecks: Bool {
        get {
            #if canImport(Sparkle)
            return controller?.updater.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }

    /// Download updates in the background and install them when the app quits.
    var automaticallyDownloads: Bool {
        get {
            #if canImport(Sparkle)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }
}

#if canImport(Sparkle)
// SpiderNotch is a menu bar app with no Dock icon, so update alerts that appear
// on their own could hide behind other windows. Sparkle's "gentle reminders"
// let us bring them forward politely.
extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        Task { @MainActor in
            NSApp.activate()
        }
    }
}
#endif
