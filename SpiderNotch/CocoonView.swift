//
//  CocoonView.swift
//  SpiderNotch
//
//  The Cocoon inside the island: a row of file tiles (pinned first, then
//  recent), a header with filters and search, an action bar for the selected
//  files, and big drop zones (AirDrop · Keep · Pin) while you drag files in.
//
//  No @State here on purpose (see SettingsWindow.swift): all UI state lives in
//  CocoonModel, an ObservableObject.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum CocoonMetrics {
    /// Same height as Now Playing, so the island can switch between them
    /// without the character hanging below having to move.
    static let contentSize = CGSize(width: 600, height: 142)
    static let tileWidth: CGFloat = 78
    static let thumbSide: CGFloat = 46
}

enum CocoonFilter: String, CaseIterable {
    case all, pinned, recent, downloads

    var title: String {
        switch self {
        case .all: return "All"
        case .pinned: return "Pinned"
        case .recent: return "Recent"
        case .downloads: return "Downloads"
        }
    }
}

enum CocoonDropZone {
    case airDrop, keep, pin
}

/// Everything the Cocoon view shows that isn't saved.
@MainActor
final class CocoonModel: ObservableObject {
    static let shared = CocoonModel()

    @Published var filter: CocoonFilter = .all
    @Published var search = ""
    @Published var selection: Set<UUID> = []
    @Published var hoveredID: UUID?
    /// Files are being dragged over the island: show the drop zones.
    @Published var isDraggingFiles = false
    @Published var targetedZone: CocoonDropZone?
    /// The pin button in the header: stay open until you close it.
    @Published var pinnedOpen = false
    @Published private(set) var downloads: [CocoonItem] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    /// Just dropped in: these tiles pop in with a little animation.
    @Published private(set) var justAdded: Set<UUID> = []
    /// A tile you're dragging (to rearrange, or out to another app).
    var draggingID: UUID?
    /// You clicked inside: stay open a little longer when the mouse leaves.
    var engaged = false
    /// Opened from the menu: stays until you click outside or press Esc.
    var stayUntilClickOutside = false

    let store = CocoonStore.shared
    private var downloadIDs: [String: UUID] = [:]
    private var cancellable: AnyCancellable?

