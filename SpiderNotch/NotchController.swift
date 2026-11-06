//
//  NotchController.swift
//  SpiderNotch
//
//  The "brain": it puts the see-through window at the notch, listens to the
//  mouse, tells the character when to come out and when to go back, opens the
//  Now Playing island when you hover while something plays, and opens the
//  app switcher when you click the character.
//
//    hover the notch, nothing playing  → the character comes out
//    hover the notch, media playing    → the Now Playing island opens and the
//                                        character hangs just below it
//    click the character               → the app switcher
//    click the song / video            → jump to where it's playing
//    move away                         → everything goes back into the notch
//

import AppKit

@MainActor
final class NotchController: NSObject {
    private var watcher: MouseWatcher?
    private var panel: NotchPanel?
    private var stage: SpiderStageView?
    private var geometry: NotchGeometry?
    private var layout: StageLayout?
    private var sticker: Sticker?
    private var settings = SpiderSettings.current()
    private let island = IslandController()
    private let media = MediaCenter.shared

    /// A character you're trying on ("Try on Notch"), shown until it goes back in.
    private var trialID: String?
    /// Extra room below the notch for the character (while the Now Playing island is open).
    private var extraDrop: CGFloat = 0

    private var dropTask: Task<Void, Never>?
    private var retractTask: Task<Void, Never>?
    private var demoUntil = Date.distantPast
    private var cursorWasOnSpider = false
    private var lastPoke = Date.distantPast
    /// True while clicks are allowed to land on the character (cursor right on it).
    private var stickerClickable = false

    /// How long the cursor must rest on the notch before anything happens (avoids accidents).
    private let hoverDelay: UInt64 = 90_000_000      // 0.09 seconds
    /// How long it waits after you move away before going back in.
    private let leaveDelay: UInt64 = 350_000_000     // 0.35 seconds
    /// The same, while the Now Playing island is open (a little more forgiving).
    private let islandLeaveDelay: UInt64 = 450_000_000

    // MARK: - Start & stop

