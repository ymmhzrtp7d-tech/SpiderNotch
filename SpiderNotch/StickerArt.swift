//
//  StickerArt.swift
//  SpiderNotch
//
//  Picture helpers shared by every character: loading files, trimming away
//  empty transparent edges, finding where the thread attaches, resizing, and
//  drawing the sticker edge (white, outline or glow) around a character.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A character that's ready to show.
struct Sticker {
    /// The picture, trimmed to its visible pixels.
    let image: CGImage
    /// Optional extra faces, trimmed exactly like `image`: eyes closed, and a big smile.
    let blinkImage: CGImage?
    let happyImage: CGImage?
    /// Where the thread attaches, from 0 to 1 (x: left → right, y: bottom → top).
    let anchor: CGPoint
    /// A photo of a real face. It's never squashed or stretched: it only moves,
    /// turns and grows evenly, so the face always looks like the original.
    var isPhoto: Bool = false

    var aspectRatio: CGFloat {
        CGFloat(image.width) / CGFloat(max(image.height, 1))
    }
}

enum StickerError: LocalizedError {
    case unreadable
    case invisible
    case notSaved(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "SpiderNotch couldn't open that file as a picture."
        case .invisible:
            return "That picture is completely transparent, so there would be nothing to see."
        case .notSaved(let reason):
            return "The sticker couldn't be saved. \(reason)"
        }
    }
}

enum StickerArt {

    // MARK: - Loading

    /// Reads a picture file at full resolution.
    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Reads a photo the right way up (phones save many photos sideways with a
    /// "rotate me" note), at most `maxPixels` on its longest side.
    /// Works for PNG, JPEG, HEIC, WebP and every other format macOS understands.
    static func loadPhoto(at url: URL, maxPixels: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return orientedImage(from: source, maxPixels: maxPixels)
    }

    static func loadPhoto(data: Data, maxPixels: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return orientedImage(from: source, maxPixels: maxPixels)
    }

    private static func orientedImage(from source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Cuts a horizontal strip of equal-width frames (open | blink | happy) apart.
    static func splitStrip(_ strip: CGImage, count: Int) -> [CGImage] {
        guard count > 1 else { return [strip] }
        let frameWidth = strip.width / count
        guard frameWidth > 0 else { return [strip] }
        return (0..<count).compactMap { index in
            strip.cropping(to: CGRect(x: index * frameWidth, y: 0, width: frameWidth, height: strip.height))
        }
    }

    // MARK: - Saving

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.9) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// True if any part of the picture can be see-through.
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    // MARK: - Preparing a picture

    /// Trims the transparent edges and finds where the thread should attach.
    /// Extra faces (blink, happy) get exactly the same trim so they line up.
    static func prepare(_ source: CGImage, blink: CGImage? = nil, happy: CGImage? = nil, isPhoto: Bool = false) -> Sticker? {
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        // 1. Look at a small copy: much faster, and plenty accurate for this.
        let scale = min(1.0, 256.0 / Double(max(width, height)))
        let smallWidth = max(1, Int((Double(width) * scale).rounded()))
        let smallHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let alpha = alphaValues(of: source, width: smallWidth, height: smallHeight) else { return nil }

        // 2. Find the box around everything that isn't transparent.
        //    (Row 0 is the TOP row of the picture.)
        var minX = smallWidth, minY = smallHeight, maxX = -1, maxY = -1
        for y in 0..<smallHeight {
            for x in 0..<smallWidth where alpha[y * smallWidth + x] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil } // completely transparent

        // 3. The thread attaches to the highest solid pixel near the middle (usually the head).
        let boxWidth = maxX - minX + 1
        let boxHeight = maxY - minY + 1
        let centerX = (minX + maxX) / 2
        let band = max(1, boxWidth / 10)
        var attachX = centerX
        var attachY = minY
        search: for y in minY...maxY {
            for x in max(minX, centerX - band)...min(maxX, centerX + band) where alpha[y * smallWidth + x] > 128 {
                attachX = x
                attachY = y
                break search
            }
        }

        // 4. Cut the full-size picture down to the box.
        let toFull = 1.0 / scale
        let cropX = max(0, Int((Double(minX) * toFull).rounded(.down)))
        let cropY = max(0, Int((Double(minY) * toFull).rounded(.down)))
        let cropWidth = min(width - cropX, Int((Double(boxWidth) * toFull).rounded(.up)) + 1)
        let cropHeight = min(height - cropY, Int((Double(boxHeight) * toFull).rounded(.up)) + 1)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        let trimmed = source.cropping(to: cropRect) ?? source

        let anchorX = (Double(attachX - minX) + 0.5) / Double(boxWidth)
        let anchorFromTop = Double(attachY - minY) / Double(boxHeight)
        let anchor = CGPoint(x: min(max(anchorX, 0.15), 0.85),
                             y: 1.0 - min(max(anchorFromTop, 0.0), 0.6))
        return Sticker(image: trimmed,
                       blinkImage: matchingFace(blink, like: source, crop: cropRect),
                       happyImage: matchingFace(happy, like: source, crop: cropRect),
                       anchor: anchor,
                       isPhoto: isPhoto)
    }

    /// An extra face only counts if it's the same size as the main picture.
    private static func matchingFace(_ face: CGImage?, like source: CGImage, crop: CGRect) -> CGImage? {
        guard let face = face, face.width == source.width, face.height == source.height else { return nil }
        return face.cropping(to: crop)
    }

    /// The transparency (0–255) of every pixel, after drawing the picture at the given size.
    private static func alphaValues(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else { return nil }

        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alpha[index] = pixels[index * 4 + 3]
        }
        return alpha
    }

