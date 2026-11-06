//
//  AppSwitcherView.swift
//  SpiderNotch
//
//  The row of app icons inside the Dynamic Island. Hover an icon to see its
//  name, click it to switch to that app. The app you're using is highlighted,
//  and the row scrolls sideways when lots of apps are open.
//

import AppKit
import QuartzCore

/// Sizes for the row of icons.
enum SwitcherMetrics {
    static let cellSize: CGFloat = 64
    static let iconSize: CGFloat = 46
    static let spacing: CGFloat = 6
    static let nameHeight: CGFloat = 22

    /// The width needed to show every app without scrolling.
    static func rowWidth(appCount: Int) -> CGFloat {
        let count = CGFloat(max(appCount, 1))
        return count * cellSize + (count - 1) * spacing
    }
}

@MainActor
final class AppSwitcherView: NSView {
    /// Called when you pick an app.
    var onPick: (@MainActor (NSRunningApplication) -> Void)?

    private let apps: RunningApps
    private let scrollView = HorizontalScrollView()
    private let strip = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var cells: [AppCell] = []
    private var hoveredCell: AppCell?
    private var keyboardIndex: Int?

    init(frame frameRect: NSRect, apps: RunningApps) {
        self.apps = apps
        super.init(frame: frameRect)
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = strip
        addSubview(scrollView)

        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = NSColor(white: 1, alpha: 0.95)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.alphaValue = 0
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("AppSwitcherView is only created in code.")
    }

    // MARK: - Building the row

    /// Rebuilds the icons from the current list of open apps.
    func reloadApps() {
        for cell in cells {
            cell.removeFromSuperview()
        }
        cells = apps.apps.map { app in
            let cell = AppCell(app: app)
            cell.onHover = { [weak self] hovered, isInside in
                self?.cellHovered(hovered, isInside: isInside)
            }
            cell.onPick = { [weak self] picked in
                self?.onPick?(picked.app)
            }
            return cell
        }
        for cell in cells {
            strip.addSubview(cell)
        }
        hoveredCell = nil
        keyboardIndex = nil
        layoutRow()
        refreshActive(animated: false)
    }

    /// Called when apps open, quit or come forward while the island is showing.
    func syncApps() {
        let current = apps.apps.map { $0.processIdentifier }
        let shown = cells.map { $0.app.processIdentifier }
        if current != shown {
            reloadApps()
        } else {
            refreshActive(animated: true)
        }
    }

    override func layout() {
        super.layout()
        layoutRow()
    }

    private func layoutRow() {
        let rowHeight = SwitcherMetrics.cellSize
        scrollView.frame = NSRect(x: 0, y: SwitcherMetrics.nameHeight, width: bounds.width, height: rowHeight)
        let needed = SwitcherMetrics.rowWidth(appCount: cells.count)
        let visible = scrollView.contentSize.width
        let stripWidth = max(needed, visible)
        strip.frame = NSRect(x: 0, y: 0, width: stripWidth, height: rowHeight)
        // Centre the icons when they all fit; otherwise they scroll.
        var x = ((stripWidth - needed) / 2).rounded()
        for cell in cells {
            cell.frame = NSRect(x: x, y: 0, width: SwitcherMetrics.cellSize, height: rowHeight)
            x += SwitcherMetrics.cellSize + SwitcherMetrics.spacing
        }
        positionNameLabel()
    }

    // MARK: - Highlight and names

    private var activeCell: AppCell? {
        guard let active = apps.activeApp else { return nil }
        return cells.first(where: { $0.app.processIdentifier == active.processIdentifier })
    }

    private var keyboardCell: AppCell? {
        guard let index = keyboardIndex, cells.indices.contains(index) else { return nil }
        return cells[index]
    }

    /// Highlights the app you're using (and keeps it up to date).
    func refreshActive(animated: Bool) {
        let activeID = apps.activeApp?.processIdentifier
        for cell in cells {
            cell.setActive(cell.app.processIdentifier == activeID, animated: animated)
            cell.refreshHiddenLook()
        }
        updateNameLabel()
    }

    /// Moves the highlight to an app straight away (when you pick it).
    func showAsActive(_ app: NSRunningApplication) {
        for cell in cells {
            cell.setActive(cell.app.processIdentifier == app.processIdentifier, animated: true)
        }
    }