    init() {
        // Re-publish store changes so the view refreshes.
        cancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Called every time the Cocoon opens.
    func willAppear() {
        store.refresh()
        refreshDownloads()
        selection = selection.filter { id in store.item(withID: id) != nil || downloads.contains { $0.id == id } }
        if filter == .downloads && !RecentDownloads.isEnabled { filter = .all }
    }

    func didDisappear() {
        engaged = false
        stayUntilClickOutside = false
        isDraggingFiles = false
        targetedZone = nil
        hoveredID = nil
        draggingID = nil
    }

    func refreshDownloads() {
        guard RecentDownloads.isEnabled else {
            downloads = []
            return
        }
        downloads = RecentDownloads.newest().map { url in
            let id = downloadIDs[url.path] ?? UUID()
            downloadIDs[url.path] = id
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return CocoonItem(id: id, bookmark: nil, path: url.path,
                              name: FileManager.default.displayName(atPath: url.path),
                              isDirectory: isDirectory.boolValue, addedAt: Date(), pinned: false)
        }
    }

    // MARK: - What's shown

    var showsDownloadsFilter: Bool { RecentDownloads.isEnabled }
    var showsSearch: Bool { store.items.count > 6 || !search.isEmpty }

    private func matches(_ item: CocoonItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
    }

    var pinnedShown: [CocoonItem] {
        (filter == .all || filter == .pinned) ? store.pinned.filter(matches) : []
    }

    var recentShown: [CocoonItem] {
        (filter == .all || filter == .recent) ? store.recent.filter(matches) : []
    }

    var downloadsShown: [CocoonItem] {
        filter == .downloads ? downloads.filter(matches) : []
    }

    var nothingShown: Bool {
        pinnedShown.isEmpty && recentShown.isEmpty && downloadsShown.isEmpty
    }

    func isMissing(_ item: CocoonItem) -> Bool {
        store.missing.contains(item.id)
    }

    func isStored(_ id: UUID) -> Bool {
        store.item(withID: id) != nil
    }

    /// The selected items, in the order they're shown.
    var selectedItems: [CocoonItem] {
        (store.items + downloads).filter { selection.contains($0.id) }
    }

    var selectionIsPinned: Bool {
        let items = selectedItems
        return !items.isEmpty && items.allSatisfy { $0.pinned }
    }

    // MARK: - Clicking tiles

    func click(_ item: CocoonItem, extend: Bool) {
        engaged = true
        if extend {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        } else {
            selection = selection == [item.id] ? [] : [item.id]
        }
    }

    func thumbnail(for item: CocoonItem) -> NSImage {
        if let image = thumbnails[item.id] { return image }
        return CocoonActions.icon(for: item)
    }

    func loadThumbnail(for item: CocoonItem) {
        guard thumbnails[item.id] == nil, !item.isDirectory else { return }
        CocoonActions.loadThumbnail(for: item, side: CocoonMetrics.thumbSide * 2) { [weak self] image in
            self?.thumbnails[item.id] = image
        }
    }

    // MARK: - Actions on the selection

    func airDrop() { CocoonActions.airDrop(selectedItems) }

    /// AirDrop works even with nothing selected: you pick the files first.
    func airDropAnything() {
        engaged = true
        if !selection.isEmpty {
            airDrop()
            return
        }
        CocoonActions.chooseFiles(prompt: "AirDrop", message: "Choose files to send with AirDrop.") { urls in
            CocoonActions.airDrop(urls: urls)
        }
    }

    /// "Add Files…": pick files with the standard Open window and keep them here.
    func addFilesFromPanel() {
        engaged = true
        CocoonActions.chooseFiles(prompt: "Add", message: "Choose files to keep handy in the Cocoon.") { [weak self] urls in
            self?.finishDrop(urls, into: .keep)
        }
    }

    func openSettings() {
        NotificationCenter.default.post(name: .spiderNotchOpenSettings, object: "cocoon")
    }
    func open() { CocoonActions.open(selectedItems) }
    func quickLook() { CocoonActions.quickLook(selectedItems) }
    func reveal() { CocoonActions.reveal(selectedItems) }
    func copy() { CocoonActions.copy(selectedItems) }

    func togglePin() {
        let items = selectedItems
        let pin = !selectionIsPinned
        let stored = Set(items.filter { isStored($0.id) }.map { $0.id })
        store.setPinned(stored, pin)
        // Downloads aren't in the Cocoon yet: pinning adds them.
        let fromDownloads = items.filter { !isStored($0.id) }.map { $0.url }
        if pin && !fromDownloads.isEmpty {
            let added = store.add(fromDownloads, pin: true)
            selection.subtract(items.filter { !isStored($0.id) }.map { $0.id })
            selection.formUnion(added)
        }
    }

    /// Takes the selected files out of the Cocoon (never deletes them).
    func remove() {
        store.remove(selection)
        selection.removeAll()
    }

    func clearRecent() {
        let recentIDs = Set(store.recent.map { $0.id })
        store.clearRecent()
        selection.subtract(recentIDs)
    }

    // MARK: - Dropping files in

    func drop(_ providers: [NSItemProvider], into zone: CocoonDropZone) -> Bool {
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !fileProviders.isEmpty else { return false }
        engaged = true
        let group = DispatchGroup()
        let collected = URLCollector()
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.isFileURL { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.finishDrop(collected.urls, into: zone)
            }
        }
        return true
    }

    private func finishDrop(_ urls: [URL], into zone: CocoonDropZone) {
        isDraggingFiles = false
        targetedZone = nil
        guard !urls.isEmpty else { return }
        switch zone {
        case .airDrop:
            CocoonActions.airDrop(urls: urls)
        case .keep, .pin:
            let ids = store.add(urls, pin: zone == .pin)
            if filter == .downloads || (zone == .pin && filter == .recent) || (zone == .keep && filter == .pinned) {
                filter = .all
            }
            search = ""
            selection = Set(ids)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) {
                justAdded = Set(ids)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.justAdded = []
                }
            }
        }
    }

    /// A tile was dragged onto another tile: rearrange.
    func moveDragged(onto target: CocoonItem) {
        guard let id = draggingID, id != target.id, isStored(id), isStored(target.id) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            store.move(id, to: target.id)
        }
    }
}

/// Collects URLs from several background callbacks.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URL] = []
    func append(_ url: URL) { lock.lock(); list.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return list }
}

// MARK: - The view

