//
//  FileDragWatcher.swift
//  SpiderNotch
//
//  Notices when you start dragging files (from Finder or any app), so the
//  Cocoon can open at the notch with its drop zones as soon as you get close.
//
//  It only looks at the drag clipboard's *types* (never its contents) and only
//  during a mouse drag, so it costs almost nothing and doesn't trigger
//  macOS's clipboard privacy prompt.
//

import AppKit

@MainActor
final class FileDragWatcher {
    /// Called when a file drag starts (true) and when the mouse button goes up (false).
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var isDraggingFiles = false

    private var monitors: [Any] = []
    private var countAtMouseDown = 0
    private var checkedThisDrag = false

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        setDragging(false)
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            countAtMouseDown = NSPasteboard(name: .drag).changeCount
            checkedThisDrag = false
            setDragging(false)
        case .leftMouseDragged:
            guard !checkedThisDrag else { return }
            let board = NSPasteboard(name: .drag)
            // A new drag puts fresh data on the drag clipboard.
            guard board.changeCount != countAtMouseDown else { return }
            checkedThisDrag = true
            let types = board.types ?? []
            if types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) {
                setDragging(true)
            }
        case .leftMouseUp:
            // The drop (if any) is handled by the Cocoon; give it a moment first.
            if isDraggingFiles {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self?.setDragging(false)
                }
            }
        default:
            break
        }
    }

    private func setDragging(_ dragging: Bool) {
        guard dragging != isDraggingFiles else { return }
        isDraggingFiles = dragging
        onChange?(dragging)
    }
}