    private func cellHovered(_ cell: AppCell, isInside: Bool) {
        if isInside {
            hoveredCell = cell
            keyboardIndex = nil
            updateKeyboardRing()
        } else if hoveredCell === cell {
            hoveredCell = nil
        }
        updateNameLabel()
    }

    /// Shows the name of the app under the cursor (or the active app's, dimmer).
    private func updateNameLabel() {
        let focused = hoveredCell ?? keyboardCell
        guard let cell = focused ?? activeCell else {
            nameLabel.animator().alphaValue = 0
            return
        }
        nameLabel.stringValue = cell.appName
        positionNameLabel()
        nameLabel.animator().alphaValue = focused == nil ? 0.55 : 1
    }

    private func positionNameLabel() {
        guard let cell = hoveredCell ?? keyboardCell ?? activeCell else { return }
        let cellFrame = convert(cell.bounds, from: cell)
        let width: CGFloat = 220
        var x = cellFrame.midX - width / 2
        x = min(max(x, 0), max(bounds.width - width, 0))
        nameLabel.frame = NSRect(x: x, y: 2, width: width, height: SwitcherMetrics.nameHeight - 4)
    }

    // MARK: - Keyboard

    /// ← and → move a selection ring around the icons.
    func moveSelection(by step: Int) {
        guard !cells.isEmpty else { return }
        let activeIndex = cells.firstIndex(where: { $0 === activeCell }) ?? 0
        let start = keyboardIndex ?? activeIndex
        let next = ((start + step) % cells.count + cells.count) % cells.count
        keyboardIndex = next
        hoveredCell = nil
        updateKeyboardRing()
        reveal(cells[next])
        updateNameLabel()
    }

    /// Return switches to the selected app. Returns false if nothing is selected.
    func pickSelection() -> Bool {
        guard let cell = keyboardCell ?? hoveredCell else { return false }
        cell.playPickAnimation()
        onPick?(cell.app)
        return true
    }

    private func updateKeyboardRing() {
        for (index, cell) in cells.enumerated() {
            cell.setKeyboardFocus(index == keyboardIndex)
        }
    }

    // MARK: - Scrolling

    func scrollToActive() {
        layoutSubtreeIfNeeded()
        if let cell = activeCell {
            reveal(cell)
        }
    }

    /// Scrolls the row so this icon is fully visible.
    private func reveal(_ cell: AppCell) {
        let target = cell.frame.insetBy(dx: -SwitcherMetrics.spacing * 3, dy: 0)
        strip.scrollToVisible(target)
        positionNameLabel()
    }
}

/// One app in the row: its real icon, a soft highlight when it's the app
/// you're using, and springy animations when you hover or click.
@MainActor
final class AppCell: NSView {
    let app: NSRunningApplication
    let appName: String
    var onHover: (@MainActor (AppCell, Bool) -> Void)?
    var onPick: (@MainActor (AppCell) -> Void)?

    private let highlightLayer = CALayer()
    private let ringLayer = CALayer()
    private let iconLayer = CALayer()
    private let dotLayer = CALayer()
    private var isHovered = false
    private var isPressed = false
    private var hoverTracking: NSTrackingArea?

    init(app: NSRunningApplication) {
        self.app = app
        self.appName = app.localizedName
            ?? app.bundleURL?.deletingPathExtension().lastPathComponent
            ?? "App"
        let size = SwitcherMetrics.cellSize
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        layer = CALayer()
        wantsLayer = true
        buildLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("AppCell is only created in code.")
    }

    private func buildLayers() {
        guard let root = layer else { return }
        let size = SwitcherMetrics.cellSize
        let iconSize = SwitcherMetrics.iconSize

        // Soft rounded square behind the active app.
        highlightLayer.frame = CGRect(x: 3, y: 3, width: size - 6, height: size - 6)
        highlightLayer.cornerRadius = 15
        highlightLayer.cornerCurve = .continuous
        highlightLayer.backgroundColor = NSColor(white: 1, alpha: 0.17).cgColor
        highlightLayer.opacity = 0
        root.addSublayer(highlightLayer)

        // Ring for keyboard selection (← →).
        ringLayer.frame = highlightLayer.frame
        ringLayer.cornerRadius = 15
        ringLayer.cornerCurve = .continuous
        ringLayer.borderColor = NSColor(white: 1, alpha: 0.7).cgColor
        ringLayer.borderWidth = 2
        ringLayer.opacity = 0
        root.addSublayer(ringLayer)

        // The app's real icon.
        iconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        iconLayer.position = CGPoint(x: size / 2, y: size / 2 + 2)
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.minificationFilter = .trilinear
        root.addSublayer(iconLayer)

        // Little dot under the active app, like the Dock.
        dotLayer.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        dotLayer.cornerRadius = 2
        dotLayer.position = CGPoint(x: size / 2, y: 4)
        dotLayer.backgroundColor = NSColor(white: 1, alpha: 0.9).cgColor
        dotLayer.opacity = 0
        root.addSublayer(dotLayer)

        refreshHiddenLook()
    }