    // MARK: - Resizing

    /// A copy that is at most `height` pixels tall (pictures are never enlarged).
    static func scaled(_ image: CGImage, toHeight height: Int) -> CGImage {
        guard height > 0, image.height > height else { return image }
        return resized(image, factor: Double(height) / Double(image.height))
    }

    /// A copy whose longest side is at most `maxSide` pixels.
    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard maxSide > 0, longest > maxSide else { return image }
        return resized(image, factor: Double(maxSide) / Double(longest))
    }

    private static func resized(_ image: CGImage, factor: Double) -> CGImage {
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let context = makeContext(width: width, height: height) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// An empty, see-through picture to draw into.
    static func makeContext(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil,
                         width: max(width, 1),
                         height: max(height, 1),
                         bitsPerComponent: 8,
                         bytesPerRow: 0,
                         space: colorSpace,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func nsImage(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    // MARK: - Last resort

    /// Only used if the built-in pictures are somehow missing: a simple round face.
    static func emergencySticker() -> Sticker {
        let size = 160
        let context = makeContext(width: size, height: size)!
        context.setFillColor(CGColor(red: 0.17, green: 0.16, blue: 0.27, alpha: 1))
        context.fillEllipse(in: CGRect(x: 30, y: 20, width: 100, height: 100))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 52, y: 62, width: 22, height: 26))
        context.fillEllipse(in: CGRect(x: 86, y: 62, width: 22, height: 26))
        let image = context.makeImage()!
        return prepare(image) ?? Sticker(image: image, blinkImage: nil, happyImage: nil,
                                         anchor: CGPoint(x: 0.5, y: 0.75))
    }
}

/// Draws the sticker edge around a character (and all its faces, so they still line up).
enum StickerBorder {
    static func apply(_ style: BorderStyle, to sticker: Sticker) -> Sticker {
        guard style != .none else { return sticker }
        let side = CGFloat(max(sticker.image.width, sticker.image.height))
        let thickness: CGFloat
        switch style {
        case .white: thickness = max(3, side * 0.045)
        case .outline: thickness = max(2, side * 0.02)
        case .glow: thickness = max(4, side * 0.05)
        case .none: thickness = 0
        }
        let pad = Int((style == .glow ? thickness * 2 : thickness + 2).rounded(.up))

        func bordered(_ image: CGImage?) -> CGImage? {
            guard let image = image else { return nil }
            return render(image, style: style, thickness: thickness, pad: pad)
        }

        let width = CGFloat(sticker.image.width)
        let height = CGFloat(sticker.image.height)
        let padding = CGFloat(pad)
        let anchor = CGPoint(x: (sticker.anchor.x * width + padding) / (width + padding * 2),
                             y: (sticker.anchor.y * height + padding) / (height + padding * 2))
        return Sticker(image: render(sticker.image, style: style, thickness: thickness, pad: pad),
                       blinkImage: bordered(sticker.blinkImage),
                       happyImage: bordered(sticker.happyImage),
                       anchor: anchor,
                       isPhoto: sticker.isPhoto)
    }

    private static func render(_ image: CGImage, style: BorderStyle, thickness: CGFloat, pad: Int) -> CGImage {
        guard let context = StickerArt.makeContext(width: image.width + pad * 2, height: image.height + pad * 2) else {
            return image
        }
        context.interpolationQuality = .high
        let rect = CGRect(x: pad, y: pad, width: image.width, height: image.height)

        switch style {
        case .white, .outline:
            let color = style == .white
                ? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                : CGColor(red: 0.16, green: 0.13, blue: 0.21, alpha: 1)
            if let silhouette = tinted(image, color: color) {
                // Stamp the silhouette in rings around the picture: a smooth, round edge.
                let steps = 28
                for ring in [1.0, 0.72, 0.44, 0.18] {
                    let radius = thickness * CGFloat(ring)
                    for step in 0..<steps {
                        let angle = Double(step) / Double(steps) * 2 * Double.pi
                        let dx = CGFloat(cos(angle)) * radius
                        let dy = CGFloat(sin(angle)) * radius
                        context.draw(silhouette, in: rect.offsetBy(dx: dx, dy: dy))
                    }
                }
            }
            context.draw(image, in: rect)
        case .glow:
            context.setShadow(offset: .zero, blur: thickness, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            context.draw(image, in: rect)
            context.draw(image, in: rect)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.draw(image, in: rect)
        case .none:
            context.draw(image, in: rect)
        }
        return context.makeImage() ?? image
    }

    /// The picture's shape filled with one color.
    private static func tinted(_ image: CGImage, color: CGColor) -> CGImage? {
        guard let context = StickerArt.makeContext(width: image.width, height: image.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color)
        context.fill(rect)
        return context.makeImage()
    }
}
