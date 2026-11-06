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
//    • Background checks don't pop up a window: UpdateCenter shows a quiet card
//      and a menu bar dot instead ("gentle reminders"). "Update Now" then opens
//      Sparkle's own window, which downloads, verifies, installs and relaunches.
//    • Settings, stickers and the Cocoon live outside the app (UserDefaults and
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
                                                      updaterDelegate: self,
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
            UpdateCenter.shared.checkStarted()
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

    /// Checks quietly in the background (results go to the Update Center and the card).
    func checkInBackground() {
        #if canImport(Sparkle)
        controller?.updater.checkForUpdatesInBackground()
        #endif
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
// Sparkle calls these on the main thread.
extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        let title = item.title
        let date = item.date
        let notes = item.itemDescription
        MainActor.assumeIsolated {
            UpdateCenter.shared.found(version: version, title: title, date: date, htmlNotes: notes)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            UpdateCenter.shared.noUpdateFound()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        // "No update found" and "cancelled" aren't failures.
        // (Sparkle's codes: 1001 no update, 4007 cancelled, 2001 download, 3001/3002 signature.)
        if nsError.domain == SUSparkleErrorDomain, [1001, 4007].contains(nsError.code) {
            return
        }
        var message = error.localizedDescription
        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case 2001:
                message = "The download was interrupted. Check your internet connection and try again: nothing was installed."
            case 3001, 3002:
                message = "The update's signature didn't check out, so it was NOT installed. Please try again later or download it from GitHub."
            default:
                break
            }
        }
        MainActor.assumeIsolated {
            UpdateCenter.shared.failed(message)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {}
}

// SpiderNotch is a menu bar app with no Dock icon, so update alerts that pop up
// on their own could hide behind other windows or interrupt you. With Sparkle's
// "gentle reminders", background checks hand the news to UpdateCenter (a quiet
// card + menu bar dot) instead, and Sparkle's window opens when you ask for it.
extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                         andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                // Sparkle's window is opening (you asked): bring it to the front.
                NSApp.activate()
                UpdateCenter.shared.userSawUpdate()
            } else {
                UpdateCenter.shared.announceIfAppropriate()
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            UpdateCenter.shared.userSawUpdate()
        }
    }
}
#endif
