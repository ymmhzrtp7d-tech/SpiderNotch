//
//  NotchGeometry.swift
//  SpiderNotch
//
//  Finds exactly where the notch is. macOS tells us how tall the notch is
//  (the "safe area" at the top of the screen) and how much room is free to its
//  left and right, so the notch is whatever is left in the middle.
//
//  All values are in points with the origin at the bottom-left, which is how
//  macOS measures screens. Points (not pixels) keep it correct on Retina
//  displays and at any "Looks like" display scaling.
//

import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let notchRect: NSRect
    /// True for a real camera notch, false for the pretend one on other screens.
    let isHardwareNotch: Bool
    /// 2.0 on Retina screens, 1.0 on older ones.
    let backingScale: CGFloat

    /// Hovering anywhere in here wakes the spider: the notch plus a small margin.
    var hotZone: NSRect {
        NSRect(x: notchRect.minX - 10,
               y: notchRect.minY - 6,
               width: notchRect.width + 20,
               height: notchRect.height + 6 + 4) // the extra 4 reaches past the top edge
    }

    /// Picks the screen to use and measures its notch.
    @MainActor
    static func detect(allowVirtualNotch: Bool) -> NotchGeometry? {
        // 1. Prefer a screen with a real notch (your MacBook's built-in display).
        for screen in NSScreen.screens {
            if let notch = hardwareNotch(on: screen) {
                return NotchGeometry(screenFrame: screen.frame,
                                     notchRect: notch,
                                     isHardwareNotch: true,
                                     backingScale: screen.backingScaleFactor)
            }
        }

        // 2. No notch (lid closed, external monitor): pretend there's one at the top centre.
        guard allowVirtualNotch, let screen = NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }
        let frame = screen.frame
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        let width: CGFloat = 180
        let pretendNotch = NSRect(x: frame.midX - width / 2,
                                  y: frame.maxY - menuBarHeight,
                                  width: width,
                                  height: menuBarHeight)
        return NotchGeometry(screenFrame: frame,
                             notchRect: pretendNotch,
                             isHardwareNotch: false,
                             backingScale: screen.backingScaleFactor)
    }

    @MainActor
    private static func hardwareNotch(on screen: NSScreen) -> NSRect? {
        let notchHeight = screen.safeAreaInsets.top
        guard notchHeight > 0 else { return nil }

        let frame = screen.frame
        // The free areas to the left and right of the camera housing.
        let leftArea: NSRect? = screen.auxiliaryTopLeftArea
        let rightArea: NSRect? = screen.auxiliaryTopRightArea

        var width: CGFloat = 200
        var minX = frame.midX - width / 2
        if let left = leftArea, let right = rightArea {
            let measured = frame.width - left.width - right.width
            if measured > 60 && measured < 600 {
                width = measured
                minX = frame.minX + left.width
            }
        }
        return NSRect(x: minX, y: frame.maxY - notchHeight, width: width, height: notchHeight)
    }
}
