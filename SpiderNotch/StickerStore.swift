//
//  StickerStore.swift
//  SpiderNotch
//
//  "My Stickers": the characters you make from your own photos (or ready-made
//  pictures). Each one lives in its own folder on this Mac:
//
//    ~/Library/Application Support/SpiderNotch/Stickers/<id>/
//        info.json      name, kind, and the editor settings (to edit it again later)
//        sticker.png    the finished round sticker that goes on the notch
//        source.jpg     your photo (only for stickers made from a photo)
//
//  Nothing ever leaves your Mac: no uploads, no network.
//

import AppKit

/// How a photo sticker was made in the editor (saved so you can edit it again).
struct PhotoStickerEdit: Codable, Equatable {
    /// 1 = the photo's shorter side fills the editor's square.
    var zoom: Double = 1
    /// How far the photo is moved, as a fraction of the editor's square (y goes up).
    var offsetX: Double = 0
    var offsetY: Double = 0
    /// The round crop's diameter, as a fraction of the editor's square.
    var cropSize: Double = 0.72
    var removeBackground: Bool = false
    /// "#RRGGBB", or nil for see-through.
    var fillColor: String? = "#FFE3EC"
    /// none, thin, classic, thick, double, dotted
    var ringStyle: String = "classic"
    var ringColor: String = "#FFFFFF"
}

struct MySticker: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        /// Made from a photo in the editor: a round face sticker.
        case photo
        /// A ready-made picture (for example a transparent PNG drawing), used as it is.
        case picture
    }

    var id: String
    var name: String
    var kind: Kind
    var created: Date
    var modified: Date
    var edit: PhotoStickerEdit?
    var sourceFile: String?

    /// The ID used when this sticker is the character on the notch.
    var characterID: String { "sticker:\(id)" }
}

@MainActor
final class StickerStore {
    static let shared = StickerStore()

    /// Your stickers, oldest first.
    private(set) var stickers: [MySticker] = []
    private var thumbnails: [String: NSImage] = [:]

    private init() {
        reload()
    }

    static var folder: URL {
        AppInfo.supportFolder.appendingPathComponent("Stickers", isDirectory: true)
    }

    func folder(for id: String) -> URL {
        StickerStore.folder.appendingPathComponent(id, isDirectory: true)
    }

    func stickerURL(for id: String) -> URL {
        folder(for: id).appendingPathComponent("sticker.png")
    }

    private func faceURL(for id: String, face: String) -> URL {
        folder(for: id).appendingPathComponent("sticker-\(face).png")
    }

