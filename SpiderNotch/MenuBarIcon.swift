//
//  MenuBarIcon.swift
//  SpiderNotch
//
//  The little spider in your menu bar, drawn in code so it's sharp at any
//  size. It's a "template" image: macOS colours it automatically to match a
//  light or dark menu bar.
//

import AppKit

enum MenuBarIcon {
    /// - Parameter badge: adds a small dot (an update is available).
    static func make(badge: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // The silk thread coming down from the top.
            let thread = NSBezierPath()
            thread.move(to: NSPoint(x: 9, y: 18))
            thread.line(to: NSPoint(x: 9, y: 12.4))
            thread.lineWidth = 1.1
            thread.stroke()

            // Four legs on each side: from the body, up to a knee, then down.
            let legs = NSBezierPath()
            legs.lineWidth = 1.2
            legs.lineCapStyle = .round
            legs.lineJoinStyle = .round
            let leg: [(start: NSPoint, knee: NSPoint, end: NSPoint)] = [
                (NSPoint(x: 3.4, y: 10.8), NSPoint(x: 6.0, y: 13.2), NSPoint(x: 8.0, y: 11.0)),
                (NSPoint(x: 3.9, y: 9.2), NSPoint(x: 6.7, y: 10.5), NSPoint(x: 8.5, y: 8.2)),
                (NSPoint(x: 3.9, y: 7.4), NSPoint(x: 6.7, y: 7.2), NSPoint(x: 8.1, y: 4.8)),
                (NSPoint(x: 3.2, y: 5.7), NSPoint(x: 5.6, y: 4.1), NSPoint(x: 6.4, y: 1.4)),
            ]
            for side in [-1.0, 1.0] as [CGFloat] {
                for part in leg {
                    legs.move(to: NSPoint(x: 9 + side * part.start.x, y: part.start.y))
                    legs.line(to: NSPoint(x: 9 + side * part.knee.x, y: part.knee.y))
                    legs.line(to: NSPoint(x: 9 + side * part.end.x, y: part.end.y))
                }
            }
            legs.stroke()

            // The round body.
            NSBezierPath(ovalIn: NSRect(x: 5.0, y: 4.3, width: 8.0, height: 8.6)).fill()

            // Two little eyes, cut out of the body.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 6.6, y: 8.3, width: 1.7, height: 2.1)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.7, y: 8.3, width: 1.7, height: 2.1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            if badge {
                // A dot in the top-right corner, with a little gap around it.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 11.6, y: 11.6, width: 7, height: 7)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: 12.6, y: 12.6, width: 5.2, height: 5.2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badge ? "SpiderNotch, update available" : "SpiderNotch"
        return image
    }
}

extension NSFont {
    /// The same font in bold.
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
