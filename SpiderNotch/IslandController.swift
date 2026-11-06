//
//  IslandController.swift
//  SpiderNotch
//
//  Opens and closes the island, in one of three modes:
//
//  • The app switcher (when you click the character). It closes after you
//    pick an app, when you click outside it, when you press Esc, or a moment
//    after the mouse has wandered off.
//  • Now Playing (when you hover the notch while media is playing). It opens
//    without taking the keyboard focus from your app, and NotchController
//    closes it when the mouse leaves.
//  • The Cocoon (files you keep handy): opens on hover when it has files, or
//    when you drag files to the notch. It stays open while you use it, or as
//    long as you like with its pin button.
//

import AppKit

@MainActor
final class IslandController: NSObject {
    private(set) var isOpen = false
    private(set) var mode: IslandMode = .apps
    /// True while you're dragging one of the Now Playing sliders.
    private(set) var isInteracting = false
    /// Called once the island has finished closing.
    var onClose: (@MainActor () -> Void)?
    /// A click beside the island (in its shadow), in screen coordinates.
    var onClickOutsideIsland: (@MainActor (NSPoint) -> Void)?
    /// You clicked the song or video: open where it's playing.
    var onOpenMediaSource: (@MainActor (MediaSession) -> Void)?
    /// Whether to show the Now Playing ⟷ Cocoon tabs beside the notch.
    var tabsAvailable: (@MainActor () -> Bool)?

    /// True while the island must stay open even if the cursor wanders off
    /// (dragging a slider, dragging files, or the Cocoon is pinned open).
    var holdsOpen: Bool {
        guard isOpen, !isClosing else { return false }
        if isInteracting { return true }
        if mode == .files {
            let cocoon = CocoonModel.shared
            return cocoon.pinnedOpen || cocoon.stayUntilClickOutside || cocoon.isDraggingFiles || cocoon.draggingID != nil
        }
        return false
    }

    /// You clicked inside the Cocoon: it waits longer before closing by itself.
    var isEngaged: Bool {
        isOpen && mode == .files && CocoonModel.shared.engaged
    }

    private let apps = RunningApps()
    private var panel: IslandPanel?
    private var islandView: IslandView?
    private var metrics: IslandMetrics?
    private var geometry: NotchGeometry?
    private var previousApp: NSRunningApplication?
    private var clickMonitors: [Any] = []
    private var awayTask: Task<Void, Never>?
    private var isClosing = false
    private var isPicking = false

    /// How long the app switcher waits after the mouse leaves before closing by itself.
    private let awayDelay: UInt64 = 1_600_000_000 // 1.6 seconds

    func start() {
        apps.onChange = { [weak self] in
            self?.appsChanged()
        }
        apps.start()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive(_:)),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    /// The open island in screen coordinates.
    var islandScreenRect: NSRect? {
        guard isOpen, let metrics = metrics else { return nil }
        return metrics.islandScreenRect
    }

    /// How far the open island reaches below the notch (the character hangs below it).
    var depthBelowNotch: CGFloat {
        guard isOpen, let metrics = metrics else { return 0 }
        return max(metrics.islandRect.height - metrics.notchRect.height, 0)
    }

    /// How far the Now Playing island will reach below the notch, before it opens.
    static func nowPlayingDepth(geometry: NotchGeometry) -> CGFloat {
        let metrics = IslandMetrics(geometry: geometry, contentSize: NowPlayingMetrics.contentSize)
        return max(metrics.islandRect.height - metrics.notchRect.height, 0)
    }

    // MARK: - Opening

    /// Opens the app switcher from the notch. `previousApp` is the app you were using.
    func open(geometry: NotchGeometry, previousApp: NSRunningApplication?) {
        guard !isOpen else { return }
        rememberPreviousApp(previousApp)
        apps.reload()
        let newMetrics = IslandMetrics(geometry: geometry, contentSize: IslandMetrics.appsContentSize(appCount: apps.apps.count))
        present(mode: .apps, geometry: geometry, metrics: newMetrics)
        // You clicked the character, so SpiderNotch takes the focus for a moment.
        // Being the active app is what lets it hand the focus to the app you pick.
        NSApp.activate()
        panel?.makeKey()
    }

    /// Opens Now Playing from the notch, without taking the focus from your app.
    func openNowPlaying(geometry: NotchGeometry) {
        openHover(.nowPlaying, geometry: geometry)
    }

