//
//  IslandView.swift
//  SpiderNotch
//
//  The black "Dynamic Island" that grows out of the notch. It shows either
//  the app switcher or Now Playing. The black shape is a Core Animation layer
//  whose outline springs from notch-size to full size (and back), and from one
//  size to another when it switches between the two, just like on iPhone.
//

import AppKit
import QuartzCore

enum IslandMode {
    case apps
    case nowPlaying
}

@MainActor
final class IslandView: NSView {
    let switcher: AppSwitcherView
    let nowPlaying: NowPlayingView
    private let backdrop: IslandBackdropView
    private(set) var mode: IslandMode = .apps
    /// Clicks that land beside the island (in its shadow) go here, so the
    /// character hanging below can still be clicked.
    var onClickOutside: (@MainActor (NSPoint) -> Void)?
    private var islandRect = NSRect.zero

    init(frame frameRect: NSRect, apps: RunningApps) {
        switcher = AppSwitcherView(frame: .zero, apps: apps)
        nowPlaying = NowPlayingView(frame: .zero)
        backdrop = IslandBackdropView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(backdrop)
        addSubview(switcher)
        addSubview(nowPlaying)
        switcher.alphaValue = 0
        nowPlaying.alphaValue = 0
        switcher.isHidden = true
        nowPlaying.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("IslandView is only created in code.")
    }

    private var moveTracking: NSTrackingArea?

    // Makes sure mouse moves over the island are always reported, so it knows
    // you're still using it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = moveTracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        moveTracking = area
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !islandRect.contains(point), let window = window {
            onClickOutside?(window.convertPoint(toScreen: event.locationInWindow))
        }
    }

    private func content(for mode: IslandMode) -> NSView {
        mode == .apps ? switcher : nowPlaying
    }

    /// Grows the island out of the notch, then fades its content in.
    func expand(with metrics: IslandMetrics, mode: IslandMode) {
        self.mode = mode
        islandRect = metrics.islandRect
        backdrop.frame = bounds
        backdrop.setShape(IslandShape.notch(metrics.notchRect))
        backdrop.morph(to: IslandShape.island(metrics.islandRect), bouncy: true)

        let shown = content(for: mode)
        let other = content(for: mode == .apps ? .nowPlaying : .apps)
        other.isHidden = true
        other.alphaValue = 0
        shown.frame = metrics.contentRect
        shown.isHidden = false
        shown.alphaValue = 0
        if mode == .apps {
            switcher.reloadApps()
            switcher.scrollToActive()
        } else {
            nowPlaying.startTicking()
        }

        Task { @MainActor [weak self] in
            // Wait until the island has mostly opened.
            try? await Task.sleep(nanoseconds: 140_000_000)
            self?.fadeIn(shown)
        }
    }

    /// Switches between Now Playing and the app switcher while open: the island
    /// springs to its new size and the content cross-fades.
    func switchMode(to newMode: IslandMode, metrics: IslandMetrics) {
        guard newMode != mode else { return }
        let old = content(for: mode)
        let new = content(for: newMode)
        mode = newMode
        islandRect = metrics.islandRect
        backdrop.morph(to: IslandShape.island(metrics.islandRect), bouncy: true)
        if newMode == .apps {
            switcher.reloadApps()
            switcher.scrollToActive()
            nowPlaying.stopTicking()
        } else {
            nowPlaying.startTicking()
        }
        fadeOut(old)
        new.frame = metrics.contentRect
        new.isHidden = false
        new.alphaValue = 0
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self?.fadeIn(new)
        }
    }

    /// Fades content in. (Kept as a plain, non-async function on purpose:
    /// inside async code Swift would pick the "async" version of this animation call.)
    private func fadeIn(_ view: NSView) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ view: NSView) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            view.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if view.alphaValue == 0 {
                    view.isHidden = true
                }
            }
        }
    }

    /// Fades the content out and shrinks the island back into the notch.
    func collapse(with metrics: IslandMetrics, completion: @escaping @MainActor @Sendable () -> Void) {
        nowPlaying.stopTicking()
        let shown = content(for: mode)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            shown.animator().alphaValue = 0
        }
        backdrop.morph(to: IslandShape.notch(metrics.notchRect), bouncy: false)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            completion()
        }
    }
}

/// Draws the black island shape (and its soft shadow) with Core Animation.
@MainActor
final class IslandBackdropView: NSView {
    private let shape = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
        shape.fillColor = NSColor.black.cgColor
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0.35
        shape.shadowRadius = 16
        shape.shadowOffset = CGSize(width: 0, height: -5)
        layer?.addSublayer(shape)
    }

    required init?(coder: NSCoder) {
        fatalError("IslandBackdropView is only created in code.")
    }

    // Draw the outline at full Retina sharpness.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        shape.contentsScale = scale
        CATransaction.commit()
    }

    /// Sets the outline straight away, with no animation.
    func setShape(_ path: CGPath) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.removeAllAnimations()
        shape.frame = bounds
        shape.path = path
        shape.shadowPath = path
        CATransaction.commit()
    }

    /// Springs the outline to a new shape. "Bouncy" overshoots a little, like the Dynamic Island.
    func morph(to path: CGPath, bouncy: Bool) {
        let start = (shape.presentation() ?? shape).path ?? path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        shape.shadowPath = path
        CATransaction.commit()

        let stiffness: CGFloat = bouncy ? 320 : 420
        let dampingRatio: CGFloat = bouncy ? 0.7 : 1.0
        for keyPath in ["path", "shadowPath"] {
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.fromValue = start
            spring.toValue = path
            spring.mass = 1
            spring.stiffness = stiffness
            spring.damping = 2 * dampingRatio * stiffness.squareRoot()
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            shape.add(spring, forKey: keyPath)
        }
    }
}

/// The island's outline: a flat top that melts into the top edge of the screen,
/// small curved "shoulders" where it meets the menu bar, and round bottom corners.
/// Every outline is built from the same pieces, so Core Animation can morph
/// smoothly between the notch-sized one and the big ones.
enum IslandShape {
    static func notch(_ rect: NSRect) -> CGPath {
        path(in: rect, cornerRadius: min(10, rect.height / 2), shoulder: 6)
    }

    static func island(_ rect: NSRect) -> CGPath {
        path(in: rect, cornerRadius: 30, shoulder: 10)
    }

    static func path(in rect: NSRect, cornerRadius: CGFloat, shoulder: CGFloat) -> CGPath {
        let s = max(0.5, shoulder)
        let r = max(0.5, min(cornerRadius, rect.height - s - 0.5, rect.width / 2 - 0.5))
        let k: CGFloat = 0.5523 // makes a cubic curve look like a quarter circle
        let left = rect.minX
        let right = rect.maxX
        let top = rect.maxY
        let bottom = rect.minY

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left - s, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top - s), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addCurve(to: CGPoint(x: left + r, y: bottom),
                      control1: CGPoint(x: left, y: bottom + r - k * r),
                      control2: CGPoint(x: left + r - k * r, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addCurve(to: CGPoint(x: right, y: bottom + r),
                      control1: CGPoint(x: right - r + k * r, y: bottom),
                      control2: CGPoint(x: right, y: bottom + r - k * r))
        path.addLine(to: CGPoint(x: right, y: top - s))
        path.addQuadCurve(to: CGPoint(x: right + s, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }
}
