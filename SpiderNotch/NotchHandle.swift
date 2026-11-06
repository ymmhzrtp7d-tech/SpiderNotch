//
//  NotchHandle.swift
//  SpiderNotch
//
//  On screens without a camera notch (external displays, older Macs, a closed
//  lid), there's nothing at the top of the screen that says "hover here". This
//  small, always-visible handle marks the spot where the island lives, so it's
//  available at a glance, just like the real notch on a MacBook.
//
//  It's one tiny window that never takes clicks or the keyboard. On a MacBook
//  with a notch it isn't shown: the notch itself is the handle.
//

import AppKit

@MainActor
final class NotchHandle {
    private var panel: NSPanel?

    /// The handle's size: a slim pill in the middle of the pretend notch.
    static let size = CGSize(width: 96, height: 5)

    /// Where the handle goes for this notch (screen coordinates), or nil when
    /// none is needed (a real notch).
    static func frame(for geometry: NotchGeometry) -> NSRect? {
        guard !geometry.isHardwareNotch else { return nil }
        let notch = geometry.notchRect
        return NSRect(x: notch.midX - size.width / 2,
                      y: geometry.screenFrame.maxY - size.height - 3,
                      width: size.width,
                      height: size.height)
    }

    /// Shows the handle for `geometry` (or hides it when there's a real notch,
    /// SpiderNotch is switched off, or `visible` is false).
    func update(geometry: NotchGeometry?, visible: Bool) {
        guard visible, let geometry = geometry, let frame = NotchHandle.frame(for: geometry) else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NotchPanel(frame: frame)
        // Just below the character's window, so the island and character cover it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.ignoresMouseEvents = true
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        view.layer?.cornerRadius = frame.height / 2
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        panel.contentView = view
        return panel
    }
}