struct CocoonView: View {
    @ObservedObject var model: CocoonModel

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                header
                    .frame(height: 22)
                tiles
                    .frame(height: 82)
                actionBar
                    .frame(height: 26)
            }
            .opacity(model.isDraggingFiles ? 0 : 1)

            if model.isDraggingFiles {
                dropZones
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.isDraggingFiles)
        .frame(width: CocoonMetrics.contentSize.width, height: CocoonMetrics.contentSize.height)
        // Files dropped anywhere on the Cocoon are kept (as recent files).
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            model.draggingID == nil ? model.drop(providers, into: .keep) : false
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(CocoonStyle.silk)
            Text("Cocoon")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                ForEach(CocoonFilter.allCases.filter { $0 != .downloads || model.showsDownloadsFilter }, id: \.self) { item in
                    FilterChip(title: item.title, selected: model.filter == item) {
                        model.engaged = true
                        model.filter = item
                        if item == .downloads { model.refreshDownloads() }
                    }
                }
            }
            Spacer(minLength: 4)
            if model.showsSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                    TextField("Search", text: Binding(get: { model.search }, set: { model.search = $0; model.engaged = true }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 90)
                }
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .foregroundStyle(.white.opacity(0.8))
            }
            if !model.store.recent.isEmpty && (model.filter == .all || model.filter == .recent) {
                HeaderButton(symbol: "sparkles", help: "Clear Recent (pinned files stay; nothing is deleted)") {
                    model.clearRecent()
                }
            }
            HeaderButton(symbol: "plus", help: "Add Files… (or drag them onto the notch)") {
                model.addFilesFromPanel()
            }
            HeaderButton(symbol: "dot.radiowaves.left.and.right", help: "AirDrop… (the selected files, or choose some)") {
                model.airDropAnything()
            }
            HeaderButton(symbol: "gearshape", help: "Cocoon Settings") {
                model.openSettings()
            }
            HeaderButton(symbol: model.pinnedOpen ? "pin.fill" : "pin",
                         help: model.pinnedOpen ? "Let the island close by itself again" : "Keep the island open",
                         active: model.pinnedOpen) {
                model.pinnedOpen.toggle()
                model.engaged = true
            }
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        Group {
            if model.nothingShown {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(model.pinnedShown) { item in tile(item) }
                        if !model.pinnedShown.isEmpty && !model.recentShown.isEmpty {
                            GroupDivider(title: "Recent")
                        }
                        ForEach(model.recentShown) { item in tile(item) }
                        ForEach(model.downloadsShown) { item in tile(item) }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func tile(_ item: CocoonItem) -> some View {
        CocoonTile(item: item,
                   image: model.thumbnail(for: item),
                   selected: model.selection.contains(item.id),
                   hovered: model.hoveredID == item.id,
                   missing: model.isMissing(item),
                   isNew: model.justAdded.contains(item.id),
                   isDownload: !model.isStored(item.id))
            .onAppear { model.loadThumbnail(for: item) }
            .onHover { inside in
                if inside {
                    model.hoveredID = item.id
                } else if model.hoveredID == item.id {
                    model.hoveredID = nil
                }
            }
            .onTapGesture(count: 2) {
                model.selection = [item.id]
                model.open()
            }
            .simultaneousGesture(TapGesture().modifiers(.command).onEnded { model.click(item, extend: true) })
            .simultaneousGesture(TapGesture().modifiers(.shift).onEnded { model.click(item, extend: true) })
            .onTapGesture { model.click(item, extend: false) }
            // Drag a tile out to Finder, Mail, a chat… or onto another tile to rearrange.
            .onDrag {
                model.draggingID = item.id
                return NSItemProvider(object: item.url as NSURL)
            }
            .onDrop(of: [UTType.fileURL], delegate: ReorderDropDelegate(target: item, model: model))
            .contextMenu {
                Button("Open") { model.selection = [item.id]; model.open() }
                Button("Quick Look") { model.selection = [item.id]; model.quickLook() }
                Button("Share with AirDrop") { model.selection = [item.id]; model.airDrop() }
                Divider()
                Button(item.pinned ? "Unpin" : "Pin") { model.selection = [item.id]; model.togglePin() }
                Button("Show in Finder") { model.selection = [item.id]; model.reveal() }
                Button("Copy") { model.selection = [item.id]; model.copy() }
                if model.isStored(item.id) {
                    Divider()
                    Button("Remove from Cocoon") { model.selection = [item.id]; model.remove() }
                }
            }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(CocoonStyle.silk)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.search.isEmpty ? (model.filter == .downloads ? "No recent downloads" : "Drop files here to keep them handy")
                                          : "Nothing matches “\(model.search)”")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Drag files from Finder onto the notch. They stay where they are: the Cocoon only keeps a link.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if model.search.isEmpty && model.filter != .downloads {
                    HStack(spacing: 6) {
                        ActionButton(symbol: "plus", title: "Add Files…", prominent: true) { model.addFilesFromPanel() }
                        ActionButton(symbol: "dot.radiowaves.left.and.right", title: "AirDrop…") { model.airDropAnything() }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 4) {
            if model.selection.isEmpty {
                Text(model.store.isEmpty ? "Tip: drop on “Pin” to keep a file here for good."
                                         : "Click a file for actions · double-click to open · drag it out to use it")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !model.nothingShown {
                    ActionButton(symbol: "plus", title: "Add Files…") { model.addFilesFromPanel() }
                    ActionButton(symbol: "dot.radiowaves.left.and.right", title: "AirDrop…") { model.airDropAnything() }
                }
            } else {
                let items = model.selectedItems
                Text(items.count == 1 ? items[0].name : "\(items.count) files")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 130, alignment: .leading)
                Spacer(minLength: 4)
                ActionButton(symbol: "dot.radiowaves.left.and.right", title: "AirDrop", prominent: true) { model.airDrop() }
                ActionButton(symbol: "arrow.up.forward.app", title: "Open") { model.open() }
                ActionButton(symbol: "eye", title: "Preview") { model.quickLook() }
                ActionButton(symbol: model.selectionIsPinned ? "pin.slash" : "pin",
                             title: model.selectionIsPinned ? "Unpin" : "Pin") { model.togglePin() }
                ActionButton(symbol: "folder", title: "Reveal") { model.reveal() }
                ActionButton(symbol: "doc.on.doc", title: "Copy") { model.copy() }
                if items.contains(where: { model.isStored($0.id) }) {
                    ActionButton(symbol: "xmark.circle", title: "Remove") { model.remove() }
                }
            }
        }
    }

    // MARK: Drop zones

    private var dropZones: some View {
        HStack(spacing: 10) {
            DropZoneView(title: "AirDrop", subtitle: "Send to a nearby device", symbol: "dot.radiowaves.left.and.right",
                         zone: .airDrop, model: model)
            DropZoneView(title: "Keep", subtitle: "Add to Recent", symbol: "tray.and.arrow.down.fill",
                         zone: .keep, model: model)
            DropZoneView(title: "Pin", subtitle: "Keep it here for good", symbol: "pin.fill",
                         zone: .pin, model: model)
        }
        .padding(.top, 4)
    }
}