    func start() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensDidChange(_:)),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(stickerDidChange(_:)),
                           name: .spiderNotchStickerChanged, object: nil)
        center.addObserver(self, selector: #selector(demoRequested(_:)),
                           name: .spiderNotchDemo, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensDidChange(_:)),
                                                          name: NSWorkspace.didWakeNotification, object: nil)

        watcher = MouseWatcher { [weak self] location, deltaX in
            self?.mouseMoved(to: location, deltaX: deltaX)
        }
        island.onClose = { [weak self] in
            self?.islandDidClose()
        }
        island.onClickOutsideIsland = { [weak self] point in
            self?.clickedBesideIsland(at: point)
        }
        island.onOpenMediaSource = { [weak self] session in
            self?.openMediaSource(session)
        }
        island.start()

        media.onChange = { [weak self] in
            self?.island.refreshNowPlaying()
        }
        media.start()

        loadSticker()
        rebuild()
        updateWatcher()
    }

    func stop() {
        watcher?.stop()
        island.close(returnFocus: false)
        media.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Re-reads the settings and applies whatever changed.
    func reloadSettings() {
        let newSettings = SpiderSettings.current()
        guard newSettings != settings else { return }
        let old = settings
        settings = newSettings

        if newSettings.enabled != old.enabled {
            updateWatcher()
        }
        if !newSettings.nowPlaying && island.isOpen && island.mode == .nowPlaying {
            island.close(returnFocus: false)
        }
        if newSettings.characterID != old.characterID || newSettings.border != old.border {
            loadSticker()
            rebuild()
        } else if newSettings.motionAndLooks != old.motionAndLooks {
            rebuild() // size, speed, style, position, swing... changed
        }
    }

    // MARK: - Building the window

    /// Loads the character's pictures (with the chosen sticker edge).
    private func loadSticker() {
        sticker = Characters.loadSticker(id: trialID ?? settings.characterID, border: settings.border)
    }

    private func rebuild() {
        let wasOut = self.stage?.isOut ?? false

        guard let geometry = NotchGeometry.detect(allowVirtualNotch: self.settings.virtualNotch) else {
            // No screen to use (no notch, and the pretend notch is switched off).
            self.geometry = nil
            self.layout = nil
            self.stage?.hideNow()
            self.panel?.orderOut(nil)
            return
        }

        let sticker: Sticker
        if let loaded = self.sticker {
            sticker = loaded
        } else {
            sticker = Characters.loadSticker(id: trialID ?? settings.characterID, border: settings.border)
            self.sticker = sticker
        }

        let layout = StageLayout(geometry: geometry, settings: settings, sticker: sticker, extraDrop: extraDrop)
        self.geometry = geometry
        self.layout = layout

        let panel: NotchPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NotchPanel(frame: layout.panelFrame)
            self.panel = panel
        }
        panel.setFrame(layout.panelFrame, display: false)

        let stage: SpiderStageView
        if let existing = self.stage {
            stage = existing
        } else {
            stage = SpiderStageView(frame: NSRect(origin: .zero, size: layout.panelFrame.size))
            stage.onStickerClick = { [weak self] in
                self?.stickerClicked()
            }
            stage.onMouseExit = { [weak self] in
                self?.setStickerClickable(false)
            }
            panel.contentView = stage
            self.stage = stage
        }
        stage.setFrameSize(layout.panelFrame.size)
        stage.configure(layout: layout, sticker: sticker, scale: geometry.backingScale)

        if wasOut {
            panel.orderFrontRegardless()
            stage.showHanging()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: - Mouse

    private func mouseMoved(to point: NSPoint, deltaX: CGFloat) {
        // While the app switcher is open, it decides what happens.
        if island.isOpen && island.mode == .apps {
            island.mouseMoved(to: point)
            return
        }

        guard settings.enabled,
              let geometry = geometry,
              let layout = layout,
              let stage = stage
        else { return }

        let isOut = stage.isOut
        let islandRect = island.isOpen ? island.islandScreenRect : nil

        // Clicks may land on the character only while the cursor is right on it;
        // everywhere else they pass straight through to your apps.
        setStickerClickable(isOut && stage.stickerContains(screenPoint: point))

        // Quick exit: the cursor is far from the notch and nothing is happening.
        if !isOut && dropTask == nil && islandRect == nil && point.y < geometry.hotZone.minY - 60 {
            return
        }

        var inside = geometry.hotZone.contains(point) || (isOut && layout.keepAliveZone.contains(point))
        if let rect = islandRect, rect.insetBy(dx: -18, dy: -18).contains(point) {
            inside = true
        }
        if island.isInteracting {
            inside = true // dragging a slider: stay open even if the cursor slips outside
        }
        if inside {
            cancelRetract()
            if !isOut && dropTask == nil {
                scheduleDrop()
            }
        } else {
            cancelDrop()
            if (isOut || islandRect != nil) && retractTask == nil && Date() >= demoUntil {
                scheduleRetract(after: islandRect != nil ? islandLeaveDelay : leaveDelay)
            }
        }

        // Bumping into the character gives it a push.
        let onSpider = isOut && layout.stickerZone.contains(point)
        if onSpider && !cursorWasOnSpider && Date().timeIntervalSince(lastPoke) > 0.3 {
            lastPoke = Date()
            stage.poke(deltaX: deltaX)
        }
        cursorWasOnSpider = onSpider
    }

    private func scheduleDrop() {
        let delay = hoverDelay
        dropTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self = self, !Task.isCancelled else { return }
            self.dropTask = nil
            self.dropNow()
        }
    }

    private func scheduleRetract(after delay: UInt64) {
        retractTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self = self, !Task.isCancelled else { return }
            self.retractTask = nil
            self.retractNow()
        }
    }

    private func cancelDrop() {
        dropTask?.cancel()
        dropTask = nil
    }

    private func cancelRetract() {
        retractTask?.cancel()
        retractTask = nil
    }

    /// Brings the character out, and the Now Playing island too if something is playing.
    private func dropNow(allowMedia: Bool = true) {
        guard let stage = stage, let geometry = geometry else { return }
        let showMedia = allowMedia && settings.enabled && settings.nowPlaying && !island.isOpen
            && media.hasSomethingToShow && media.currentSession != nil

        // Make room for the island before the character comes out.
        if !stage.isOut {
            var wanted: CGFloat = 0
            if showMedia {
                wanted = IslandController.nowPlayingDepth(geometry: geometry)
            } else if island.isOpen && island.mode == .nowPlaying {
                wanted = island.depthBelowNotch
            }
            if wanted != extraDrop {
                extraDrop = wanted
                rebuild()
            }
        }
        if showMedia {
            island.openNowPlaying(geometry: geometry)
        }
        guard let panel = panel, let current = self.stage else { return }
        panel.orderFrontRegardless()
        current.drop()
    }

    /// Sends everything back into the notch (the Now Playing island too).
    private func retractNow() {
        guard let stage = stage else { return }
        setStickerClickable(false)
        if island.isOpen && island.mode == .nowPlaying {
            island.close(returnFocus: false)
        }
        stage.climb { [weak self] in
            // Once it's gone, take the window off screen entirely: zero cost while hidden.
            self?.panel?.orderOut(nil)
            self?.finishTrialIfNeeded()
        }
    }

    private func setStickerClickable(_ clickable: Bool) {
        guard clickable != stickerClickable else { return }
        stickerClickable = clickable
        panel?.ignoresMouseEvents = !clickable
    }

    // MARK: - Clicking

    /// You clicked the character: a happy hop, then the app switcher.
    private func stickerClicked() {
        guard let stage = stage, stage.isOut, let geometry = geometry else { return }
        // Remember the app you're using before SpiderNotch takes the focus.
        let previousApp = NSWorkspace.shared.frontmostApplication
        if island.isOpen {
            // Now Playing is open: it turns into the app switcher.
            guard island.mode == .nowPlaying else { return }
            cancelDrop()
            cancelRetract()
            demoUntil = Date().addingTimeInterval(1.0)
            setStickerClickable(false)
            stage.celebrate()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard let self = self else { return }
                self.island.switchToApps(previousApp: previousApp)
                try? await Task.sleep(nanoseconds: 340_000_000)
                self.retractNow()
            }
            return
        }
        cancelDrop()
        cancelRetract()
        demoUntil = Date().addingTimeInterval(1.0) // stay out during the reaction
        setStickerClickable(false)
        stage.celebrate()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self = self else { return }
            self.island.open(geometry: geometry, previousApp: previousApp)
            // The island now covers it, so it can quietly go back into the notch.
            try? await Task.sleep(nanoseconds: 340_000_000)
            self.retractNow()
        }
    }

    /// A click in the island's shadow: maybe it was meant for the character.
    private func clickedBesideIsland(at point: NSPoint) {
        guard let stage = stage, stage.isOut, stage.stickerContains(screenPoint: point) else { return }
        stickerClicked()
    }

    /// You clicked the song or video: go to where it's playing.
    private func openMediaSource(_ session: MediaSession) {
        media.openSource(of: session)
        cancelDrop()
        cancelRetract()
        retractNow()
    }

    private func islandDidClose() {
        cursorWasOnSpider = false
        demoUntil = .distantPast
        setStickerClickable(false)
        // The character was hanging from the island: it goes back in too.
        if extraDrop > 0, stage?.isOut == true {
            retractNow()
        }
        // If the cursor is still at the notch, the next mouse move brings it out again.
    }

    // MARK: - Demo

    /// Brings the character out for a few seconds without hovering. Used for the
    /// first-launch hello, "Drop It Now", Test Drop and "Try on Notch".
    /// `characterID` tries another character for this one demo.
    func showDemo(after delay: TimeInterval = 0, characterID: String? = nil) {
        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self = self else { return }
            if let id = characterID, id != self.settings.characterID, Characters.exists(id) {
                if self.island.isOpen {
                    self.island.close(returnFocus: false)
                }
                self.trialID = id
                self.loadSticker()
                self.extraDrop = 0
                self.rebuild()
            } else if self.layout == nil || (self.extraDrop > 0 && self.stage?.isOut != true) {
                self.extraDrop = 0
                self.rebuild()
            }
            let showFor: TimeInterval = 3.5
            self.demoUntil = Date().addingTimeInterval(showFor)
            self.cancelRetract()
            self.dropNow(allowMedia: false)

            try? await Task.sleep(nanoseconds: UInt64((showFor + 0.1) * 1_000_000_000))
            // Go back in, unless another demo started or your cursor is on it.
            guard Date() >= self.demoUntil, !self.isCursorNearby() else { return }
            self.retractNow()
        }
    }

    /// After trying on a character, your own character comes back.
    private func finishTrialIfNeeded() {
        guard trialID != nil else { return }
        trialID = nil
        loadSticker()
        rebuild()
    }

    private func isCursorNearby() -> Bool {
        guard settings.enabled, let geometry = geometry, let layout = layout else { return false }
        let point = NSEvent.mouseLocation
        if let rect = island.islandScreenRect, rect.contains(point) {
            return true
        }
        return geometry.hotZone.contains(point) || layout.keepAliveZone.contains(point)
    }

    // MARK: - System events

    @objc private func screensDidChange(_ notification: Notification) {
        island.close(returnFocus: false)
        extraDrop = 0
        rebuild()
    }

    @objc private func stickerDidChange(_ notification: Notification) {
        loadSticker()
        rebuild()
    }

    @objc private func demoRequested(_ notification: Notification) {
        showDemo(characterID: notification.object as? String)
    }

    private func updateWatcher() {
        if settings.enabled {
            watcher?.start()
        } else {
            watcher?.stop()
            cancelDrop()
            cancelRetract()
            island.close(returnFocus: true)
            if stage?.isOut == true {
                retractNow()
            }
        }
    }
}
