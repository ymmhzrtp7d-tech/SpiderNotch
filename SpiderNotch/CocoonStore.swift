//
//  CocoonStore.swift
//  SpiderNotch
//
//  The Cocoon: files you keep handy in the island. This file is the data side:
//  what's in it, saving and loading, and finding files again after they move.
//
//  Important promises:
//    • The Cocoon only stores *references* (bookmarks) to your files. Adding,
//      removing, pinning or clearing never moves, copies or deletes an original.
//    • Pinned files stay until you unpin or remove them. Other ("recent") files
//      are temporary: they're cleared after a while (Settings → Cocoon) or with
//      Clear Recent.
//    • Saved in ~/Library/Application Support/SpiderNotch/Cocoon.json.
//
//  SpiderNotch isn't sandboxed, so plain bookmarks are enough to find a file
//  again after it's renamed or moved. Security-scoped bookmarks are used when
//  macOS allows them, so the same data keeps working if the app is ever sandboxed.
//

import AppKit
import Combine
import UniformTypeIdentifiers

/// One file or folder in the Cocoon.
struct CocoonItem: Codable, Identifiable, Equatable {
    let id: UUID
    var bookmark: Data?
    /// Where the file was last seen (used if the bookmark can't be resolved).
    var path: String
    var name: String
    var isDirectory: Bool
    var addedAt: Date
    var pinned: Bool

    var url: URL { URL(fileURLWithPath: path) }
}

/// What kind of file it is, for the little badge on each tile.
enum CocoonKind: String {
    case folder, pdf, image, video, audio, text, archive, app, other

    static func of(_ url: URL, isDirectory: Bool) -> CocoonKind {
        if url.pathExtension.lowercased() == "app" { return .app }
        if isDirectory { return .folder }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .text) || type.conforms(to: .content) { return .text }
        return .other
    }

    var label: String {
        switch self {
        case .folder: return "Folder"
        case .pdf: return "PDF"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .text: return "Document"
        case .archive: return "Archive"
        case .app: return "App"
        case .other: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .pdf: return "doc.richtext.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .text: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .app: return "app.fill"
        case .other: return "doc.fill"
        }
    }
}

@MainActor
final class CocoonStore: ObservableObject {
    static let shared = CocoonStore()

    /// Pinned files first (in your order), then recent files (newest first).
    @Published private(set) var items: [CocoonItem] = []
    /// IDs of files that can't be found any more (moved to the Trash, deleted, unplugged disk…).
    @Published private(set) var missing: Set<UUID> = []

    private let fileURL: URL
    private let now: () -> Date

    /// How long recent (unpinned) files stay, in seconds. 0 = until you clear them.
    var recentLifetime: TimeInterval {
        let hours = UserDefaults.standard.double(forKey: Preferences.Key.cocoonRecentHours)
        return hours > 0 ? hours * 3600 : 0
    }

    /// - Parameter folder: where Cocoon.json lives (tests pass a temporary folder).
    init(folder: URL = AppInfo.supportFolder, now: @escaping () -> Date = Date.init) {
        fileURL = folder.appendingPathComponent("Cocoon.json")
        self.now = now
        load()
    }

    var pinned: [CocoonItem] { items.filter { $0.pinned } }
    var recent: [CocoonItem] { items.filter { !$0.pinned } }
    var isEmpty: Bool { items.isEmpty }

    func item(withID id: UUID) -> CocoonItem? {
        items.first { $0.id == id }
    }

    // MARK: - Adding

    /// Adds files (or folders). Files already in the Cocoon move to the front,
    /// and are pinned if `pin` is true. Returns the IDs of the added items.
    @discardableResult
    func add(_ urls: [URL], pin: Bool = false) -> [UUID] {
        var added: [UUID] = []
        for raw in urls where raw.isFileURL {
            let url = raw.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if let index = items.firstIndex(where: { $0.path == url.path }) {
                var existing = items.remove(at: index)
                existing.addedAt = now()
                if pin { existing.pinned = true }
                insert(existing)
                added.append(existing.id)
                continue
            }
            let item = CocoonItem(id: UUID(),
                                  bookmark: CocoonStore.makeBookmark(for: url),
                                  path: url.path,
                                  name: FileManager.default.displayName(atPath: url.path),
                                  isDirectory: isDirectory.boolValue,
                                  addedAt: now(),
                                  pinned: pin)
            insert(item)
            added.append(item.id)
        }
        if !added.isEmpty { save() }
        return added
    }

