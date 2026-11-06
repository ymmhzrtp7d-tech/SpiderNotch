//
//  CharacterLibrary.swift
//  SpiderNotch
//
//  The built-in characters (the animal library), and which character is in use.
//
//  The library is not a fixed list in the code: it's read from Library.json
//  inside the app (Resources/Characters), plus any extra "character packs" in
//  ~/Library/Application Support/SpiderNotch/Character Packs/<pack name>/,
//  each with its own Library.json and pictures. A future update can simply
//  add pictures and lines to Library.json (see tools/character-art).
//
//  Each character is one PNG "strip": its faces side by side, in the order
//  listed under "faces" (open, blink, happy).
//

import AppKit

struct CharacterCategory: Identifiable, Hashable {
    let id: String
    let name: String
    /// An SF Symbol name for the category's little icon.
    let symbol: String
}

struct LibraryCharacter: Identifiable, Hashable {
    /// "builtin:cat", or "pack:<pack folder>/<id>" for characters from a pack.
    let id: String
    let name: String
    let categoryID: String
    let imageURL: URL
    let faces: [String]
}

@MainActor
final class CharacterLibrary {
    static let shared = CharacterLibrary()

    private(set) var categories: [CharacterCategory] = []
    private(set) var characters: [LibraryCharacter] = []
    private var thumbnails: [String: NSImage] = [:]

    private init() {
        reload()
    }

    /// Where extra character packs can be installed.
    static var packsFolder: URL {
        AppInfo.supportFolder.appendingPathComponent("Character Packs", isDirectory: true)
    }

    /// Reads the built-in library and every installed pack.
    func reload() {
        var categories: [CharacterCategory] = []
        var characters: [LibraryCharacter] = []
        var seenCategories = Set<String>()
        var seenCharacters = Set<String>()

        func add(manifestAt url: URL, prefix: String) {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data)
            else { return }
            let folder = url.deletingLastPathComponent()
            for category in manifest.categories ?? [] where !seenCategories.contains(category.id) {
                seenCategories.insert(category.id)
                categories.append(CharacterCategory(id: category.id, name: category.name,
                                                    symbol: category.symbol ?? "star.fill"))
            }
            for entry in manifest.characters {
                let id = prefix + entry.id
                let imageURL = folder.appendingPathComponent(entry.image)
                guard !seenCharacters.contains(id),
                      FileManager.default.fileExists(atPath: imageURL.path)
                else { continue }
                seenCharacters.insert(id)
                if !seenCategories.contains(entry.category) {
                    seenCategories.insert(entry.category)
                    categories.append(CharacterCategory(id: entry.category, name: entry.category.capitalized,
                                                        symbol: "star.fill"))
                }
                characters.append(LibraryCharacter(id: id, name: entry.name, categoryID: entry.category,
                                                   imageURL: imageURL, faces: entry.faces ?? ["open"]))
            }
        }

        if let builtIn = Bundle.main.url(forResource: "Library", withExtension: "json", subdirectory: "Characters") {
            add(manifestAt: builtIn, prefix: "builtin:")
        }
        let packs = (try? FileManager.default.contentsOfDirectory(at: CharacterLibrary.packsFolder,
                                                                   includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        for pack in packs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifest = pack.appendingPathComponent("Library.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                add(manifestAt: manifest, prefix: "pack:\(pack.lastPathComponent)/")
            }
        }

        self.categories = categories
        self.characters = characters
        thumbnails.removeAll()
    }

    func character(withID id: String) -> LibraryCharacter? {
        characters.first(where: { $0.id == id })
    }

    func characters(in categoryID: String) -> [LibraryCharacter] {
        categoryID == "all" ? characters : characters.filter { $0.categoryID == categoryID }
    }

    /// The character's faces, trimmed and ready (without the sticker edge).
    func sticker(for character: LibraryCharacter) -> Sticker? {
        guard let strip = StickerArt.loadImage(at: character.imageURL) else { return nil }
        let frames = StickerArt.splitStrip(strip, count: max(character.faces.count, 1))
        func frame(_ name: String) -> CGImage? {
            guard let index = character.faces.firstIndex(of: name), frames.indices.contains(index) else { return nil }
            return frames[index]
        }
        guard let open = frame("open") ?? frames.first else { return nil }
        return StickerArt.prepare(open, blink: frame("blink"), happy: frame("happy"))
    }

    /// A small picture of the character for lists and grids.
    func thumbnail(for character: LibraryCharacter) -> NSImage? {
        if let cached = thumbnails[character.id] {
            return cached
        }
        guard let strip = StickerArt.loadImage(at: character.imageURL),
              let open = StickerArt.splitStrip(strip, count: max(character.faces.count, 1)).first
        else { return nil }
        let image = StickerArt.nsImage(StickerArt.scaled(open, maxSide: 180))
        thumbnails[character.id] = image
        return image
    }
}

/// The format of Library.json.
private struct LibraryManifest: Decodable {
    struct Category: Decodable {
        let id: String
        let name: String
        let symbol: String?
    }

    struct Entry: Decodable {
        let id: String
        let name: String
        let category: String
        let image: String
        let faces: [String]?
    }

    let categories: [Category]?
    let characters: [Entry]
}

/// Which character is on the notch, and loading any character by its ID.
/// IDs look like "builtin:cat" (library), "pack:<pack>/<id>" (packs) or
/// "sticker:<id>" (your own stickers).
@MainActor
enum Characters {
    static var currentID: String {
        UserDefaults.standard.string(forKey: Preferences.Key.characterID) ?? Preferences.Default.characterID
    }

    /// Makes a character the one on the notch (it's remembered as your default).
    static func select(_ id: String) {
        UserDefaults.standard.set(id, forKey: Preferences.Key.characterID)
    }

    static func isSticker(_ id: String) -> Bool {
        id.hasPrefix("sticker:")
    }

    static func exists(_ id: String) -> Bool {
        if isSticker(id) {
            return StickerStore.shared.sticker(withID: String(id.dropFirst("sticker:".count))) != nil
        }
        return CharacterLibrary.shared.character(withID: id) != nil
    }

    static func displayName(for id: String) -> String {
        if isSticker(id) {
            return StickerStore.shared.sticker(withID: String(id.dropFirst("sticker:".count)))?.name ?? "My Sticker"
        }
        return CharacterLibrary.shared.character(withID: id)?.name ?? "Spider"
    }

    /// The character's picture(s), ready for the notch, with the chosen sticker edge.
    /// Falls back to the spider if the character is missing.
    static func loadSticker(id: String, border: BorderStyle) -> Sticker {
        if let sticker = rawSticker(id: id) {
            return StickerBorder.apply(border, to: sticker)
        }
        if let spider = rawSticker(id: Preferences.Default.characterID) {
            return StickerBorder.apply(border, to: spider)
        }
        return StickerBorder.apply(border, to: StickerArt.emergencySticker())
    }

    private static func rawSticker(id: String) -> Sticker? {
        if isSticker(id) {
            return StickerStore.shared.loadSticker(id: String(id.dropFirst("sticker:".count)))
        }
        guard let character = CharacterLibrary.shared.character(withID: id) else { return nil }
        return CharacterLibrary.shared.sticker(for: character)
    }

    static func thumbnail(for id: String) -> NSImage? {
        if isSticker(id) {
            return StickerStore.shared.thumbnail(id: String(id.dropFirst("sticker:".count)))
        }
        guard let character = CharacterLibrary.shared.character(withID: id) else { return nil }
        return CharacterLibrary.shared.thumbnail(for: character)
    }
}
