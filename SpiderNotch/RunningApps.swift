//
//  RunningApps.swift
//  SpiderNotch
//
//  Keeps a live list of the apps you have open (the ones with a Dock icon),
//  remembers which one you were using last, and switches to an app.
//  Nothing is hard-coded: everything comes straight from macOS (NSWorkspace),
//  and the list updates by itself when apps open, quit, hide or come forward.
//

import AppKit

@MainActor
final class RunningApps: NSObject {
    /// Open apps: Finder first, then in the order you opened them.
    private(set) var apps: [NSRunningApplication] = []
    /// The app you were using most recently (never SpiderNotch itself).
    private(set) var activeApp: NSRunningApplication?
    /// Called whenever the list or the active app changes.
    var onChange: (@MainActor () -> Void)?

    private let myProcessID = NSRunningApplication.current.processIdentifier
    private var isWatching = false

    // MARK: - Watching macOS

    func start() {
        guard !isWatching else { return }
        isWatching = true

        let center = NSWorkspace.shared.notificationCenter
        let listChanges: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in listChanges {
            center.addObserver(self, selector: #selector(appListChanged(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != myProcessID {
            activeApp = front
        }
        reload()
    }

    @objc private func appListChanged(_ notification: Notification) {
        reload()
    }

    @objc private func appActivated(_ notification: Notification) {
        let key = NSWorkspace.applicationUserInfoKey
        if let app = notification.userInfo?[key] as? NSRunningApplication,
           app.processIdentifier != myProcessID {
            activeApp = app
        }
        reload()
    }

    /// Reads the list of open apps from macOS again.
    func reload() {
        let mine = myProcessID
        var list = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != mine
        }
        list.sort { first, second in
            let firstIsFinder = first.bundleIdentifier == "com.apple.finder"
            let secondIsFinder = second.bundleIdentifier == "com.apple.finder"
            if firstIsFinder != secondIsFinder {
                return firstIsFinder
            }
            let firstDate = first.launchDate ?? Date.distantFuture
            let secondDate = second.launchDate ?? Date.distantFuture
            if firstDate != secondDate {
                return firstDate < secondDate
            }
            return first.processIdentifier < second.processIdentifier
        }
        apps = list
        if let active = activeApp, active.isTerminated {
            activeApp = nil
        }
        onChange?()
    }

    // MARK: - Switching apps

    /// Brings an app to the front, like clicking its icon in the Dock.
    func activate(_ app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }
        // macOS 14+ "cooperative activation": SpiderNotch (the active app while the
        // island is open) hands the focus over to the app you picked.
        NSApp.yieldActivation(to: app)
        app.activate(from: NSRunningApplication.current, options: [.activateAllWindows])

        // If macOS didn't switch (it's allowed to refuse), open the app the way
        // the Dock does. That always brings it forward.
        let processID = app.processIdentifier
        let appURL = app.bundleURL
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != processID {
                RunningApps.openLikeTheDock(appURL)
            }
        }
    }

    /// Gives the focus back to an app (used when the switcher closes without a choice).
    func returnFocus(to app: NSRunningApplication?) {
        guard let app = app, !app.isTerminated, NSApp.isActive else { return }
        NSApp.yieldActivation(to: app)
        app.activate(from: NSRunningApplication.current, options: [])
    }

    private static func openLikeTheDock(_ url: URL?) {
        guard let url = url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
}