    /// Opens the Cocoon. `explicit` (from the menu) takes the keyboard and keeps it
    /// open until you click outside; otherwise it behaves like Now Playing on hover.
    func openFiles(geometry: NotchGeometry, explicit: Bool = false) {
        if isOpen {
            if mode != .files { switchHover(to: .files) }
        } else {
            openHover(.files, geometry: geometry)
        }
        if explicit {
            CocoonModel.shared.engaged = true
            NSApp.activate()
            panel?.makeKey()
        }
    }

    /// The window is big enough for every mode, so the island can switch
    /// between them without its window moving.
    private func hoverMetrics(for mode: IslandMode, geometry: NotchGeometry) -> IslandMetrics {
        let sizes = [IslandMetrics.appsContentSize(appCount: apps.apps.count), NowPlayingMetrics.contentSize, CocoonMetrics.contentSize]
        var room = CGSize.zero
        for size in sizes {
            let frame = IslandMetrics(geometry: geometry, contentSize: size).panelFrame.size
            room.width = max(room.width, frame.width)
            room.height = max(room.height, frame.height)
        }
        let content = mode == .files ? CocoonMetrics.contentSize : NowPlayingMetrics.contentSize
        return IslandMetrics(geometry: geometry, contentSize: content, minimumPanelSize: room)
    }

    private func openHover(_ mode: IslandMode, geometry: NotchGeometry) {
        guard !isOpen else { return }
        apps.reload()
        present(mode: mode, geometry: geometry, metrics: hoverMetrics(for: mode, geometry: geometry))
        if mode == .nowPlaying {
            refreshNowPlaying()
        }
    }

    /// Switches between Now Playing and the Cocoon (the tabs beside the notch).
    func switchHover(to newMode: IslandMode) {
        guard isOpen, !isClosing, newMode != mode, newMode != .apps, mode != .apps,
              let geometry = geometry, let view = islandView
        else { return }
        let newMetrics = hoverMetrics(for: newMode, geometry: geometry)
        mode = newMode
        isInteracting = false
        metrics = newMetrics
        panel?.setFrame(newMetrics.panelFrame, display: false)
        view.switchMode(to: newMode, metrics: newMetrics)
        if newMode == .nowPlaying {
            refreshNowPlaying()
        }
    }

    /// Re-checks whether the Now Playing ⟷ Cocoon tabs should show.
    func refreshTabs() {
        guard isOpen, !isClosing, mode != .apps, let view = islandView, let metrics = metrics else { return }
        view.setTabs(visible: tabsAvailable?() ?? false, metrics: metrics)
    }

    /// From Now Playing or the Cocoon to the app switcher (you clicked the character).
    func switchToApps(previousApp: NSRunningApplication?) {
        guard isOpen, !isClosing, mode != .apps, let geometry = geometry, let current = metrics,
              let view = islandView
        else { return }
        rememberPreviousApp(previousApp)
        apps.reload()
        let newMetrics = IslandMetrics(geometry: geometry, contentSize: IslandMetrics.appsContentSize(appCount: apps.apps.count),
                                       minimumPanelSize: current.panelFrame.size)
        mode = .apps
        isInteracting = false
        metrics = newMetrics
        panel?.setFrame(newMetrics.panelFrame, display: false)
        view.setTabs(visible: false, metrics: newMetrics)
        view.switchMode(to: .apps, metrics: newMetrics)
        NSApp.activate()
        panel?.makeKey()
    }

    private func rememberPreviousApp(_ previous: NSRunningApplication?) {
        let me = NSRunningApplication.current.processIdentifier
        if let previous = previous, previous.processIdentifier != me {
            self.previousApp = previous
        } else {
            self.previousApp = apps.activeApp
        }
    }

