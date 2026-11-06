//
//  IslandPanel.swift
//  SpiderNotch
//
//  The window for the expanded Dynamic Island. Unlike the spider's window,
//  it takes clicks and key presses (Esc, ← →, Return). It has no title bar
//  or shadow of its own: the island draws everything itself.
//

import AppKit

final class IslandPanel: NSPanel {
    /// Gets each key press first. Return true if it was handled.
    var onKey: (@MainActor (NSEvent) -> Bool)?

    convenience init(frame: NSRect) {
        self.init(contentRect: frame,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        isFloatingPanel = true
        // Just above the character's window, so the character hangs *below* the
        // island and its thread disappears behind it.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // Clicking Now Playing's buttons never takes the keyboard from your app.
        // (The app switcher asks for the keyboard itself, for Esc and the arrow keys.)
        becomesKeyOnlyIfNeeded = true
    }

    // It can take key presses, but never becomes a "main" document window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func keyDown(with event: NSEvent) {
        if let handler = onKey, handler(event) {
            return
        }
        super.keyDown(with: event)
    }
}
