//
//  MouseWatcher.swift
//  SpiderNotch
//
//  Listens to mouse movement anywhere on screen and reports where the cursor
//  is. It doesn't take over clicks or keyboard focus, needs no special
//  permissions, and only runs a few comparisons per mouse move, so it uses
//  almost no CPU. It only runs while SpiderNotch is enabled.
//

import AppKit

@MainActor
final class MouseWatcher {
    typealias Handler = @MainActor (_ location: NSPoint, _ deltaX: CGFloat) -> Void

    private let handler: Handler
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    func start() {
        guard !isRunning else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        // Mouse moves while other apps are in front (almost all the time).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                if let watcher = self {
                    watcher.report(event)
                }
            }
        }

        // Mouse moves while SpiderNotch itself is in front (e.g. its Settings window).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                if let watcher = self {
                    watcher.report(event)
                }
            }
            return event
        }
    }

    /// AppKit delivers mouse events on the main thread, so this runs on the main actor.
    private func report(_ event: NSEvent) {
        handler(NSEvent.mouseLocation, event.deltaX)
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }
}
