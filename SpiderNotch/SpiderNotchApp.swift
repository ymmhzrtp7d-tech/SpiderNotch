//
//  SpiderNotchApp.swift
//  SpiderNotch
//
//  Where the app starts. SpiderNotch has no Dock icon and no main window:
//  it lives in the menu bar and quietly waits for your mouse at the notch.
//

import AppKit
import Combine

// The test runner (Tests/) builds every file with SPIDERNOTCH_TESTS and brings its own @main.
#if !SPIDERNOTCH_TESTS
@main
enum SpiderNotchApp {
    /// The very first code that runs when the app launches.
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // "Accessory" means no Dock icon and no app menu: perfect for a menu bar app.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
#endif

/// Sets everything up once the app has launched, and owns the menu bar icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private var enabledMenuItem: NSMenuItem?
    private var cocoonMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var updateObserver: AnyCancellable?
    private var settingsWindow: SettingsWindowController?
    private var lastLaunchAtLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        // Writing to a helper that has just quit must not crash the app.
        signal(SIGPIPE, SIG_IGN)
        // Stickers from SpiderNotch 1.0/1.1 become your first saved sticker.
        StickerStore.shared.migrateLegacyStickerIfNeeded()

        // Start with the "Launch at login" switch matching what macOS really has.
        let launchesAtLogin = LoginItem.isEnabled
        UserDefaults.standard.set(launchesAtLogin, forKey: Preferences.Key.launchAtLogin)
        lastLaunchAtLogin = launchesAtLogin

        let notch = NotchController()
        self.notch = notch
        setUpMenuBarIcon()

        // Whenever a setting changes (from the menu or the Settings window), apply it right away.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        notch.start()
        Updater.shared.start()
        observeUpdates()
        UpdateCenter.shared.showWhatsNewIfUpdated()
        NotificationCenter.default.addObserver(forName: .spiderNotchOpenSettings, object: nil, queue: .main) { [weak self] note in
            let section = note.object as? String
            MainActor.assumeIsolated {
                self?.showSettings(section: section)
            }
        }
        runTestingHooks()

        // The very first time the app runs, the character says hi so you can see it works.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Preferences.Key.hasSaidHello) {
            defaults.set(true, forKey: Preferences.Key.hasSaidHello)
            notch.showDemo(after: 1.0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.stop()
    }

    // MARK: - Menu bar icon

