//
//  StageLayout.swift
//  SpiderNotch
//
//  All the measurements for the animation, worked out from the notch
//  position and your settings. Pure math: nothing here draws anything.
//

import AppKit

struct StageLayout {
    /// Where the see-through window goes (screen coordinates).
    let panelFrame: NSRect
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    /// The middle of the notch, in the window's own coordinates.
    let notchMidX: CGFloat
    /// True on screens without a real notch: we then draw a small black one.
    let drawsFakeNotch: Bool
    /// The sticker's size on screen, in points.
    let stickerSize: CGSize
    /// Where the thread attaches to the sticker (0…1, y = 1 is the top edge).
    let anchor: CGPoint
    /// The hinge the character swings around: the top edge of the screen, above
    /// the spot it hangs from (in the window's own coordinates).
    let pivot: CGPoint
    /// Height of the attach point, measured from the hinge (negative = further down).
    let hangingY: CGFloat
    /// Same, when the character is tucked away inside the notch.
    let hiddenY: CGFloat
    /// How lively the motion is (from your settings).
    let swing: CGFloat
    let bounce: CGFloat
    let floatAmount: CGFloat
    /// 1 = normal speed, 2 = twice as fast.
    let speed: CGFloat
    let entrance: EntranceStyle
    /// Photos of real faces are only moved, turned and scaled evenly.
    let isPhoto: Bool
    /// The furthest the character may ever swing, in radians.
    let maxSwingAngle: CGFloat

    var showsThread: Bool { entrance == .thread }

    // Screen positions, used to decide whether the cursor is near the character.
    private let attachScreenX: CGFloat
    private let screenTop: CGFloat

    /// - Parameter extraDrop: extra room below the notch (used while the Dynamic
    ///   Island is open, so the character hangs below the island instead).
    init(geometry: NotchGeometry, settings: SpiderSettings, sticker: Sticker, extraDrop: CGFloat = 0) {
        let notchHeight = geometry.notchRect.height
        let notchWidth = geometry.notchRect.width
        let height = settings.stickerSize
        let width = min(height * sticker.aspectRatio, height * 2.2)
        let web = settings.webLength
        let maxAngle: CGFloat = 26 * .pi / 180
        let drop = max(extraDrop, 0)

        // Where along the notch the character hangs.
        let notch = geometry.notchRect
        let inset = min(max(width * 0.35, 14), notchWidth / 2)
        let attachX: CGFloat
        switch settings.position {
        case .left: attachX = notch.minX + inset
        case .center: attachX = notch.midX
        case .right: attachX = notch.maxX - inset
        }

        // How far below the top of the screen the character's attach point hangs.
        let hangDepth: CGFloat
        switch settings.entrance {
        case .thread: hangDepth = notchHeight + drop + web
        case .peek: hangDepth = notchHeight + drop - height * 0.3
        case .pop: hangDepth = notchHeight + drop + 10
        }

        // Big enough for the widest swing and the deepest bounce, and no bigger.
        let reach = hangDepth + height
        let halfWidth = max(notchWidth / 2 + 10 + abs(attachX - notch.midX),
                            reach * sin(maxAngle) + width / 2 + 30)
        let overshoot = (web + height) * (0.2 + 0.35 * settings.bounce)
        let panelWidth = (halfWidth * 2).rounded(.up)
        let panelHeight = (reach + overshoot + 40 + settings.floatAmount * 6).rounded(.up)

        let screen = geometry.screenFrame
        var x = attachX - panelWidth / 2
        x = min(max(x, screen.minX), screen.maxX - panelWidth)
        panelFrame = NSRect(x: x, y: screen.maxY - panelHeight, width: panelWidth, height: panelHeight)

        self.notchHeight = notchHeight
        self.notchWidth = notchWidth
        notchMidX = notch.midX - x
        drawsFakeNotch = !geometry.isHardwareNotch
        stickerSize = CGSize(width: width, height: height)
        anchor = sticker.anchor
        pivot = CGPoint(x: attachX - x, y: panelHeight)
        hangingY = -hangDepth
        // Hidden: the sticker's bottom edge sits just above the bottom of the notch.
        hiddenY = -notchHeight + 2 + height * sticker.anchor.y
        swing = settings.swing
        bounce = settings.bounce
        floatAmount = settings.floatAmount
        speed = settings.speed
        entrance = settings.entrance
        isPhoto = sticker.isPhoto
        maxSwingAngle = maxAngle
        attachScreenX = attachX
        screenTop = screen.maxY
    }

    /// A layout for the little preview in Settings: a pretend notch at the top
    /// middle of a box of the given size.
    static func preview(size: CGSize, settings: SpiderSettings, sticker: Sticker) -> StageLayout {
        var settings = settings
        // Keep the preview inside its box.
        settings.stickerSize = min(settings.stickerSize, size.height * 0.42)
        settings.webLength = min(settings.webLength, size.height * 0.3)
        let notchWidth = min(150, size.width * 0.4)
        let notchHeight: CGFloat = 22
        let frame = NSRect(origin: .zero, size: size)
        let geometry = NotchGeometry(screenFrame: frame,
                                     notchRect: NSRect(x: size.width / 2 - notchWidth / 2, y: size.height - notchHeight,
                                                       width: notchWidth, height: notchHeight),
                                     isHardwareNotch: false,
                                     backingScale: 2)
        return StageLayout(geometry: geometry, settings: settings, sticker: sticker)
    }

    /// Where the attach point is when the character is fully out (screen coordinates).
    private var attachY: CGFloat {
        screenTop + hangingY
    }

    /// The sticker's frame on screen while it hangs still.
    var stickerZone: NSRect {
        NSRect(x: attachScreenX - anchor.x * stickerSize.width,
               y: attachY - anchor.y * stickerSize.height,
               width: stickerSize.width,
               height: stickerSize.height)
    }

    /// While the character is out, keeping the cursor around it (or its thread) keeps it out.
    var keepAliveZone: NSRect {
        let depth = max(screenTop - attachY, 0)
        let sideRoom = (depth + stickerSize.height) * 0.22 + 16
        let body = stickerZone.insetBy(dx: -sideRoom, dy: -18)
        let thread = NSRect(x: attachScreenX - sideRoom,
                            y: body.maxY - 1,
                            width: sideRoom * 2,
                            height: max(screenTop - body.maxY + 4, 1))
        return body.union(thread)
    }
}
