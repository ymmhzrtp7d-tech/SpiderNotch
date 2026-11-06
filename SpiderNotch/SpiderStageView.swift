//
//  SpiderStageView.swift
//  SpiderNotch
//
//  The little stage under the notch where the character performs.
//
//  Everything here uses Core Animation: we describe each movement once and
//  macOS's graphics system plays it smoothly on the GPU. The app itself does
//  almost no work while the character moves.
//
//  The layers, from the outside in:
//
//    root ─┬─ clip              hides everything above the bottom edge of the notch
//          │   └─ pivot         turns for pushes and the drop "kick"   (swing)
//          │       └─ sway      turns gently back and forth when idle  (sway)
//          │           └─ body  moves down and up (drop / climb)
//          │               ├─ web      the silk thread (only for "Drop on a Thread")
//          │               └─ sticker  the picture (breathes, blinks, wiggles)
//          └─ fakeNotch         a black notch, only on screens without a real one
//
//  Three ways to arrive (Settings → Appearance): drop on a thread, peek out,
//  or pop out and float. "Animation speed" speeds up or slows down the whole
//  stage at once (the root layer's `speed`).
//
//  Photos of real faces are never squashed or stretched: they only move, turn
//  and grow evenly, so the face always looks exactly like the original. Only
//  drawn characters that come with real blink/smile pictures blink and smile.
//

import AppKit
import QuartzCore

@MainActor
final class SpiderStageView: NSView {
    enum Phase {
        case hidden, dropping, hanging, climbing
    }

    private(set) var phase: Phase = .hidden

    /// True while the character is out below the notch (or on its way out).
    var isOut: Bool {
        phase == .dropping || phase == .hanging
    }

    private let clipLayer = CALayer()
    private let fakeNotchLayer = CAShapeLayer()
    private let pivotLayer = CALayer()
    private let swayLayer = CALayer()
    private let bodyLayer = CALayer()
    private let webLayer = CAShapeLayer()
    private let stickerLayer = CALayer()

    private(set) var layout: StageLayout?
    private var sticker: Sticker?
    private var displayScale: CGFloat = 2
    private var generation = 0
    private var swingCount = 0
    private var phaseTask: Task<Void, Never>?

    // The sticker's faces, prepared at the right size for this display.
    private var openFace: CGImage?
    private var blinkFace: CGImage?
    private var happyFace: CGImage?