    // MARK: - Icon image (sharp on Retina)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateIconImage()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateIconImage()
    }

    private func updateIconImage() {
        let scale = window?.backingScaleFactor ?? 2
        let pixels = Int((SwitcherMetrics.iconSize * scale).rounded(.up))
        var rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let image = app.icon ?? NSImage(named: NSImage.applicationIconName)
        let picture = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let layers: [CALayer] = [highlightLayer, ringLayer, iconLayer, dotLayer]
        for item in layers {
            item.contentsScale = scale
        }
        layer?.contentsScale = scale
        iconLayer.contents = picture
        CATransaction.commit()
    }

    /// Hidden apps look see-through, like in the Dock.
    func refreshHiddenLook() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.opacity = app.isHidden ? 0.5 : 1
        CATransaction.commit()
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverTracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        animateIcon()
        onHover?(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        animateIcon()
        onHover?(self, false)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        animateIcon()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let wasPressed = isPressed
        isPressed = false
        if wasPressed && bounds.contains(point) {
            playPickAnimation()
            onPick?(self)
        } else {
            animateIcon()
        }
    }

    // MARK: - Animations

    /// Grow a little when hovered, shrink when pressed.
    private func animateIcon() {
        let scale: CGFloat = isPressed ? 0.88 : (isHovered ? 1.16 : 1.0)
        let lift: CGFloat = (isHovered && !isPressed) ? 3 : 0
        spring(iconLayer, keyPath: "transform.scale", to: scale, dampingRatio: isPressed ? 1.0 : 0.6)
        spring(iconLayer, keyPath: "transform.translation.y", to: lift, dampingRatio: 0.8)
    }

    /// A happy bounce when you pick the app.
    func playPickAnimation() {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [0.88, 1.24, 0.95, 1.05, 1.0]
        bounce.keyTimes = [0, 0.3, 0.55, 0.8, 1]
        bounce.duration = 0.42
        bounce.calculationMode = .cubic
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.setValue(1.0, forKeyPath: "transform.scale")
        CATransaction.commit()
        iconLayer.add(bounce, forKey: "transform.scale")
    }

    func setActive(_ active: Bool, animated: Bool) {
        fade(highlightLayer, to: active ? 1 : 0, animated: animated)
        fade(dotLayer, to: active ? 1 : 0, animated: animated)
    }

    func setKeyboardFocus(_ focused: Bool) {
        fade(ringLayer, to: focused ? 1 : 0, animated: true)
    }

    private func spring(_ target: CALayer, keyPath: String, to value: CGFloat, dampingRatio: CGFloat) {
        let current = ((target.presentation() ?? target).value(forKeyPath: keyPath) as? CGFloat) ?? value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        let stiffness: CGFloat = 420
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = current
        animation.toValue = value
        animation.mass = 1
        animation.stiffness = stiffness
        animation.damping = 2 * dampingRatio * stiffness.squareRoot()
        animation.duration = animation.settlingDuration
        target.add(animation, forKey: keyPath)
    }

    private func fade(_ target: CALayer, to opacity: Float, animated: Bool) {
        let current = (target.presentation() ?? target).opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.opacity = opacity
        CATransaction.commit()
        guard animated, current != opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = current
        animation.toValue = opacity
        animation.duration = 0.25
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        target.add(animation, forKey: "opacity")
    }
}

/// A scroll view that also scrolls sideways with an ordinary mouse wheel.
final class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(deltaX), let document = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let clip = contentView
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let maxX = max(0, document.frame.width - clip.bounds.width)
        var origin = clip.bounds.origin
        origin.x = min(max(origin.x - deltaY * step, 0), maxX)
        clip.scroll(to: origin)
        reflectScrolledClipView(clip)
    }
}