    private func setUpMenuBarIcon() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MenuBarIcon.make()
            button.toolTip = "SpiderNotch"
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "SpiderNotch \(AppInfo.version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // Shown only while an update is waiting.
        let availableItem = NSMenuItem(title: "Update Available…", action: #selector(installUpdate(_:)), keyEquivalent: "")
        availableItem.target = self
        availableItem.isHidden = true
        menu.addItem(availableItem)
        updateMenuItem = availableItem
        menu.addItem(NSMenuItem.separator())

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        enabledMenuItem = enabledItem

        let dropItem = NSMenuItem(title: "Say Hi Now", action: #selector(dropNow(_:)), keyEquivalent: "")
        dropItem.target = self
        menu.addItem(dropItem)

        menu.addItem(NSMenuItem.separator())

        let cocoonItem = NSMenuItem(title: "Open Cocoon", action: #selector(openCocoon(_:)), keyEquivalent: "")
        cocoonItem.target = self
        cocoonItem.toolTip = "Your files, in the island at the notch"
        menu.addItem(cocoonItem)
        cocoonMenuItem = cocoonItem

        menu.addItem(NSMenuItem.separator())

        let charactersItem = NSMenuItem(title: "Characters…", action: #selector(openCharacters(_:)), keyEquivalent: "")
        charactersItem.target = self
        menu.addItem(charactersItem)

        let stickersItem = NSMenuItem(title: "My Stickers…", action: #selector(openStickers(_:)), keyEquivalent: "")
        stickersItem.target = self
        menu.addItem(stickersItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(title: "About SpiderNotch", action: #selector(openAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SpiderNotch", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        refreshMenu()
    }

    /// Updates the checkmark next to "Enabled" and dims the icon when switched off.
    private func refreshMenu() {
        let isEnabled = UserDefaults.standard.bool(forKey: Preferences.Key.enabled)
        enabledMenuItem?.state = isEnabled ? .on : .off
        cocoonMenuItem?.isHidden = !UserDefaults.standard.bool(forKey: Preferences.Key.cocoonEnabled)
        statusItem?.button?.appearsDisabled = !isEnabled
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.bool(forKey: Preferences.Key.enabled)
        defaults.set(!isEnabled, forKey: Preferences.Key.enabled)
        // preferencesDidChange(_:) runs automatically after this.
    }

    @objc private func dropNow(_ sender: Any?) {
        notch?.showDemo()
    }

    @objc private func openCocoon(_ sender: Any?) {
        // Let the menu finish closing first, so its click doesn't close the island.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.notch?.openCocoon(explicit: true)
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        showSettings(section: nil)
    }

    @objc private func openCharacters(_ sender: Any?) {
        showSettings(section: "library")
    }

    @objc private func openStickers(_ sender: Any?) {
        showSettings(section: "stickers")
    }

    @objc private func installUpdate(_ sender: Any?) {
        UpdateCenter.shared.updateNow()
    }

    /// The menu bar dot and the "Update Available" menu item follow the Update Center.
    private func observeUpdates() {
        updateObserver = UpdateCenter.shared.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] release in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    self.statusItem?.button?.image = MenuBarIcon.make(badge: release != nil)
                    if let release = release {
                        let kind = ReleaseNotes.kind(from: AppInfo.version, to: release.version)
                        let title = NSMutableAttributedString(string: "Update Available: \(release.version)…",
                                                              attributes: [.font: NSFont.menuFont(ofSize: 0).bold])
                        title.append(NSAttributedString(string: "  \(kind.label)",
                                                        attributes: [.font: NSFont.menuFont(ofSize: 11),
                                                                     .foregroundColor: NSColor.secondaryLabelColor]))
                        self.updateMenuItem?.attributedTitle = title
                        self.updateMenuItem?.isHidden = false
                        self.statusItem?.button?.toolTip = "SpiderNotch: version \(release.version) is available"
                    } else {
                        self.updateMenuItem?.isHidden = true
                        self.statusItem?.button?.toolTip = "SpiderNotch"
                    }
                }
            }
    }

    /// Launch options used by the automated UI checks (scripts/ui-check.sh):
    /// -SpiderNotchOpenCocoon YES opens the Cocoon, -SpiderNotchOpenSettings <section> opens Settings.
    private func runTestingHooks() {
        let defaults = UserDefaults.standard
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SpiderNotchOpenCocoon") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.notch?.openCocoon(explicit: true)
            }
        }
        if args.contains("-SpiderNotchOpenSettings"), let section = defaults.string(forKey: "SpiderNotchOpenSettings") {
            showSettings(section: section)
        }
        if args.contains("-SpiderNotchShowAnnouncement") {
            let notes = ReleaseNotes.bundledNotes() ?? "- Bug fixes and improvements."
            let release = ReleaseInfo(version: "9.9.9", title: "SpiderNotch 9.9.9", date: Date(), notes: notes,
                                      url: AppInfo.releasesURL, isPrerelease: false)
            UpdateAnnouncementPanel.shared.show(.available(release, kind: ReleaseNotes.kind(from: AppInfo.version, to: "9.9.9")), after: 1)
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        Updater.shared.checkForUpdates()
    }

    @objc private func openAbout(_ sender: Any?) {
        showSettings(section: "about")
    }

    private func showSettings(section: String?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.show(section: section)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Settings changes

    @objc private func preferencesDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            applyPreferences()
        } else {
            Task { @MainActor [weak self] in
                self?.applyPreferences()
            }
        }
    }

    private func applyPreferences() {
        refreshMenu()
        updateLaunchAtLogin()
        notch?.reloadSettings()
    }

    /// Turns "Launch at login" on or off when you flip the switch in Settings.
    private func updateLaunchAtLogin() {
        let defaults = UserDefaults.standard
        let wanted = defaults.bool(forKey: Preferences.Key.launchAtLogin)
        guard wanted != lastLaunchAtLogin else { return } // the switch didn't move
        lastLaunchAtLogin = wanted
        guard wanted != LoginItem.isEnabled else { return }

        var problem: String?
        do {
            try LoginItem.setEnabled(wanted)
        } catch {
            problem = error.localizedDescription
        }

        let actual = LoginItem.isEnabled
        if actual != wanted {
            // It didn't work, so flip the switch back to match reality.
            lastLaunchAtLogin = actual
            defaults.set(actual, forKey: Preferences.Key.launchAtLogin)
        }

        if let problem = problem {
            Task { @MainActor in
                Alerts.show(title: "Couldn't change Launch at Login",
                            message: "\(problem)\n\nYou can also add SpiderNotch yourself in System Settings → General → Login Items.")
            }
        } else if wanted && LoginItem.needsApproval {
            Task { @MainActor in
                Alerts.show(title: "One more step",
                            message: "macOS wants you to allow SpiderNotch under Login Items. System Settings will open next.")
                LoginItem.openSystemSettings()
            }
        }
    }
}
