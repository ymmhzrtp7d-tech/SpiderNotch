//
//  CharacterPreviewView.swift
//  SpiderNotch
//
//  A little pretend screen with a notch, where a character performs exactly
//  like it does on your real notch (same stage, same animations). Used in
//  Settings and in the photo sticker editor. Hover it to bump the character,
//  click it to make it hop.
//

import AppKit
import SwiftUI

@MainActor
final class CharacterPreviewNSView: NSView {
    private let backdrop = PreviewBackdropView()
    private let stage = SpiderStageView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    private var shownKey = ""
    private var sticker: Sticker?
    private var settings = SpiderSettings.current()
    private var loopTask: Task<Void, Never>?
    private var tracking: NSTrackingArea?
    private var cursorInside = false
    private var cursorWasOnSticker = false
    private var lastSize = CGSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        addSubview(backdrop)
        addSubview(stage)
    }

    required init?(coder: NSCoder) {
        fatalError("CharacterPreviewNSView is only created in code.")
    }

    /// Shows a character. `key` says what's shown: when it changes, the character
    /// makes its entrance again (with `keepPose`, it just updates in place).
    /// `makeSticker` is only called when the picture really needs (re)loading.
    func show(key: String, settings: SpiderSettings, keepPose: Bool = false, makeSticker: () -> Sticker) {
        let keyChanged = key != shownKey
        let needsSticker = keyChanged || sticker == nil || settings.border != self.settings.border
        guard needsSticker || settings != self.settings else { return }
        let replay = shownKey.isEmpty
            || (keyChanged && !keepPose)
            || settings.entrance != self.settings.entrance
        if needsSticker {
            sticker = makeSticker()
        }
        shownKey = key
        self.settings = settings
        configureStage(replay: replay)
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stage.frame = bounds
        if bounds.size != lastSize {
            lastSize = bounds.size
            configureStage(replay: true)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            loopTask?.cancel()
            loopTask = nil
        } else if sticker != nil {
            configureStage(replay: true)
        }
    }

    private func configureStage(replay: Bool) {
        guard let sticker = sticker, bounds.width > 40, bounds.height > 40 else { return }
        let layout = StageLayout.preview(size: bounds.size, settings: settings, sticker: sticker)
        backdrop.notchRect = NSRect(x: layout.notchMidX - layout.notchWidth / 2,
                                    y: bounds.height - layout.notchHeight,
                                    width: layout.notchWidth, height: layout.notchHeight)
        stage.configure(layout: layout, sticker: sticker, scale: window?.backingScaleFactor ?? 2)
        if replay {
            startLoop()
        } else {
            stage.showHanging()
        }
    }

    /// Comes out, stays a while, goes back in, and again (paused while you hover).
    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            while !Task.isCancelled {
                guard let self = self else { return }
                self.stage.drop()
                try? await Task.sleep(nanoseconds: 4_200_000_000)
                while !Task.isCancelled && self.cursorInside {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                if Task.isCancelled { return }
                self.stage.climb {}
                try? await Task.sleep(nanoseconds: 1_300_000_000)
            }
        }
    }

    // MARK: - Playing with it

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        cursorInside = true
        if !stage.isOut {
            stage.drop()
        }
    }

    override func mouseExited(with event: NSEvent) {
        cursorInside = false
        cursorWasOnSticker = false
    }

    override func mouseMoved(with event: NSEvent) {
        let point = stage.convert(event.locationInWindow, from: nil)
        let onSticker = stage.stickerContains(viewPoint: point)
        if onSticker && !cursorWasOnSticker {
            stage.poke(deltaX: event.deltaX)
        }
        cursorWasOnSticker = onSticker
    }

    override func mouseDown(with event: NSEvent) {
        let point = stage.convert(event.locationInWindow, from: nil)
        if stage.stickerContains(viewPoint: point) {
            stage.celebrate()
        } else if !stage.isOut {
            stage.drop()
        }
    }
}

/// The pretend screen: a soft wallpaper, a menu bar and a notch.
@MainActor
final class PreviewBackdropView: NSView {
    var notchRect = NSRect.zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = [NSColor(red: 0.42, green: 0.52, blue: 0.86, alpha: 1),
                      NSColor(red: 0.78, green: 0.56, blue: 0.86, alpha: 1),
                      NSColor(red: 0.98, green: 0.75, blue: 0.70, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -65)
        let barHeight = notchRect.height > 0 ? notchRect.height : 22
        NSColor(white: 1, alpha: 0.28).setFill()
        NSRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight).fill()
        guard notchRect.width > 0 else { return }
        NSColor.black.setFill()
        let radius = min(9, notchRect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: notchRect.minX, y: notchRect.maxY))
        path.line(to: NSPoint(x: notchRect.minX, y: notchRect.minY + radius))
        path.appendArc(from: NSPoint(x: notchRect.minX, y: notchRect.minY),
                       to: NSPoint(x: notchRect.minX + radius, y: notchRect.minY), radius: radius)
        path.line(to: NSPoint(x: notchRect.maxX - radius, y: notchRect.minY))
        path.appendArc(from: NSPoint(x: notchRect.maxX, y: notchRect.minY),
                       to: NSPoint(x: notchRect.maxX, y: notchRect.minY + radius), radius: radius)
        path.line(to: NSPoint(x: notchRect.maxX, y: notchRect.maxY))
        path.close()
        path.fill()
    }
}

/// The preview for SwiftUI. Give it a character ID, or a sticker made on the spot.
struct CharacterPreview: NSViewRepresentable {
    var characterID: String
    var settings: SpiderSettings
    /// When set, this picture is shown instead of the character (the photo editor's live preview).
    var sticker: Sticker? = nil
    /// Bump this whenever `sticker` changes.
    var stickerVersion: Int = 0

    func makeNSView(context: Context) -> CharacterPreviewNSView {
        CharacterPreviewNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
    }

    func updateNSView(_ view: CharacterPreviewNSView, context: Context) {
        let settings = self.settings
        if let sticker = sticker {
            view.show(key: "\(characterID)#\(stickerVersion)", settings: settings, keepPose: true) {
                StickerBorder.apply(settings.border, to: sticker)
            }
        } else {
            let id = characterID
            view.show(key: id, settings: settings) {
                Characters.loadSticker(id: id, border: settings.border)
            }
        }
    }
}