    // MARK: - Reading

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: StickerStore.folder,
                                                                     includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        var found: [MySticker] = []
        for folder in folders {
            let infoURL = folder.appendingPathComponent("info.json")
            guard let data = try? Data(contentsOf: infoURL),
                  let sticker = try? StickerStore.decoder.decode(MySticker.self, from: data),
                  FileManager.default.fileExists(atPath: stickerURL(for: sticker.id).path)
            else { continue }
            found.append(sticker)
        }
        stickers = found.sorted { $0.created < $1.created }
        thumbnails.removeAll()
    }

    func sticker(withID id: String) -> MySticker? {
        stickers.first(where: { $0.id == id })
    }

    /// The sticker's picture(s), trimmed and ready (without the sticker edge).
    func loadSticker(id: String) -> Sticker? {
        guard let info = sticker(withID: id), let image = StickerArt.loadImage(at: stickerURL(for: id)) else {
            return nil
        }
        if info.kind == .photo {
            // A real face: no pretend blinking or smiling, and never squashed.
            return StickerArt.prepare(image, isPhoto: true)
        }
        return StickerArt.prepare(image,
                                  blink: StickerArt.loadImage(at: faceURL(for: id, face: "blink")),
                                  happy: StickerArt.loadImage(at: faceURL(for: id, face: "happy")))
    }

    func thumbnail(id: String) -> NSImage? {
        if let cached = thumbnails[id] {
            return cached
        }
        guard let image = StickerArt.loadImage(at: stickerURL(for: id)) else { return nil }
        let thumbnail = StickerArt.nsImage(StickerArt.scaled(image, maxSide: 180))
        thumbnails[id] = thumbnail
        return thumbnail
    }

    /// The original photo of a photo sticker (to edit it again).
    func sourcePhoto(for sticker: MySticker) -> CGImage? {
        guard let file = sticker.sourceFile else { return nil }
        return StickerArt.loadImage(at: folder(for: sticker.id).appendingPathComponent(file))
    }

    // MARK: - Saving

    /// Saves a sticker made in the photo editor. Pass `existingID` to update one.
    @discardableResult
    func savePhotoSticker(existingID: String?, name: String, source: CGImage, rendered: CGImage,
                          edit: PhotoStickerEdit) throws -> MySticker {
        let id = existingID ?? UUID().uuidString
        let now = Date()
        var sticker = existingID.flatMap { self.sticker(withID: $0) }
            ?? MySticker(id: id, name: name, kind: .photo, created: now, modified: now, edit: edit, sourceFile: nil)
        sticker.name = cleanName(name)
        sticker.kind = .photo
        sticker.modified = now
        sticker.edit = edit

        let folder = self.folder(for: id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Keep the photo (so you can edit the sticker later): JPEG unless it's see-through.
            let keepsTransparency = StickerArt.hasTransparency(source)
            let sourceName = keepsTransparency ? "source.png" : "source.jpg"
            let sourceData = keepsTransparency ? StickerArt.pngData(source) : StickerArt.jpegData(source)
            guard let photoData = sourceData, let stickerData = StickerArt.pngData(rendered) else {
                throw StickerError.notSaved("The pictures couldn't be encoded.")
            }
            if let old = sticker.sourceFile, old != sourceName {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
            }
            try photoData.write(to: folder.appendingPathComponent(sourceName), options: .atomic)
            try stickerData.write(to: stickerURL(for: id), options: .atomic)
            sticker.sourceFile = sourceName
            try writeInfo(sticker)
        } catch let error as StickerError {
            throw error
        } catch {
            throw StickerError.notSaved(error.localizedDescription)
        }
        finishChange(changedID: id)
        return sticker
    }

    /// Adds a ready-made picture as it is. If "name-blink.png" (eyes closed) and
    /// "name-happy.png" (big smile) sit next to it, they're kept so it can blink and smile.
    @discardableResult
    func addPicture(from url: URL) throws -> MySticker {
        guard let original = StickerArt.loadPhoto(at: url, maxPixels: 4096) else { throw StickerError.unreadable }
        guard StickerArt.prepare(original) != nil else { throw StickerError.invisible }
        let id = UUID().uuidString
        let now = Date()
        let baseName = url.deletingPathExtension().lastPathComponent
        let sticker = MySticker(id: id, name: uniqueName(cleanName(baseName)), kind: .picture,
                                created: now, modified: now, edit: nil, sourceFile: nil)
        do {
            try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
            guard let data = StickerArt.pngData(StickerArt.scaled(original, maxSide: 1024)) else {
                throw StickerError.notSaved("The picture couldn't be encoded.")
            }
            try data.write(to: stickerURL(for: id), options: .atomic)
            copyExtraFaces(nextTo: url, matching: original, into: id)
            try writeInfo(sticker)
        } catch let error as StickerError {
            throw error
        } catch {
            throw StickerError.notSaved(error.localizedDescription)
        }
        finishChange(changedID: id)
        return sticker
    }

    private func copyExtraFaces(nextTo url: URL, matching original: CGImage, into id: String) {
        let folder = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? "png" : url.pathExtension
        for face in ["blink", "happy"] {
            let candidates = [face, face.capitalized].map { suffix in
                folder.appendingPathComponent("\(name)-\(suffix).\(fileExtension)")
            }
            guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let frame = StickerArt.loadPhoto(at: found, maxPixels: 4096),
                  frame.width == original.width,
                  frame.height == original.height,
                  let data = StickerArt.pngData(StickerArt.scaled(frame, maxSide: 1024))
            else { continue }
            try? data.write(to: faceURL(for: id, face: face), options: .atomic)
        }
    }

    func rename(_ id: String, to name: String) {
        guard var sticker = sticker(withID: id) else { return }
        let cleaned = cleanName(name)
        guard !cleaned.isEmpty, cleaned != sticker.name else { return }
        sticker.name = cleaned
        sticker.modified = Date()
        try? writeInfo(sticker)
        finishChange(changedID: nil)
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: folder(for: id))
        if Characters.currentID == "sticker:\(id)" {
            Characters.select(Preferences.Default.characterID)
        }
        finishChange(changedID: nil)
    }

    /// "My Sticker", "My Sticker 2", ...
    func uniqueName(_ base: String) -> String {
        let names = Set(stickers.map { $0.name })
        let start = base.isEmpty ? "My Sticker" : base
        guard names.contains(start) else { return start }
        var number = 2
        while names.contains("\(start) \(number)") {
            number += 1
        }
        return "\(start) \(number)"
    }

    private func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "My Sticker" : trimmed).prefix(40))
    }

    private func writeInfo(_ sticker: MySticker) throws {
        let data = try StickerStore.encoder.encode(sticker)
        try data.write(to: folder(for: sticker.id).appendingPathComponent("info.json"), options: .atomic)
    }

    private func finishChange(changedID: String?) {
        reload()
        NotificationCenter.default.post(name: .spiderNotchStickersChanged, object: nil)
        if let id = changedID, Characters.currentID == "sticker:\(id)" {
            // The sticker on the notch was edited: show the new version.
            NotificationCenter.default.post(name: .spiderNotchStickerChanged, object: nil)
        }
    }

    // MARK: - From SpiderNotch 1.0 and 1.1

    /// Earlier versions had a single "custom sticker". It becomes your first
    /// saved sticker (and stays in use), so nothing is lost when you update.
    func migrateLegacyStickerIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Preferences.Key.migratedLegacySticker) else { return }
        defaults.set(true, forKey: Preferences.Key.migratedLegacySticker)

        let oldFolder = AppInfo.supportFolder
        let oldSticker = oldFolder.appendingPathComponent("CustomSticker.png")
        guard FileManager.default.fileExists(atPath: oldSticker.path),
              let image = StickerArt.loadImage(at: oldSticker)
        else { return }

        let id = UUID().uuidString
        let now = Date()
        let sticker = MySticker(id: id, name: uniqueName("My Sticker"), kind: .picture,
                                created: now, modified: now, edit: nil, sourceFile: nil)
        do {
            try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
            guard let data = StickerArt.pngData(image) else { return }
            try data.write(to: stickerURL(for: id), options: .atomic)
            for (oldFace, newFace) in [("Blink", "blink"), ("Happy", "happy")] {
                let oldURL = oldFolder.appendingPathComponent("CustomSticker-\(oldFace).png")
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    try? FileManager.default.copyItem(at: oldURL, to: faceURL(for: id, face: newFace))
                }
            }
            try writeInfo(sticker)
        } catch {
            return
        }
        for name in ["CustomSticker.png", "CustomSticker-Blink.png", "CustomSticker-Happy.png"] {
            try? FileManager.default.removeItem(at: oldFolder.appendingPathComponent(name))
        }
        reload()
        // In 1.1 the custom sticker was always the one in use.
        Characters.select(sticker.characterID)
    }

    // MARK: - JSON

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