    private func present(mode: IslandMode, geometry: NotchGeometry, metrics newMetrics: IslandMetrics) {
        isOpen = true
        isClosing = false
        isPicking = false
        isInteracting = false
        self.mode = mode
        self.geometry = geometry
        metrics = newMetrics

        let islandPanel: IslandPanel
        if let existing = panel {
            islandPanel = existing
        } else {
            islandPanel = IslandPanel(frame: newMetrics.panelFrame)
            panel = islandPanel
        }
        islandPanel.setFrame(newMetrics.panelFrame, display: false)
        islandPanel.onKey = { [weak self] event in
            self?.handleKey(event) ?? false
        }

        let view = IslandView(frame: NSRect(origin: .zero, size: newMetrics.panelFrame.size), apps: apps)
        view.switcher.onPick = { [weak self] app in
            self?.pick(app)
        }
        view.onClickOutside = { [weak self] point in
            self?.onClickOutsideIsland?(point)
        }
        let media = MediaCenter.shared
        view.nowPlaying.onOpenSource = { [weak self] session in
            self?.onOpenMediaSource?(session)
        }
        view.nowPlaying.onCommand = { command, session in
            media.perform(command, on: session)
        }
        view.nowPlaying.onSeek = { session, seconds in
            media.seek(session, to: seconds)
        }
        view.nowPlaying.onPickSession = { [weak self] id in
            media.pin(id)
            self?.refreshNowPlaying()
        }
        view.nowPlaying.onInteraction = { [weak self] active in
            self?.isInteracting = active
        }
        view.onSelectTab = { [weak self] tab in
            self?.switchHover(to: tab)
        }
        islandPanel.contentView = view
        islandView = view

        islandPanel.orderFrontRegardless()
        view.expand(with: newMetrics, mode: mode)
        if mode != .apps {
            view.setTabs(visible: tabsAvailable?() ?? false, metrics: newMetrics)
        }
        installClickMonitors()
    }

    /// Shows the latest media in the Now Playing island.
    func refreshNowPlaying() {
        guard isOpen, mode == .nowPlaying, let view = islandView else { return }
        let media = MediaCenter.shared
        view.nowPlaying.show(media.currentSession, all: media.sessions)
    }

    // MARK: - Closing

    /// Closes the island. `returnFocus` gives the keyboard back to the app you were using.
    func close(returnFocus: Bool) {
        guard isOpen, !isClosing, let view = islandView, let currentMetrics = metrics else { return }
        isClosing = true
        isInteracting = false
        removeClickMonitors()
        awayTask?.cancel()
        awayTask = nil
        if returnFocus && mode == .apps {
            apps.returnFocus(to: previousApp)
        }
        view.collapse(with: currentMetrics) { [weak self] in
            self?.finishClosing()
        }
    }

    private func finishClosing() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        islandView = nil
        isOpen = false
        isClosing = false
        isPicking = false
        isInteracting = false
        MediaCenter.shared.pin(nil)
        onClose?()
    }

    /// You picked an app: switch to it, let the highlight move, then close.
    private func pick(_ app: NSRunningApplication) {
        guard isOpen, !isClosing, !isPicking else { return }
        isPicking = true
        islandView?.switcher.showAsActive(app)
        apps.activate(app)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            self?.close(returnFocus: false)
        }
    }

    // MARK: - Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let view = islandView else { return false }
        if event.keyCode == 53 { // Esc
            CocoonModel.shared.pinnedOpen = false
            close(returnFocus: true)
            return true
        }
        if mode == .files {
            let cocoon = CocoonModel.shared
            guard !cocoon.selection.isEmpty else { return false }
            switch event.keyCode {
            case 49: // Space: Quick Look, like in Finder
                cocoon.quickLook()
                return true
            case 36, 76: // Return: open
                cocoon.open()
                return true
            case 51, 117: // Delete: take out of the Cocoon (the file itself stays)
                cocoon.remove()
                return true
            default:
                return false
            }
        }
        guard mode == .apps else { return false }
        switch event.keyCode {
        case 123: // ←
            view.switcher.moveSelection(by: -1)
            return true
        case 124: // →
            view.switcher.moveSelection(by: 1)
            return true
        case 36, 76: // Return, Enter
            return view.switcher.pickSelection()
        default:
            return false
        }
    }

    // MARK: - Clicks outside, and wandering off

    private func installClickMonitors() {
        removeClickMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Clicks in other apps.
        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                if let controller = self {
                    controller.clicked(at: NSEvent.mouseLocation, inOtherApp: true)
                }
            }
        })
        if let global = global {
            clickMonitors.append(global)
        }

        // Clicks in SpiderNotch's own windows.
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let controller = self {
                    controller.clicked(at: NSEvent.mouseLocation, inOtherApp: false)
                }
            }
            return event
        })
        if let local = local {
            clickMonitors.append(local)
        }
    }

    private func removeClickMonitors() {
        for monitor in clickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors.removeAll()
    }

    private func clicked(at point: NSPoint, inOtherApp: Bool) {
        guard isOpen, !isClosing, let currentMetrics = metrics else { return }
        guard !currentMetrics.islandScreenRect.contains(point) else { return }
        // Clicks on SpiderNotch's own windows (like the character, Quick Look or
        // the AirDrop window) are handled there.
        if !inOtherApp && mode != .apps {
            return
        }
        // A pinned-open Cocoon stays until you unpin it or press Esc.
        if mode == .files && CocoonModel.shared.pinnedOpen {
            return
        }
        // A click outside closes the island. If it landed in another app, that app
        // takes over; otherwise give the focus back to the app you were using.
        let wasApps = mode == .apps
        close(returnFocus: false)
        guard wasApps else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self = self else { return }
            self.apps.returnFocus(to: self.previousApp)
        }
    }

    /// Called on every mouse move while the app switcher is open.
    func mouseMoved(to point: NSPoint) {
        guard isOpen, !isClosing, mode == .apps, let currentMetrics = metrics else { return }
        let nearby = currentMetrics.islandScreenRect.insetBy(dx: -40, dy: -40).contains(point)
        if nearby {
            awayTask?.cancel()
            awayTask = nil
        } else if awayTask == nil {
            let delay = awayDelay
            awayTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self = self, !Task.isCancelled else { return }
                self.awayTask = nil
                self.close(returnFocus: true)
            }
        }
    }

    // MARK: - System events

    @objc private func appDidResignActive(_ notification: Notification) {
        // Another app came forward because you clicked it: just close.
        // (After a pick, the island closes by itself a moment later.)
        if isOpen && !isClosing && !isPicking && mode == .apps {
            close(returnFocus: false)
        }
    }

    private func appsChanged() {
        guard isOpen, !isClosing, mode == .apps, let view = islandView else { return }
        view.switcher.syncApps()
    }
}