    /// Called when you click the character.
    var onStickerClick: (@MainActor () -> Void)?
    /// Called when the cursor leaves this window (only happens while it's clickable).
    var onMouseExit: (@MainActor () -> Void)?
    private var mouseTracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Give the view our own layer, so we fully control it ("layer hosting").
        layer = CALayer()
        wantsLayer = true
        buildLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("SpiderStageView is only created in code.")
    }

    // MARK: - Setting up

    private func buildLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        clipLayer.masksToBounds = true
        root.addSublayer(clipLayer)
        root.addSublayer(fakeNotchLayer)

        clipLayer.addSublayer(pivotLayer)
        pivotLayer.addSublayer(swayLayer)
        swayLayer.addSublayer(bodyLayer)
        bodyLayer.addSublayer(webLayer)      // the thread goes behind…
        bodyLayer.addSublayer(stickerLayer)  // …the sticker

        // The pivot and sway layers are zero-sized "hinges": everything inside
        // them is placed relative to the hinge point and turns around it.
        pivotLayer.bounds = .zero
        swayLayer.bounds = .zero
        swayLayer.position = .zero

        // The thread: a thin silk line with a soft shadow, so it shows on light and dark backgrounds.
        webLayer.fillColor = nil
        webLayer.strokeColor = NSColor(white: 1, alpha: 0.95).cgColor
        webLayer.lineWidth = 1.4
        webLayer.lineCap = .round
        webLayer.shadowColor = NSColor.black.cgColor
        webLayer.shadowOpacity = 0.5
        webLayer.shadowRadius = 1.2
        webLayer.shadowOffset = .zero

        // The sticker, with a soft drop shadow. "Rasterizing" draws the shadow
        // once and reuses it, instead of recalculating it every frame.
        stickerLayer.contentsGravity = .resize
        stickerLayer.minificationFilter = .trilinear
        stickerLayer.magnificationFilter = .linear
        stickerLayer.shadowColor = NSColor.black.cgColor
        stickerLayer.shadowOpacity = 0.3
        stickerLayer.shadowRadius = 3
        stickerLayer.shadowOffset = CGSize(width: 0, height: -2)
        stickerLayer.shouldRasterize = true

        fakeNotchLayer.fillColor = NSColor.black.cgColor
        fakeNotchLayer.opacity = 0
    }

    /// Lays out all the layers for a new screen, size or character. It starts hidden.
    func configure(layout: StageLayout, sticker: Sticker, scale: CGFloat) {
        self.layout = layout
        self.sticker = sticker
        stopEverything()

        let size = layout.stickerSize
        let attach = CGPoint(x: layout.anchor.x * size.width, y: layout.anchor.y * size.height)
        let notchRect = CGRect(x: layout.notchMidX - layout.notchWidth / 2,
                               y: bounds.height - layout.notchHeight,
                               width: layout.notchWidth,
                               height: layout.notchHeight)

        instantly {
            layer?.frame = bounds
            layer?.speed = Float(layout.speed)
            clipLayer.frame = CGRect(x: 0, y: 0,
                                     width: bounds.width,
                                     height: max(bounds.height - layout.notchHeight, 0))
            pivotLayer.position = layout.pivot

            bodyLayer.bounds = CGRect(origin: .zero, size: size)
            bodyLayer.anchorPoint = layout.anchor
            bodyLayer.position = CGPoint(x: 0, y: layout.hiddenY)
            bodyLayer.opacity = 1

            stickerLayer.bounds = CGRect(origin: .zero, size: size)
            stickerLayer.anchorPoint = layout.anchor
            stickerLayer.position = attach

            // The thread starts just inside the sticker and runs far up past the top
            // of the screen. Only the part below the notch is ever visible, so it
            // seems to grow out of the notch as the character drops.
            webLayer.frame = CGRect(origin: .zero, size: size)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: attach.x, y: attach.y - 3))
            path.addLine(to: CGPoint(x: attach.x, y: attach.y + 2000))
            webLayer.path = path
            webLayer.isHidden = !layout.showsThread

            fakeNotchLayer.isHidden = !layout.drawsFakeNotch
            fakeNotchLayer.path = SpiderStageView.notchShape(in: notchRect)
            fakeNotchLayer.opacity = 0
        }
        applyScale(scale)
    }

    /// Seconds on the clock for something that takes `duration` at normal speed.
    private func realTime(_ duration: Double) -> Double {
        duration / Double(max(layout?.speed ?? 1, 0.1))
    }

    // MARK: - Sharp on Retina

    private func applyScale(_ scale: CGFloat) {
        displayScale = scale
        instantly {
            let layers: [CALayer] = [clipLayer, fakeNotchLayer, pivotLayer, swayLayer, bodyLayer, webLayer, stickerLayer]
            for item in layers {
                item.contentsScale = scale
            }
            layer?.contentsScale = scale
            stickerLayer.rasterizationScale = scale
        }
        renderStickerImage()
    }

    /// Makes copies of the sticker's faces at exactly the pixel size this display needs.
    private func renderStickerImage() {
        guard let layout = layout, let sticker = sticker else { return }
        // A little extra resolution so it stays crisp while it bounces.
        let pixelHeight = Int((layout.stickerSize.height * displayScale * 1.3).rounded(.up))
        let open = StickerArt.scaled(sticker.image, toHeight: pixelHeight)
        openFace = open
        blinkFace = sticker.blinkImage.map { StickerArt.scaled($0, toHeight: pixelHeight) }
        happyFace = sticker.happyImage.map { StickerArt.scaled($0, toHeight: pixelHeight) }
        instantly {
            stickerLayer.contents = open
        }
        if isOut {
            startFaceLoop()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor, scale != displayScale {
            applyScale(scale)
        }
    }

    // MARK: - Clicking the character

    // The window normally lets every click pass through. NotchController switches
    // that off only while the cursor is right on the character, so these get called.

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = mouseTracking {
            removeTrackingArea(old)
        }
        // Keeps mouse-move events coming while this window is clickable.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        mouseTracking = area
    }

    override func mouseDown(with event: NSEvent) {
        if stickerContains(screenPoint: NSEvent.mouseLocation) {
            onStickerClick?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    /// Is this point on the screen on the character right now, even in the middle of a swing?
    func stickerContains(screenPoint: NSPoint) -> Bool {
        guard isOut, let window = window else { return false }
        let inWindow = window.convertPoint(fromScreen: screenPoint)
        return stickerContains(viewPoint: convert(inWindow, from: nil))
    }

    /// The same, for a point in this view's own coordinates.
    func stickerContains(viewPoint: NSPoint) -> Bool {
        guard isOut, let root = layer else { return false }
        // Ask the layers where they are on screen right now ("presentation" = mid-animation).
        let shown = root.presentation() ?? root
        guard let hit = shown.hitTest(viewPoint) else { return false }
        return hit === stickerLayer || hit.model() === stickerLayer
    }

    // MARK: - Arriving

    /// The character comes out of the notch, in the style chosen in Settings.
    func drop() {
        guard let layout = layout, !isOut else { return }
        let comingFromHidden = (phase == .hidden)
        let startY = comingFromHidden ? layout.hiddenY : presentedBodyY()
        let presented = bodyLayer.presentation() ?? bodyLayer
        let startScale = (presented.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        let startOpacity = presented.opacity
        generation += 1
        let token = generation
        phaseTask?.cancel()

        // Stop leaving (if it was), starting from wherever it is right now.
        let moving: [CALayer] = [bodyLayer, stickerLayer]
        for item in moving {
            item.removeAllAnimations()
        }
        instantly {
            bodyLayer.position = CGPoint(x: 0, y: layout.hangingY)
            bodyLayer.opacity = 1
            bodyLayer.transform = CATransform3DIdentity
        }

        var settle: Double = 0.8
        switch layout.entrance {
        case .thread:
            let spring = CASpringAnimation(keyPath: "position.y")
            spring.fromValue = startY
            spring.toValue = layout.hangingY
            spring.mass = 1
            spring.stiffness = 170
            spring.damping = damping(ratio: 0.8 - 0.5 * clamp01(layout.bounce), stiffness: 170)
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            bodyLayer.add(spring, forKey: "drop")
            settle = min(spring.duration, 2.5)
            // A little sideways kick, so it starts swinging as it falls.
            if comingFromHidden && layout.swing > 0.01 {
                let direction: CGFloat = Bool.random() ? 1 : -1
                addSwing(degrees: 6.5 * layout.swing * direction)
            }

        case .peek:
            let spring = CASpringAnimation(keyPath: "position.y")
            spring.fromValue = startY
            spring.toValue = layout.hangingY
            spring.mass = 1
            spring.stiffness = 220
            spring.damping = damping(ratio: 0.85 - 0.35 * clamp01(layout.bounce), stiffness: 220)
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            bodyLayer.add(spring, forKey: "drop")
            settle = min(spring.duration, 1.6)
            // A curious little tilt as it peeks out.
            let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            tilt.values = [0.0, radians(7), radians(-4), 0.0]
            tilt.keyTimes = [0, 0.35, 0.7, 1]
            tilt.duration = 0.9
            tilt.calculationMode = .cubic
            tilt.isAdditive = true
            stickerLayer.add(tilt, forKey: "peek-tilt")

        case .pop:
            let grow = CASpringAnimation(keyPath: "transform.scale")
            let fromScale: CGFloat = comingFromHidden ? 0.2 : startScale
            grow.fromValue = fromScale
            grow.toValue = 1.0
            grow.mass = 1
            grow.stiffness = 260
            grow.damping = damping(ratio: 0.75 - 0.4 * clamp01(layout.bounce), stiffness: 260)
            grow.initialVelocity = 0
            grow.duration = grow.settlingDuration
            bodyLayer.add(grow, forKey: "pop")
            let fade = CABasicAnimation(keyPath: "opacity")
            let fromOpacity: Float = comingFromHidden ? 0 : startOpacity
            fade.fromValue = fromOpacity
            fade.toValue = 1.0
            fade.duration = 0.14
            bodyLayer.add(fade, forKey: "pop-fade")
            settle = min(grow.duration, 1.4)
        }

        if layout.drawsFakeNotch {
            fadeFakeNotch(to: 1)
        }
        startIdleMotion()

        phase = .dropping
        let wait = realTime(settle)
        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self = self, self.generation == token, !Task.isCancelled else { return }
            self.phase = .hanging
        }
    }

    private func damping(ratio: CGFloat, stiffness: CGFloat) -> CGFloat {
        2 * max(ratio, 0.15) * stiffness.squareRoot()
    }

    private func presentedBodyY() -> CGFloat {
        (bodyLayer.presentation() ?? bodyLayer).position.y
    }

    // MARK: - Idle motion

    /// Small, never-ending movements so it feels alive while it's out.
    private func startIdleMotion() {
        guard let layout = layout else { return }
        let float = layout.floatAmount

        switch layout.entrance {
        case .thread:
            // Sway gently left and right on the thread…
            if layout.swing > 0.01 {
                let sway = wave(keyPath: "transform.rotation.z", amplitude: radians(2.4) * layout.swing, period: 4.4)
                swayLayer.add(sway, forKey: "sway")
            }
            // …and bob softly on the stretchy thread.
            if float > 0.01 {
                bodyLayer.add(bob(distance: 3 * float, period: 1.9), forKey: "bob")
            }
        case .peek:
            if float > 0.01 {
                bodyLayer.add(bob(distance: 3.5 * float, period: 2.3), forKey: "bob")
                let tilt = wave(keyPath: "transform.rotation.z", amplitude: radians(2.2) * float, period: 5.2)
                tilt.isAdditive = true
                stickerLayer.add(tilt, forKey: "idle-tilt")
            }
        case .pop:
            if float > 0.01 {
                bodyLayer.add(bob(distance: 6 * float, period: 2.6), forKey: "bob")
                let tilt = wave(keyPath: "transform.rotation.z", amplitude: radians(3) * float, period: 3.6)
                tilt.isAdditive = true
                stickerLayer.add(tilt, forKey: "idle-tilt")
            }
        }

        // Breathe. Drawn characters get a tiny squash and stretch; photos only
        // grow evenly, so a real face is never distorted.
        if layout.isPhoto {
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 1.0
            breathe.toValue = 1.02
            breathe.duration = 1.6
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            stickerLayer.add(breathe, forKey: "breathe")
        } else {
            let breatheY = CABasicAnimation(keyPath: "transform.scale.y")
            breatheY.fromValue = 1.0
            breatheY.toValue = 1.035
            let breatheX = CABasicAnimation(keyPath: "transform.scale.x")
            breatheX.fromValue = 1.0
            breatheX.toValue = 0.985
            for breathe in [breatheY, breatheX] {
                breathe.duration = 1.4
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            }
            stickerLayer.add(breatheY, forKey: "breatheY")
            stickerLayer.add(breatheX, forKey: "breatheX")
        }

        // Blink now and then, and flash a big smile (only characters drawn with those faces).
        startFaceLoop()
    }

    /// A soft up-and-down movement that adds on top of where the character is.
    private func bob(distance: CGFloat, period: CFTimeInterval) -> CABasicAnimation {
        let bob = CABasicAnimation(keyPath: "position.y")
        bob.fromValue = 0.0
        bob.toValue = -distance
        bob.isAdditive = true
        bob.duration = period / 2
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return bob
    }

    /// An 11-second loop of faces: blink, a double blink, and a big smile.
    /// It's one Core Animation, so it costs no CPU while it plays.
    private func startFaceLoop() {
        guard let open = openFace, let blink = blinkFace else { return }
        let smile = happyFace ?? open
        let loopLength = 11.0
        // Each face shows from its start time until the next one starts.
        let script: [(face: CGImage, starts: Double)] = [
            (open, 0.0), (blink, 3.0), (open, 3.14),
            (blink, 6.8), (open, 6.92), (blink, 7.1), (open, 7.22),
            (smile, 9.2), (open, 10.4),
        ]
        let faces = CAKeyframeAnimation(keyPath: "contents")
        faces.values = script.map { $0.face }
        faces.keyTimes = script.map { NSNumber(value: $0.starts / loopLength) } + [NSNumber(value: 1.0)]
        faces.calculationMode = .discrete
        faces.duration = loopLength
        faces.repeatCount = .infinity
        stickerLayer.add(faces, forKey: "faces")
    }

    // MARK: - Click reaction

    /// A happy little hop when you click the character.
    func celebrate() {
        guard isOut, let layout = layout else { return }
        let duration = 0.5

        // Big smile (if the character has a happy face).
        if let happy = happyFace, let open = openFace {
            let face = CAKeyframeAnimation(keyPath: "contents")
            face.values = [happy, open]
            face.keyTimes = [0, 0.85, 1]
            face.calculationMode = .discrete
            face.duration = duration
            stickerLayer.add(face, forKey: "reaction-face")
        }

        // Hop up and land (adds on top of where it already is).
        let hop = CAKeyframeAnimation(keyPath: "position.y")
        hop.values = [0.0, 16.0, 0.0, 4.0, 0.0]
        hop.keyTimes = [0, 0.3, 0.6, 0.8, 1]
        hop.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
        ]
        hop.isAdditive = true
        hop.duration = duration
        bodyLayer.add(hop, forKey: "reaction-hop")

        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [0.0, -0.14, 0.12, -0.06, 0.0]
        var reactions: [(CAKeyframeAnimation, String)] = [(wiggle, "reaction-wiggle")]
        if layout.isPhoto {
            // A cute bounce that keeps the photo's proportions exactly.
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = [1.0, 0.9, 1.12, 0.97, 1.0]
            reactions.append((grow, "reaction-scale"))
        } else {
            // Squash, stretch and a playful wiggle.
            let stretchY = CAKeyframeAnimation(keyPath: "transform.scale.y")
            stretchY.values = [1.0, 0.82, 1.14, 0.95, 1.0]
            let stretchX = CAKeyframeAnimation(keyPath: "transform.scale.x")
            stretchX.values = [1.0, 1.14, 0.9, 1.03, 1.0]
            reactions.append((stretchY, "reaction-y"))
            reactions.append((stretchX, "reaction-x"))
        }
        for (animation, key) in reactions {
            animation.keyTimes = [0, 0.15, 0.45, 0.75, 1]
            animation.duration = duration
            animation.calculationMode = .cubic
            stickerLayer.add(animation, forKey: key)
        }
    }

    /// A smooth back-and-forth wave that starts at zero, so it never jumps.
    private func wave(keyPath: String, amplitude: CGFloat, period: CFTimeInterval) -> CAKeyframeAnimation {
        let steps = 48
        var values: [NSNumber] = []
        var keyTimes: [NSNumber] = []
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            values.append(NSNumber(value: Double(amplitude) * sin(progress * 2 * Double.pi)))
            keyTimes.append(NSNumber(value: progress))
        }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = period
        animation.repeatCount = .infinity
        animation.calculationMode = .cubic
        return animation
    }

    // MARK: - Swinging

    /// Gives the character a push. It fades out like a real pendulum, and
    /// several pushes simply add up (they're "additive" animations).
    private func addSwing(degrees: CGFloat) {
        guard abs(degrees) > 0.2 else { return }
        let amplitude = Double(radians(degrees))
        let duration = 7.0
        let period = 1.7
        let fadeTime = 2.0
        let steps = 140
        var values: [NSNumber] = []
        var keyTimes: [NSNumber] = []
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let time = progress * duration
            let envelope = exp(-time / fadeTime) * (1 - pow(progress, 6))
            values.append(NSNumber(value: amplitude * envelope * sin(2 * Double.pi * time / period)))
            keyTimes.append(NSNumber(value: progress))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.isAdditive = true
        animation.calculationMode = .cubic
        swingCount += 1
        pivotLayer.add(animation, forKey: "swing-\(swingCount)")
    }

    /// Your cursor bumped into the character: it swings (or wobbles) away with a happy "boing".
    func poke(deltaX: CGFloat) {
        guard isOut, let layout = layout else { return }
        let direction: CGFloat = deltaX >= 0 ? 1 : -1
        let strength = min(max(abs(deltaX) / 10, 0.4), 1)

        if layout.entrance == .thread {
            // Never let pushes add up to a swing wider than the window.
            let currentDegrees = abs(currentAngle(of: pivotLayer)) * 180 / .pi
            let limitDegrees = layout.maxSwingAngle * 180 / .pi - 4
            let room = max(0, limitDegrees - currentDegrees)
            // A gentle push, so it stays under the cursor and is easy to click.
            let push = min(5 * strength * max(layout.swing, 0.4), room)
            addSwing(degrees: push * direction)
        } else {
            let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            let angle = Double(radians(9 * strength)) * Double(direction)
            wobble.values = [0.0, -angle, angle * 0.6, -angle * 0.25, 0.0]
            wobble.keyTimes = [0, 0.2, 0.5, 0.8, 1]
            wobble.duration = 0.6
            wobble.calculationMode = .cubic
            wobble.isAdditive = true
            stickerLayer.add(wobble, forKey: "poke-wobble")
        }

        let boing = CAKeyframeAnimation(keyPath: "transform.scale")
        boing.values = [1.0, 1.15, 0.93, 1.04, 1.0]
        boing.keyTimes = [0, 0.2, 0.45, 0.72, 1]
        boing.duration = 0.55
        boing.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        bodyLayer.add(boing, forKey: "boing")
    }

    private func currentAngle(of target: CALayer) -> CGFloat {
        let transform = (target.presentation() ?? target).transform
        return atan2(transform.m12, transform.m11)
    }

    // MARK: - Leaving

    /// The character goes back into the notch and disappears.
    /// `completion` runs once it's completely out of sight.
    func climb(completion: @escaping @MainActor @Sendable () -> Void) {
        guard let layout = layout else {
            completion()
            return
        }
        if phase == .hidden {
            completion()
            return
        }
        if phase == .climbing {
            return // already on its way
        }

        // Remember exactly where it is, so nothing jumps.
        let startY = presentedBodyY()
        let swingAngle = currentAngle(of: pivotLayer)
        let swayAngle = currentAngle(of: swayLayer)
        let startScale = ((bodyLayer.presentation() ?? bodyLayer).value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        let startOpacity = (bodyLayer.presentation() ?? bodyLayer).opacity
        generation += 1
        let token = generation
        phaseTask?.cancel()

        let moving: [CALayer] = [pivotLayer, swayLayer, bodyLayer, stickerLayer]
        for item in moving {
            item.removeAllAnimations()
        }
        instantly {
            pivotLayer.transform = CATransform3DIdentity
            swayLayer.transform = CATransform3DIdentity
            bodyLayer.transform = CATransform3DIdentity
            bodyLayer.position = CGPoint(x: 0, y: layout.hiddenY)
        }

        // Straighten up…
        pivotLayer.add(straighten(from: swingAngle, duration: 0.35), forKey: "straighten")
        swayLayer.add(straighten(from: swayAngle, duration: 0.35), forKey: "straighten")

        var duration: Double
        switch layout.entrance {
        case .thread:
            // …a tiny dip to get ready, then pull up into the notch.
            let distance = max(layout.hiddenY - startY, 1)
            duration = min(max(0.45 + Double(distance) / 420, 0.55), 0.95)
            let pullUp = CAKeyframeAnimation(keyPath: "position.y")
            pullUp.values = [startY, startY - 6, layout.hiddenY]
            pullUp.keyTimes = [0, 0.18, 1]
            pullUp.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(controlPoints: 0.45, 0, 0.6, 1),
            ]
            pullUp.duration = duration
            bodyLayer.add(pullUp, forKey: "climb")

            // A hand-over-hand wiggle while climbing.
            let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            wiggle.values = [0.0, 0.07, -0.07, 0.06, -0.05, 0.0]
            wiggle.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            wiggle.calculationMode = .cubic
            wiggle.duration = duration
            stickerLayer.add(wiggle, forKey: "wiggle")

            // Squash before the pull, stretch while zooming up (drawn characters only).
            if !layout.isPhoto {
                let stretch = CAKeyframeAnimation(keyPath: "transform.scale.y")
                stretch.values = [1.0, 0.92, 1.1, 1.0]
                stretch.keyTimes = [0, 0.18, 0.6, 1]
                stretch.duration = duration
                bodyLayer.add(stretch, forKey: "stretch")
            }

        case .peek:
            duration = 0.38
            let slide = CAKeyframeAnimation(keyPath: "position.y")
            slide.values = [startY, startY - 4, layout.hiddenY]
            slide.keyTimes = [0, 0.25, 1]
            slide.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
            ]
            slide.duration = duration
            bodyLayer.add(slide, forKey: "climb")

        case .pop:
            duration = 0.26
            // Shrink and fade away where it is, then tuck it into the notch.
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = startScale
            shrink.toValue = 0.2
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = startOpacity
            fade.toValue = 0.0
            let hold = CABasicAnimation(keyPath: "position.y")
            hold.fromValue = startY
            hold.toValue = startY + 10
            for animation in [shrink, fade, hold] {
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
            }
            bodyLayer.add(shrink, forKey: "pop-shrink")
            bodyLayer.add(fade, forKey: "pop-fade")
            bodyLayer.add(hold, forKey: "climb")
        }

        if layout.drawsFakeNotch {
            fadeFakeNotch(to: 0, delay: duration)
        }

        phase = .climbing
        let wait = realTime(duration + 0.05)
        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self = self, self.generation == token, !Task.isCancelled else { return }
            self.bodyLayer.removeAllAnimations()
            self.phase = .hidden
            completion()
        }
    }

    private func straighten(from angle: CGFloat, duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = angle
        animation.toValue = 0.0
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    // MARK: - Instant changes

    /// Hides the character straight away, with no animation.
    func hideNow() {
        stopEverything()
        guard let layout = layout else { return }
        instantly {
            bodyLayer.position = CGPoint(x: 0, y: layout.hiddenY)
            bodyLayer.opacity = 1
            fakeNotchLayer.opacity = 0
        }
    }

    /// Shows the character already out (used when settings change while it's out).
    func showHanging() {
        guard let layout = layout else { return }
        stopEverything()
        instantly {
            bodyLayer.position = CGPoint(x: 0, y: layout.hangingY)
            bodyLayer.opacity = 1
            if layout.drawsFakeNotch {
                fakeNotchLayer.opacity = 1
            }
        }
        startIdleMotion()
        phase = .hanging
    }

    private func stopEverything() {
        generation += 1
        phaseTask?.cancel()
        phaseTask = nil
        let all: [CALayer] = [pivotLayer, swayLayer, bodyLayer, stickerLayer, webLayer, fakeNotchLayer]
        for item in all {
            item.removeAllAnimations()
        }
        instantly {
            pivotLayer.transform = CATransform3DIdentity
            swayLayer.transform = CATransform3DIdentity
            bodyLayer.transform = CATransform3DIdentity
            stickerLayer.transform = CATransform3DIdentity
        }
        phase = .hidden
    }

    // MARK: - Helpers

    /// Changes layer properties immediately, without Core Animation's automatic fades.
    private func instantly(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private func fadeFakeNotch(to opacity: Float, delay: CFTimeInterval = 0) {
        let current = (fakeNotchLayer.presentation() ?? fakeNotchLayer).opacity
        fakeNotchLayer.removeAnimation(forKey: "fade")
        instantly {
            fakeNotchLayer.opacity = opacity
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = current
        fade.toValue = opacity
        fade.duration = 0.25
        if delay > 0 {
            // The stage may run faster or slower than the clock, so ask the layer for "now".
            fade.beginTime = fakeNotchLayer.convertTime(CACurrentMediaTime(), from: nil) + delay
            fade.fillMode = .backwards
        }
        fakeNotchLayer.add(fade, forKey: "fade")
    }

    private func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// A notch-like shape: flat top, rounded bottom corners.
    private static func notchShape(in rect: CGRect) -> CGPath {
        let radius = min(10, rect.height / 2, rect.width / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
