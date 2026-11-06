//
//  NotchPanel.swift
//  SpiderNotch
//
//  A borderless, see-through window that floats above other windows right
//  at the notch. It ignores the mouse completely, so clicks pass straight
//  through to whatever is underneath, and it never steals focus.
//

import AppKit

final class NotchPanel: NSPanel {
    convenience init(frame: NSRect) {
        self.init(contentRect: frame,
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        isFloatingPanel = true
        level = .statusBar                    // above normal windows and the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear              // fully transparent…
        isOpaque = false
        hasShadow = false                     // …with no window shadow
        ignoresMouseEvents = true             // clicks go through to the apps below…
        acceptsMouseMovedEvents = true        // …except on the spider (see NotchController)
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
    }

    // Never become the active window, so typing always goes to your apps.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Let the window sit right against the very top edge of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