    private func insert(_ item: CocoonItem) {
        if item.pinned {
            // New pins go to the end of the pinned row.
            let end = items.lastIndex(where: { $0.pinned }).map { $0 + 1 } ?? 0
            items.insert(item, at: end)
        } else {
            // Recent files: newest first, right after the pinned ones.
            let start = items.lastIndex(where: { $0.pinned }).map { $0 + 1 } ?? 0
            items.insert(item, at: start)
        }
    }

    // MARK: - Changing

    func setPinned(_ ids: Set<UUID>, _ pinned: Bool) {
        var changed = false
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].pinned != pinned else { continue }
            var item = items.remove(at: index)
            item.pinned = pinned
            if !pinned { item.addedAt = now() } // an unpinned file starts its "recent" time again
            insert(item)
            changed = true
        }
        if changed { save() }
    }

    /// Takes files out of the Cocoon. The original files are NOT touched.
    func remove(_ ids: Set<UUID>) {
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        missing.subtract(ids)
        if items.count != before { save() }
    }

    /// Takes all recent (unpinned) files out of the Cocoon. Originals are NOT touched.
    func clearRecent() {
        let ids = Set(recent.map { $0.id })
        remove(ids)
    }

    /// Moves `id` to where `target` is (drag to rearrange). Only within the same group.
    func move(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target }),
              items[from].pinned == items[to].pinned
        else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        save()
    }

    // MARK: - Finding files again

    /// Re-checks every file: follows moves and renames, notes missing ones,
    /// and lets old recent files expire. Cheap; called when the Cocoon opens.
    func refresh() {
        var changed = false
        let lifetime = recentLifetime
        if lifetime > 0 {
            let cutoff = now().addingTimeInterval(-lifetime)
            let before = items.count
            items.removeAll { !$0.pinned && $0.addedAt < cutoff }
            changed = changed || items.count != before
        }
        var nowMissing: Set<UUID> = []
        for index in items.indices {
            let (resolved, staleBookmark) = CocoonStore.resolve(items[index])
            guard let url = resolved else {
                nowMissing.insert(items[index].id)
                continue
            }
            if url.path != items[index].path {
                items[index].path = url.path
                items[index].name = FileManager.default.displayName(atPath: url.path)
                changed = true
            }
            if staleBookmark {
                items[index].bookmark = CocoonStore.makeBookmark(for: url)
                changed = true
            }
        }
        if nowMissing != missing { missing = nowMissing }
        if changed { save() }
    }

    /// The file's current location, or nil if it can't be found.
    func currentURL(for item: CocoonItem) -> URL? {
        CocoonStore.resolve(item).url
    }

    /// Follows the bookmark (moves/renames), falling back to the last known path.
    private static func resolve(_ item: CocoonItem) -> (url: URL?, stale: Bool) {
        if let data = item.bookmark {
            var stale = false
            for options in [URL.BookmarkResolutionOptions.withSecurityScope, []] {
                if let url = try? URL(resolvingBookmarkData: data, options: options.union(.withoutUI),
                                      relativeTo: nil, bookmarkDataIsStale: &stale),
                   FileManager.default.fileExists(atPath: url.path) {
                    // Files in the Trash count as gone.
                    if url.path.contains("/.Trash/") { return (nil, false) }
                    return (url.standardizedFileURL, stale)
                }
            }
        }
        if FileManager.default.fileExists(atPath: item.path) {
            return (item.url, item.bookmark == nil)
        }
        return (nil, false)
    }

    private static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    // MARK: - Saving

    private struct SavedFile: Codable {
        var version = 1
        var items: [CocoonItem]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let saved = try JSONDecoder().decode(SavedFile.self, from: data)
            items = saved.items.filter { $0.pinned } + saved.items.filter { !$0.pinned }
        } catch {
            // Keep a copy of a file we couldn't read rather than overwriting it.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("SpiderNotch: couldn't read Cocoon.json (\(error)); a copy was kept.")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SavedFile(items: items))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SpiderNotch: couldn't save the Cocoon: \(error)")
        }
    }
}

/// The newest files in your Downloads folder (only when you turn it on in Settings,
/// because macOS asks for permission to read Downloads).
enum RecentDownloads {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Preferences.Key.cocoonShowDownloads)
    }

    static func newest(limit: Int = 6, in folder: URL? = nil) -> [URL] {
        let downloads = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloads = downloads else { return [] }
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        else { return [] }
        func added(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
        }
        // Skip downloads that are still in progress.
        let finished = contents.filter { !["download", "crdownload", "part"].contains($0.pathExtension.lowercased()) }
        return Array(finished.sorted { added($0) > added($1) }.prefix(limit))
    }
}
