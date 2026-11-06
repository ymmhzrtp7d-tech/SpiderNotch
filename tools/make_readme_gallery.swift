// Draws docs/images/characters.png (the character gallery in README.md)
// from the character strips. Run: swift tools/make_readme_gallery.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("SpiderNotch/Resources/Characters")
let data = try! Data(contentsOf: folder.appendingPathComponent("Library.json"))
let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
let characters = json["characters"] as! [[String: Any]]

let columns = 12, cell: CGFloat = 120, pad: CGFloat = 14
let rows = Int(ceil(Double(characters.count) / Double(columns)))
let size = CGSize(width: CGFloat(columns) * cell + pad * 2, height: CGFloat(rows) * cell + pad * 2)
let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
for (i, c) in characters.enumerated() {
    guard let src = NSImage(contentsOf: folder.appendingPathComponent(c["image"] as! String))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let faces = max((c["faces"] as? [String])?.count ?? 1, 1)
    let w = src.width / faces
    guard let face = src.cropping(to: CGRect(x: 0, y: 0, width: w, height: src.height)) else { continue }
    let scale = min((cell - 16) / CGFloat(face.width), (cell - 16) / CGFloat(face.height))
    let fw = CGFloat(face.width) * scale, fh = CGFloat(face.height) * scale
    let col = i % columns, row = i / columns
    let x = pad + CGFloat(col) * cell + (cell - fw) / 2
    let y = size.height - pad - CGFloat(row + 1) * cell + (cell - fh) / 2
    ctx.draw(face, in: CGRect(x: x, y: y, width: fw, height: fh))
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("docs/images/characters.png"))
print("Wrote docs/images/characters.png (\(characters.count) characters)")