// MARK: - Pieces

enum CocoonStyle {
    /// The Cocoon's own colour: soft silk lilac.
    static let silk = Color(red: 0.78, green: 0.70, blue: 1.0)
    static let tileFill = Color.white.opacity(0.06)
}

struct CocoonTile: View {
    let item: CocoonItem
    let image: NSImage
    let selected: Bool
    let hovered: Bool
    let missing: Bool
    let isNew: Bool
    let isDownload: Bool

    var body: some View {
        let kind = CocoonKind.of(item.url, isDirectory: item.isDirectory)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: CocoonMetrics.thumbSide, height: CocoonMetrics.thumbSide)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .saturation(missing ? 0 : 1)
                    .opacity(missing ? 0.4 : 1)
                if missing {
                    Badge(symbol: "exclamationmark", color: .orange)
                } else if item.pinned {
                    Badge(symbol: "pin.fill", color: CocoonStyle.silk)
                } else if isDownload {
                    Badge(symbol: "arrow.down", color: .blue)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .offset(x: -3, y: 3)
                    .help(kind.label)
            }
            Text(missing ? "Missing: \(item.name)" : item.name)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(missing ? 0.45 : 0.9))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: CocoonMetrics.tileWidth - 6, height: 26, alignment: .top)
        }
        .frame(width: CocoonMetrics.tileWidth, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? CocoonStyle.silk.opacity(0.28) : (hovered ? Color.white.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? CocoonStyle.silk.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isNew ? 1.08 : (hovered ? 1.03 : 1))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .contentShape(Rectangle())
        .help(missing ? "\(item.name) can't be found. It may have been moved to the Trash or deleted." : item.path)
    }
}

private struct Badge: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 15, height: 15)
            .background(Circle().fill(color))
            .offset(x: 4, y: -4)
    }
}

private struct GroupDivider: View {
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 44)
            Text(title)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 10, height: 30)
        }
        .padding(.horizontal, 4)
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.75))
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(selected ? CocoonStyle.silk : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.75))
                .frame(width: 22, height: 20)
                .background(Capsule().fill(active ? CocoonStyle.silk : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ActionButton: View {
    let symbol: String
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.9))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(prominent ? CocoonStyle.silk : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct DropZoneView: View {
    let title: String
    let subtitle: String
    let symbol: String
    let zone: CocoonDropZone
    @ObservedObject var model: CocoonModel

    var body: some View {
        let targeted = model.targetedZone == zone
        return VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(subtitle).font(.system(size: 10)).opacity(0.7)
        }
        .foregroundStyle(targeted ? Color.black : Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(targeted ? CocoonStyle.silk : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: targeted ? [] : [5, 4]))
                .foregroundStyle(targeted ? Color.clear : Color.white.opacity(0.35))
        )
        .scaleEffect(targeted ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(
            get: { model.targetedZone == zone },
            set: { inside in
                if inside {
                    model.targetedZone = zone
                } else if model.targetedZone == zone {
                    model.targetedZone = nil
                }
            })) { providers in
            model.drop(providers, into: zone)
        }
    }
}

/// Dragging one tile onto another rearranges them (pinned with pinned, recent with recent).
private struct ReorderDropDelegate: DropDelegate {
    let target: CocoonItem
    let model: CocoonModel

    func validateDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { model.draggingID != nil }
    }

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated { model.moveDragged(onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { model.draggingID = nil }
        return true
    }
}