/// Sizes and positions for the island, worked out from the notch.
struct IslandMetrics {
    /// Where the island's window goes (screen coordinates).
    let panelFrame: NSRect
    /// The notch, the fully open island and its content (window coordinates).
    let notchRect: NSRect
    let islandRect: NSRect
    let contentRect: NSRect

    private static let shadowRoom: CGFloat = 28
    private static let sidePadding: CGFloat = 18
    private static let gapBelowNotch: CGFloat = 8
    private static let bottomPadding: CGFloat = 12

    /// The app switcher's content size for this many apps.
    static func appsContentSize(appCount: Int) -> CGSize {
        CGSize(width: SwitcherMetrics.rowWidth(appCount: appCount),
               height: SwitcherMetrics.cellSize + SwitcherMetrics.nameHeight)
    }

    /// - Parameter minimumPanelSize: make the window at least this big (so the
    ///   island can change size without moving its window).
    init(geometry: NotchGeometry, contentSize: CGSize, minimumPanelSize: CGSize = .zero) {
        let notch = geometry.notchRect
        let screen = geometry.screenFrame
        let maxWidth = min(screen.width - 80, 920)
        let minWidth = min(max(notch.width + 140, 340), maxWidth)
        let islandWidth = min(max(contentSize.width + IslandMetrics.sidePadding * 2, minWidth), maxWidth)
        let islandHeight = notch.height + IslandMetrics.gapBelowNotch + contentSize.height + IslandMetrics.bottomPadding

        let room = IslandMetrics.shadowRoom
        let panelWidth = max((islandWidth + room * 2).rounded(.up), minimumPanelSize.width)
        let panelHeight = max((islandHeight + room).rounded(.up), minimumPanelSize.height)
        var x = notch.midX - panelWidth / 2
        x = min(max(x, screen.minX), screen.maxX - panelWidth)
        panelFrame = NSRect(x: x, y: screen.maxY - panelHeight, width: panelWidth, height: panelHeight)

        let centerX = notch.midX - x
        notchRect = NSRect(x: centerX - notch.width / 2,
                           y: panelHeight - notch.height,
                           width: notch.width,
                           height: notch.height)
        islandRect = NSRect(x: centerX - islandWidth / 2,
                            y: panelHeight - islandHeight,
                            width: islandWidth,
                            height: islandHeight)
        contentRect = NSRect(x: islandRect.minX + IslandMetrics.sidePadding,
                             y: islandRect.minY + IslandMetrics.bottomPadding,
                             width: islandWidth - IslandMetrics.sidePadding * 2,
                             height: contentSize.height)
    }

    /// The open island in screen coordinates (to tell if a click was outside it).
    var islandScreenRect: NSRect {
        islandRect.offsetBy(dx: panelFrame.minX, dy: panelFrame.minY)
    }
}
