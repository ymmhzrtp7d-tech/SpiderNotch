//
//  NowPlayingView.swift
//  SpiderNotch
//
//  The Now Playing content of the Dynamic Island: artwork (or the video
//  thumbnail), title, artist or channel, the app or website, a progress bar
//  you can drag, the time, previous / play-pause / next, the volume, and
//  little app icons to switch between several things that are playing.
//
//  Everything is drawn with plain AppKit views and Core Animation layers, in
//  the island's style: white on black, springy, and light on the CPU.
//

import AppKit
import QuartzCore

enum NowPlayingMetrics {
    static let contentSize = CGSize(width: 404, height: 142)
    static let artworkSide: CGFloat = 70
}

@MainActor
final class NowPlayingView: NSView {
    var onOpenSource: (@MainActor (MediaSession) -> Void)?
    var onCommand: (@MainActor (MediaCommand, MediaSession) -> Void)?
    var onSeek: (@MainActor (MediaSession, Double) -> Void)?
    var onPickSession: (@MainActor (String) -> Void)?
    /// Called when you start and stop dragging a slider (the island stays open meanwhile).
    var onInteraction: (@MainActor (Bool) -> Void)?

    private let infoArea = ClickableArea()
    private let artworkLayer = CALayer()
    private let placeholderIcon = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let sourceIcon = NSImageView()
    private let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: 18, height: 14))
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let remainingLabel = NSTextField(labelWithString: "")
    private let progress = IslandSlider()
    private let previousButton = IslandButton(symbol: "backward.fill", size: 17)
    private let playButton = IslandButton(symbol: "play.fill", size: 24)
    private let nextButton = IslandButton(symbol: "forward.fill", size: 17)
    private let volumeIcon = IslandButton(symbol: "speaker.wave.2.fill", size: 12)
    private let volume = IslandSlider()
    private var chips: [SessionChip] = []

    private var session: MediaSession?
    private var sessionCount = 0
    private var ticker: Timer?
    private var shownArtwork: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("NowPlayingView is only created in code.")
    }

    private func build() {
        infoArea.wantsLayer = true
        infoArea.onClick = { [weak self] in
            guard let self = self, let session = self.session else { return }
            self.onOpenSource?(session)
        }
        addSubview(infoArea)

        artworkLayer.cornerRadius = 12
        artworkLayer.cornerCurve = .continuous
        artworkLayer.masksToBounds = true
        artworkLayer.contentsGravity = .resizeAspectFill
        artworkLayer.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor
        placeholderIcon.contentsGravity = .resizeAspect
        artworkLayer.addSublayer(placeholderIcon)
        infoArea.layer?.addSublayer(artworkLayer)

        for (label, size, weight, alpha) in [(titleLabel, CGFloat(14.5), NSFont.Weight.semibold, CGFloat(1)),
                                             (subtitleLabel, CGFloat(12.5), NSFont.Weight.regular, CGFloat(0.66)),
                                             (sourceLabel, CGFloat(11), NSFont.Weight.medium, CGFloat(0.46))] {
            label.font = NSFont.systemFont(ofSize: size, weight: weight)
            label.textColor = NSColor(white: 1, alpha: alpha)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.truncatesLastVisibleLine = true
            infoArea.addSubview(label)
        }
        sourceIcon.imageScaling = .scaleProportionallyUpOrDown
        infoArea.addSubview(sourceIcon)
        addSubview(waveform)

        for label in [elapsedLabel, remainingLabel] {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            label.textColor = NSColor(white: 1, alpha: 0.55)
            addSubview(label)
        }
        remainingLabel.alignment = .right

        progress.onChanging = { [weak self] value in
            self?.showDragTime(value)
        }
        progress.onDragging = { [weak self] dragging in
            self?.onInteraction?(dragging)
        }
        progress.onChanged = { [weak self] value in
            guard let self = self, let session = self.session, let duration = session.duration, duration > 0 else { return }
            self.onSeek?(session, value * duration)
        }
        addSubview(progress)

        previousButton.onPress = { [weak self] in self?.send(.previous) }
        playButton.onPress = { [weak self] in self?.send(.toggle) }
        nextButton.onPress = { [weak self] in self?.send(.next) }
        for button in [previousButton, playButton, nextButton] {
            addSubview(button)
        }

        volumeIcon.onPress = { [weak self] in
            SystemVolume.setMuted(!SystemVolume.isMuted)
            self?.refreshVolume()
        }
        volume.compact = true
        volume.onChanging = { value in
            SystemVolume.setVolume(Float(value))
        }
        volume.onDragging = { [weak self] dragging in
            self?.onInteraction?(dragging)
            if !dragging {
                self?.refreshVolume()
            }
        }
        volume.onChanged = { [weak self] _ in
            self?.refreshVolume()
        }
        addSubview(volumeIcon)
        addSubview(volume)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let width = bounds.width
        let top = bounds.height
        let isWide = session?.isVideo == true
        let artHeight = NowPlayingMetrics.artworkSide
        let artWidth = isWide ? (artHeight * 16 / 9).rounded() : artHeight
        let infoHeight = artHeight
        infoArea.frame = NSRect(x: 0, y: top - infoHeight, width: width - 4, height: infoHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.frame = CGRect(x: 0, y: 0, width: artWidth, height: artHeight)
        let iconSide: CGFloat = 38
        placeholderIcon.frame = CGRect(x: (artWidth - iconSide) / 2, y: (artHeight - iconSide) / 2,
                                       width: iconSide, height: iconSide)
        CATransaction.commit()

        let textX = artWidth + 14
        let chipsWidth = CGFloat(chips.count) * 24
        let textWidth = max(width - textX - 8 - max(chipsWidth, 22), 60)
        titleLabel.frame = NSRect(x: textX, y: infoHeight - 24, width: textWidth, height: 20)
        subtitleLabel.frame = NSRect(x: textX, y: infoHeight - 44, width: textWidth + max(chipsWidth - 22, 0), height: 17)
        sourceIcon.frame = NSRect(x: textX, y: infoHeight - 64, width: 14, height: 14)
        sourceLabel.frame = NSRect(x: textX + 19, y: infoHeight - 65, width: textWidth - 19, height: 15)

        // Little app icons to switch between several things that play (top right).
        var chipX = width - 22
        for chip in chips.reversed() {
            chip.frame = NSRect(x: chipX, y: top - 22, width: 20, height: 20)
            chipX -= 24
        }
        waveform.frame = NSRect(x: chips.isEmpty ? width - 20 : chipX + 2, y: top - 18, width: 18, height: 14)

        // Progress bar with the times on each side.
        let progressY = top - infoHeight - 24
        elapsedLabel.frame = NSRect(x: 0, y: progressY - 1, width: 42, height: 14)
        remainingLabel.frame = NSRect(x: width - 46, y: progressY - 1, width: 46, height: 14)
        progress.frame = NSRect(x: 46, y: progressY - 3, width: width - 46 - 50, height: 18)

        // Buttons in the middle, volume on the right.
        let buttonsY = progressY - 40
        playButton.frame = NSRect(x: width / 2 - 20, y: buttonsY, width: 40, height: 36)
        previousButton.frame = NSRect(x: width / 2 - 20 - 50, y: buttonsY, width: 40, height: 36)
        nextButton.frame = NSRect(x: width / 2 + 30, y: buttonsY, width: 40, height: 36)
        volume.frame = NSRect(x: width - 84, y: buttonsY + 9, width: 84, height: 18)
        volumeIcon.frame = NSRect(x: width - 84 - 26, y: buttonsY + 5, width: 24, height: 26)
    }

    // MARK: - Showing a session

    /// Shows a session (nil = nothing playing any more).
    func show(_ session: MediaSession?, all sessions: [MediaSession]) {
        let wasWide = self.session?.isVideo == true
        self.session = session
        rebuildChips(for: sessions, current: session?.id)

        guard let session = session else {
            titleLabel.stringValue = "Nothing is playing"
            subtitleLabel.stringValue = "Play some music or a video, then come back."
            sourceLabel.stringValue = ""
            sourceIcon.image = nil
            setArtwork(nil, icon: nil)
            setControlsEnabled(false)
            waveform.isPlaying = false
            updateProgress()
            return
        }

        titleLabel.stringValue = session.title
        subtitleLabel.stringValue = session.subtitle.isEmpty ? " " : session.subtitle
        sourceLabel.stringValue = session.sourceLine
        let icon = session.appIcon
        sourceIcon.image = icon
        setArtwork(session.artwork, icon: icon)
        setControlsEnabled(true)
        playButton.symbol = session.isPlaying ? "pause.fill" : "play.fill"
        waveform.isPlaying = session.isPlaying
        progress.isEnabled = session.canSeek
        updateProgress()
        refreshVolume()
        if wasWide != session.isVideo {
            needsLayout = true
        }
    }

    private func rebuildChips(for sessions: [MediaSession], current: String?) {
        let ids = sessions.count > 1 ? sessions.prefix(4).map { $0.id } : []
        let shownIDs = chips.map { $0.sessionID }
        if ids != shownIDs || sessions.count != sessionCount {
            for chip in chips {
                chip.removeFromSuperview()
            }
            var made: [SessionChip] = []
            if sessions.count > 1 {
                for item in sessions.prefix(4) {
                    let chip = SessionChip(sessionID: item.id, icon: item.appIcon, tooltip: "\(item.title) — \(item.sourceLine)")
                    chip.onPick = { [weak self] id in
                        self?.onPickSession?(id)
                    }
                    made.append(chip)
                }
            }
            chips = made
            for chip in chips {
                addSubview(chip)
            }
            sessionCount = sessions.count
            needsLayout = true
        }
        for chip in chips {
            chip.isSelected = chip.sessionID == current
        }
    }

    private func setArtwork(_ image: NSImage?, icon: NSImage?) {
        guard image !== shownArtwork || image == nil else { return }
        shownArtwork = image
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.contentsScale = scale
        placeholderIcon.contentsScale = scale
        if let image = image {
            var rect = NSRect(x: 0, y: 0, width: 240, height: 240)
            artworkLayer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            placeholderIcon.contents = nil
        } else {
            artworkLayer.contents = nil
            var rect = NSRect(x: 0, y: 0, width: 96, height: 96)
            placeholderIcon.contents = icon?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        CATransaction.commit()
        if image != nil {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.3
            fade.toValue = 1.0
            fade.duration = 0.25
            artworkLayer.add(fade, forKey: "fade")
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        for button in [previousButton, playButton, nextButton] {
            button.isEnabled = enabled
        }
        progress.isEnabled = enabled
    }

    private func send(_ command: MediaCommand) {
        guard let session = session else { return }
        if command == .toggle {
            playButton.symbol = session.isPlaying ? "play.fill" : "pause.fill"
        }
        onCommand?(command, session)
    }

    // MARK: - Time

    /// Moves the progress bar along twice a second while the island is open.
    func startTicking() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        updateProgress()
    }

    func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func updateProgress() {
        guard !progress.isDragging else { return }
        guard let session = session, let duration = session.duration, duration > 0,
              let elapsed = session.elapsed()
        else {
            // No length or position reported (a live stream, or an app that doesn't say).
            elapsedLabel.stringValue = ""
            remainingLabel.stringValue = ""
            progress.value = 0
            progress.isHidden = true
            return
        }
        progress.isHidden = false
        progress.value = elapsed / duration
        elapsedLabel.stringValue = NowPlayingView.time(elapsed)
        remainingLabel.stringValue = "-" + NowPlayingView.time(max(duration - elapsed, 0))
    }

    private func showDragTime(_ value: Double) {
        guard let duration = session?.duration, duration > 0 else { return }
        elapsedLabel.stringValue = NowPlayingView.time(value * duration)
        remainingLabel.stringValue = "-" + NowPlayingView.time(max(duration - value * duration, 0))
    }

    func refreshVolume() {
        if let level = SystemVolume.volume {
            volume.isHidden = false
            volumeIcon.isHidden = false
            let muted = SystemVolume.isMuted
            if !volume.isDragging {
                volume.value = muted ? 0 : Double(level)
            }
            volumeIcon.symbol = muted || level == 0 ? "speaker.slash.fill"
                : (level < 0.34 ? "speaker.wave.1.fill" : (level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        } else {
            volume.isHidden = true
            volumeIcon.isHidden = true
        }
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Controls

/// A round button with an SF Symbol: grows a little on hover, squishes when pressed.
@MainActor
final class IslandButton: NSView {
    var onPress: (@MainActor () -> Void)?
    var isEnabled = true {
        didSet { imageLayer.opacity = isEnabled ? 1 : 0.35 }
    }
    var symbol: String {
        didSet {
            if symbol != oldValue {
                updateImage()
            }
        }
    }

    private let size: CGFloat
    private let hoverLayer = CALayer()
    private let imageLayer = CALayer()
    private var hovering = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    init(symbol: String, size: CGFloat) {
        self.symbol = symbol
        self.size = size
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        hoverLayer.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
        updateImage()
    }

    required init?(coder: NSCoder) {
        fatalError("IslandButton is only created in code.")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        hoverLayer.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        hoverLayer.cornerRadius = side / 2
        imageLayer.bounds = CGRect(x: 0, y: 0, width: size * 1.3, height: size * 1.3)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateImage()
    }

    private func updateImage() {
        let scale = window?.backingScaleFactor ?? 2
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let tinted = NSImage(size: image.size, flipped: false) { drawRect in
            image.draw(in: drawRect)
            NSColor.white.set()
            drawRect.fill(using: .sourceAtop)
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = scale
        imageLayer.contents = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        animate()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressed = false
        animate()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        animate()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = pressed
        pressed = false
        animate()
        if wasPressed && inside && isEnabled {
            onPress?()
        }
    }

    private func animate() {
        let target: CGFloat = pressed ? 0.82 : (hovering && isEnabled ? 1.12 : 1)
        let current = ((imageLayer.presentation() ?? imageLayer).value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.setValue(target, forKeyPath: "transform.scale")
        hoverLayer.opacity = hovering && isEnabled ? 1 : 0
        CATransaction.commit()
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = current
        spring.toValue = target
        spring.stiffness = 420
        spring.damping = 2 * (pressed ? 1.0 : 0.6) * CGFloat(420).squareRoot()
        spring.duration = spring.settlingDuration
        imageLayer.add(spring, forKey: "scale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.duration = 0.15
        hoverLayer.add(fade, forKey: "fade")
    }
}

/// A thin white bar you can click or drag. Its knob appears when you hover it.
@MainActor
final class IslandSlider: NSView {
    var value: Double = 0 {
        didSet { needsDisplay = true }
    }
    var isEnabled = true {
        didSet { needsDisplay = true }
    }
    /// A smaller knob (volume).
    var compact = false
    var onChanging: (@MainActor (Double) -> Void)?
    var onChanged: (@MainActor (Double) -> Void)?
    var onDragging: (@MainActor (Bool) -> Void)?
    private(set) var isDragging = false
    private var hovering = false
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let thickness: CGFloat = (hovering || isDragging) ? 6 : 4
        let inset: CGFloat = 6
        let track = NSRect(x: inset, y: bounds.midY - thickness / 2, width: max(bounds.width - inset * 2, 1), height: thickness)
        NSColor(white: 1, alpha: isEnabled ? 0.22 : 0.1).setFill()
        NSBezierPath(roundedRect: track, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        guard isEnabled else { return }
        let clamped = min(max(value, 0), 1)
        var filled = track
        filled.size.width = max(track.width * CGFloat(clamped), thickness)
        NSColor(white: 1, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: filled, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        if hovering || isDragging {
            let knob: CGFloat = compact ? 10 : 12
            let center = NSPoint(x: track.minX + track.width * CGFloat(clamped), y: bounds.midY)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - knob / 2, y: center.y - knob / 2, width: knob, height: knob)).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isDragging = true
        onDragging?(true)
        track(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        track(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        track(event)
        isDragging = false
        onDragging?(false)
        onChanged?(value)
        needsDisplay = true
    }

    private func track(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inset: CGFloat = 6
        let fraction = (point.x - inset) / max(bounds.width - inset * 2, 1)
        value = Double(min(max(fraction, 0), 1))
        onChanging?(value)
    }
}

/// The artwork and text: click it to open where the media is playing.
@MainActor
final class ClickableArea: NSView {
    var onClick: (@MainActor () -> Void)?
    private var pressed = false
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        fade(to: 0.86)
    }

    override func mouseExited(with event: NSEvent) {
        pressed = false
        fade(to: 1)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        fade(to: 0.7)
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = pressed
        pressed = false
        fade(to: inside ? 0.86 : 1)
        if wasPressed && inside {
            onClick?()
        }
    }

    private func fade(to opacity: Float) {
        guard let layer = layer else { return }
        let current = (layer.presentation() ?? layer).opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = current
        animation.toValue = opacity
        animation.duration = 0.15
        layer.add(animation, forKey: "opacity")
    }
}

/// A tiny app icon in the island's corner, to switch to another thing that's playing.
@MainActor
final class SessionChip: NSView {
    let sessionID: String
    var onPick: (@MainActor (String) -> Void)?
    var isSelected = false {
        didSet { ring.opacity = isSelected ? 1 : 0 }
    }
    private let ring = CALayer()
    private let iconLayer = CALayer()

    init(sessionID: String, icon: NSImage?, tooltip: String) {
        self.sessionID = sessionID
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        layer = CALayer()
        wantsLayer = true
        toolTip = tooltip
        ring.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        ring.cornerRadius = 10
        ring.borderColor = NSColor(white: 1, alpha: 0.85).cgColor
        ring.borderWidth = 1.5
        ring.opacity = 0
        layer?.addSublayer(ring)
        iconLayer.frame = CGRect(x: 2, y: 2, width: 16, height: 16)
        iconLayer.contentsGravity = .resizeAspect
        var rect = NSRect(x: 0, y: 0, width: 48, height: 48)
        iconLayer.contents = icon?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        iconLayer.contentsScale = 2
        layer?.addSublayer(iconLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("SessionChip is only created in code.")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onPick?(sessionID)
        }
    }

    override func mouseDown(with event: NSEvent) {}
}

/// Three little bars that dance while something plays (like the iPhone's island).
@MainActor
final class WaveformView: NSView {
    var isPlaying = false {
        didSet {
            if isPlaying != oldValue {
                update()
            }
        }
    }
    private var bars: [CALayer] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
        for index in 0..<4 {
            let bar = CALayer()
            bar.backgroundColor = NSColor(red: 0.55, green: 0.9, blue: 0.7, alpha: 1).cgColor
            bar.cornerRadius = 1.25
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.frame = CGRect(x: CGFloat(index) * 4.5, y: 0, width: 2.5, height: 14)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        update()
    }

    required init?(coder: NSCoder) {
        fatalError("WaveformView is only created in code.")
    }

    private func update() {
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            if isPlaying {
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.25
                bounce.toValue = 1.0
                bounce.duration = 0.32 + Double(index % 3) * 0.09
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timeOffset = Double(index) * 0.13
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(bounce, forKey: "bounce")
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.setValue(0.22, forKeyPath: "transform.scale.y")
                CATransaction.commit()
            }
        }
    }
}
