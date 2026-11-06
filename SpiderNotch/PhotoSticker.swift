//
//  PhotoSticker.swift
//  SpiderNotch
//
//  Turns a photo into a round sticker: the crop circle, an optional background
//  colour, an optional cut-out of the person or pet (background removed), and
//  a cute ring around it. Everything happens on this Mac: the background
//  removal and face finding use Apple's Vision framework, on-device.
//

import AppKit
import CoreImage
import Vision

/// The ring drawn around a photo sticker.
enum RingStyle: String, CaseIterable, Identifiable {
    case none, thin, classic, thick, double, dotted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No Ring"
        case .thin: return "Thin"
        case .classic: return "Classic"
        case .thick: return "Thick"
        case .double: return "Double"
        case .dotted: return "Dotted"
        }
    }

    /// The ring's width for a sticker of the given size.
    func width(for size: CGFloat) -> CGFloat {
        switch self {
        case .none: return 0
        case .thin: return size * 0.024
        case .classic: return size * 0.045
        case .thick: return size * 0.075
        case .double: return size * 0.07
        case .dotted: return size * 0.065
        }
    }
}

enum PhotoStickerError: LocalizedError {
    case noSubject
    case failed

    var errorDescription: String? {
        switch self {
        case .noSubject:
            return "No person, pet or object stood out from the background in this photo."
        case .failed:
            return "The background couldn't be removed from this photo."
        }
    }
}

enum PhotoStickerRenderer {
    /// The finished sticker is a square picture this many pixels wide.
    static let outputSize = 512

    /// Draws the sticker. `cutout` is the photo with its background removed
    /// (used when `edit.removeBackground` is on).
    static func render(photo: CGImage, cutout: CGImage?, edit: PhotoStickerEdit, size: Int = outputSize) -> CGImage? {
        guard let context = StickerArt.makeContext(width: size, height: size) else { return nil }
        context.interpolationQuality = .high
        let side = CGFloat(size)
        let ring = RingStyle(rawValue: edit.ringStyle) ?? .classic
        let ringWidth = ring.width(for: side)
        let center = CGPoint(x: side / 2, y: side / 2)
        let outerRadius = side / 2 - 2
        let innerRadius = outerRadius - ringWidth
        let inner = CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                           width: innerRadius * 2, height: innerRadius * 2)

        // 1. Inside the circle: the background colour, then the photo.
        context.saveGState()
        context.addEllipse(in: inner)
        context.clip()
        if let hex = edit.fillColor, let color = NSColor(hex: hex) {
            context.setFillColor(color.cgColor)
            context.fill(inner)
        }
        let picture = (edit.removeBackground ? cutout : nil) ?? photo
        let frame = photoFrame(for: picture, edit: edit, innerDiameter: innerRadius * 2, center: center)
        context.draw(picture, in: frame)
        context.restoreGState()

        // 2. The ring.
        guard ring != .none, ringWidth > 0 else { return context.makeImage() }
        let ringColor = (NSColor(hex: edit.ringColor) ?? .white).cgColor
        let middle = innerRadius + ringWidth / 2
        let ringRect = CGRect(x: center.x - middle, y: center.y - middle, width: middle * 2, height: middle * 2)
        context.setStrokeColor(ringColor)
        context.setLineWidth(ringWidth)
        context.strokeEllipse(in: ringRect)
        switch ring {
        case .double:
            // A thin white line in the middle of the band: two rings.
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.setLineWidth(ringWidth * 0.24)
            context.strokeEllipse(in: ringRect)
        case .dotted:
            // White polka dots around the band.
            let count = max(12, Int((2 * CGFloat.pi * middle) / (ringWidth * 1.7)))
            let dot = ringWidth * 0.24
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                let x = center.x + cos(angle) * middle
                let y = center.y + sin(angle) * middle
                context.fillEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
            }
        default:
            break
        }
        return context.makeImage()
    }

    /// Where the photo goes, so the editor's crop circle maps exactly onto the sticker.
    ///
    /// In the editor (a square of side 1), the photo's shorter side is `zoom` wide,
    /// its middle sits at (offsetX, offsetY) from the centre, and the circle is
    /// `cropSize` wide. Here the circle is `innerDiameter` wide.
    static func photoFrame(for picture: CGImage, edit: PhotoStickerEdit, innerDiameter: CGFloat, center: CGPoint) -> CGRect {
        let shorter = CGFloat(max(min(picture.width, picture.height), 1))
        let crop = CGFloat(max(edit.cropSize, 0.05))
        let scale = innerDiameter * CGFloat(edit.zoom) / (shorter * crop)
        let width = CGFloat(picture.width) * scale
        let height = CGFloat(picture.height) * scale
        let midX = center.x + CGFloat(edit.offsetX) * innerDiameter / crop
        let midY = center.y + CGFloat(edit.offsetY) * innerDiameter / crop
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }

    // MARK: - Vision (on this Mac)

    /// The photo with everything but the main subject (person, pet, object) see-through.
    /// Slow-ish (about a second): call it off the main thread.
    static func removeBackground(from image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw PhotoStickerError.noSubject
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                    croppedToInstancesExtent: false)
        let masked = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        guard let output = context.createCGImage(masked, from: masked.extent) else {
            throw PhotoStickerError.failed
        }
        return output
    }

    /// The biggest face in the photo (0…1 coordinates, origin at the bottom left), if any.
    static func findFace(in image: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let faces = request.results ?? []
        return faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })?
            .boundingBox
    }

    /// Editor settings that put a face nicely in the middle of the circle.
    static func centered(on face: CGRect, in image: CGImage, edit: PhotoStickerEdit) -> PhotoStickerEdit {
        var edit = edit
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let shorter = max(min(width, height), 1)
        // The face (without hair) fills a bit more than half the circle.
        let faceWidth = max(face.width * width, 1)
        let zoom = 0.58 * CGFloat(edit.cropSize) * shorter / faceWidth
        edit.zoom = Double(min(max(zoom, 0.5), 6))
        let scale = CGFloat(edit.zoom) / shorter
        // Aim a little above the middle of the face, so the hair fits too.
        let targetX = face.midX * width
        let targetY = (face.midY + face.height * 0.08) * height
        edit.offsetX = Double(-(targetX - width / 2) * scale)
        edit.offsetY = Double(-(targetY - height / 2) * scale)
        return edit
    }
}

extension NSColor {
    /// A colour from "#RRGGBB".
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    /// "#RRGGBB" for this colour.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", min(max(red, 0), 255), min(max(green, 0), 255), min(max(blue, 0), 255))
    }
}
