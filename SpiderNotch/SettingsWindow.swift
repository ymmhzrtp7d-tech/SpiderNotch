//
//  SettingsWindow.swift
//  SpiderNotch
//
//  The Settings window: a sidebar with Characters (the animal library),
//  My Stickers, Appearance, Now Playing, General, Updates and About.
//
//  Note: this code deliberately doesn't use SwiftUI's @State. On macOS 27,
//  @State is a "macro" that needs a plugin that only comes with the full
//  Xcode app, and SpiderNotch is built with just the Command Line Tools.
//  Saved settings use @AppStorage, and everything else lives in
//  SettingsModel (an ObservableObject, which works without macros).
//

import AppKit
import SwiftUI

/// Opens (and re-opens) the Settings window.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsRootView>?
    let model = SettingsModel()

    /// Opens Settings, optionally at a section ("library", "stickers", "appearance", "nowPlaying", "general", "updates", "about").
    func show(section: String? = nil) {
        if let section = section {
            UserDefaults.standard.set(section, forKey: Preferences.Key.settingsSection)
        }
        // Make the "Launch at login" switch match what macOS really has.
        UserDefaults.standard.set(LoginItem.isEnabled, forKey: Preferences.Key.launchAtLogin)
        model.reload()

        if window == nil {
            let newHosting = NSHostingController(rootView: SettingsRootView(model: model))
            let newWindow = NSWindow(contentViewController: newHosting)
            newWindow.title = "SpiderNotch Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 900, height: 640))
            newWindow.center()
            hosting = newHosting
            window = newWindow
            model.presenter = newHosting
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Everything the Settings window shows that isn't a saved setting.
@MainActor
final class SettingsModel: ObservableObject {
    /// The character on the notch right now.
    @Published private(set) var currentID: String = Characters.currentID
    /// The character being previewed in the library (before you pick it).
    @Published var libraryPreviewID: String?
    /// The sticker being previewed in My Stickers.
    @Published var stickerPreviewID: String?
    @Published private(set) var stickers: [MySticker] = []
    /// Bumped when sticker pictures change, so thumbnails refresh.
    @Published private(set) var stickerVersion = 0
    @Published private(set) var media = MediaStatusReport()

    /// Used to show the Photos picker as a sheet on the Settings window.
    weak var presenter: NSViewController?

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.characterMayHaveChanged()
            }
        }
        center.addObserver(forName: .spiderNotchStickersChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadStickers()
            }
        }
        center.addObserver(forName: .spiderNotchMediaChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshMedia()
            }
        }
        reloadStickers()
    }

    func reload() {
        CharacterLibrary.shared.reload()
        reloadStickers()
        characterMayHaveChanged()
        refreshMedia(force: true)
    }

    private func reloadStickers() {
        stickers = StickerStore.shared.stickers
        stickerVersion += 1
        if let shown = stickerPreviewID, StickerStore.shared.sticker(withID: shown) == nil {
            stickerPreviewID = nil
        }
    }

    private func characterMayHaveChanged() {
        let id = Characters.currentID
        if id != currentID {
            currentID = id
        }
    }

    private var lastMediaRefresh = Date.distantPast

    /// Updates the Now Playing status (at most every 2 seconds unless `force`).
    func refreshMedia(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastMediaRefresh) > 2 else { return }
        lastMediaRefresh = Date()
        media = MediaCenter.shared.statusReport()
    }

    // MARK: - Characters

    func isCurrent(_ id: String) -> Bool {
        id == currentID
    }

    /// Puts a character on the notch (and keeps it as your default).
    func use(_ id: String) {
        Characters.select(id)
        currentID = id
    }

    /// Drops a character at the real notch for a few seconds, without picking it.
    func tryOnNotch(_ id: String) {
        NotificationCenter.default.post(name: .spiderNotchDemo, object: id)
    }

    /// The library character shown in the big preview.
    var libraryShownID: String {
        if let id = libraryPreviewID, CharacterLibrary.shared.character(withID: id) != nil {
            return id
        }
        if !Characters.isSticker(currentID), CharacterLibrary.shared.character(withID: currentID) != nil {
            return currentID
        }
        return Preferences.Default.characterID
    }

    /// The sticker shown in the big preview in My Stickers (nil if you have none).
    var stickerShown: MySticker? {
        if let id = stickerPreviewID, let sticker = StickerStore.shared.sticker(withID: id) {
            return sticker
        }
        if Characters.isSticker(currentID),
           let sticker = StickerStore.shared.sticker(withID: String(currentID.dropFirst("sticker:".count))) {
            return sticker
        }
        return stickers.last
    }

    // MARK: - Making stickers

    enum PhotoSource {
        case photos, desktop, downloads, anywhere
    }

    func newSticker(from source: PhotoSource) {
        let open: PhotoImporter.Completion = { [weak self] image, _ in
            guard let image = image else {
                Alerts.show(title: "Couldn't open that picture", message: StickerError.unreadable.localizedDescription)
                return
            }
            self?.openEditor(with: image)
        }
        switch source {
        case .photos:
            PhotoImporter.shared.pickFromPhotos(presentingFrom: presenter, completion: open)
        case .desktop:
            PhotoImporter.shared.chooseFile(in: .desktop, completion: open)
        case .downloads:
            PhotoImporter.shared.chooseFile(in: .downloads, completion: open)
        case .anywhere:
            PhotoImporter.shared.chooseFile(in: .anywhere, completion: open)
        }
    }

    /// A photo was dropped onto My Stickers.
    func newSticker(fromDropped providers: [NSItemProvider]) -> Bool {
        PhotoImporter.loadImage(from: providers) { [weak self] image, _ in
            guard let image = image else {
                Alerts.show(title: "Couldn't open that picture", message: StickerError.unreadable.localizedDescription)
                return
            }
            self?.openEditor(with: image)
        }
    }

    func openEditor(with image: CGImage) {
        let editor = PhotoEditorModel.forNewPhoto(image, name: StickerStore.shared.uniqueName("My Sticker"))
        PhotoEditorWindowController.show(model: editor) { [weak self] saved in
            // Your new sticker goes straight onto the notch, and says hi.
            self?.stickerPreviewID = saved.id
            self?.use(saved.characterID)
            NotificationCenter.default.post(name: .spiderNotchDemo, object: nil)
        }
    }

    func edit(_ sticker: MySticker) {
        guard sticker.kind == .photo, let photo = StickerStore.shared.sourcePhoto(for: sticker) else {
            Alerts.show(title: "This one can't be edited",
                        message: "“\(sticker.name)” was added as a ready-made picture, so there's no photo to crop. You can rename it, delete it, or make a new sticker from a photo.")
            return
        }
        let editor = PhotoEditorModel(photo: photo, name: sticker.name, edit: sticker.edit ?? PhotoStickerEdit(),
                                      existingID: sticker.id)
        PhotoEditorWindowController.show(model: editor) { [weak self] saved in
            self?.stickerPreviewID = saved.id
        }
    }

    func addReadyMadePicture() {
        guard let url = PhotoImporter.shared.choosePictureFile() else { return }
        do {
            let sticker = try StickerStore.shared.addPicture(from: url)
            stickerPreviewID = sticker.id
            use(sticker.characterID)
        } catch {
            Alerts.show(title: "Couldn't use that picture", message: error.localizedDescription)
        }
    }

    func rename(_ sticker: MySticker) {
        guard let name = Alerts.askForText(title: "Rename Sticker", message: "Give “\(sticker.name)” a new name.",
                                           initial: sticker.name, button: "Rename")
        else { return }
        StickerStore.shared.rename(sticker.id, to: name)
    }

    func delete(_ sticker: MySticker) {
        guard Alerts.confirm(title: "Delete “\(sticker.name)”?",
                             message: "The sticker and its photo are removed from this Mac. This can't be undone.",
                             button: "Delete")
        else { return }
        if stickerPreviewID == sticker.id {
            stickerPreviewID = nil
        }
        StickerStore.shared.delete(sticker.id)
    }
}

// MARK: - The window's layout

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Preferences.Key.settingsSection) private var section = "library"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
                .frame(maxHeight: .infinity)
                .background(Color.primary.opacity(0.035))
            Divider()
            Group {
                switch section {
                case "stickers":
                    StickersSection(model: model)
                case "appearance":
                    AppearanceSection(model: model)
                case "nowPlaying":
                    NowPlayingSection(model: model)
                case "general":
                    GeneralSection(model: model)
                case "updates":
                    UpdatesSection()
                case "about":
                    AboutSection()
                default:
                    LibrarySection(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 900, height: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SpiderNotch").font(.headline)
                    Text("Version \(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
            SidebarButton(title: "Characters", symbol: "pawprint.fill", id: "library", selection: $section)
            SidebarButton(title: "My Stickers", symbol: "face.smiling", id: "stickers", selection: $section)
            SidebarButton(title: "Appearance", symbol: "paintbrush.pointed.fill", id: "appearance", selection: $section)
            SidebarButton(title: "Now Playing", symbol: "music.note", id: "nowPlaying", selection: $section)
            SidebarButton(title: "General", symbol: "gearshape.fill", id: "general", selection: $section)
            SidebarButton(title: "Updates", symbol: "arrow.triangle.2.circlepath", id: "updates", selection: $section)
            SidebarButton(title: "About", symbol: "info.circle.fill", id: "about", selection: $section)
            Spacer()
            Text("Hover over the notch to say hi.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}

struct SidebarButton: View {
    let title: String
    let symbol: String
    let id: String
    @Binding var selection: String

    var body: some View {
        let selected = selection == id
        return Button {
            selection = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(title)
                    .fontWeight(selected ? .semibold : .regular)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The title at the top of each section.
struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

// MARK: - General

struct GeneralSection: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Preferences.Key.enabled) private var enabled = Preferences.Default.enabled
    @AppStorage(Preferences.Key.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Preferences.Key.virtualNotch) private var virtualNotch = Preferences.Default.virtualNotch

    var body: some View {
        Form {
            Section {
                SectionHeader(title: "General", subtitle: "SpiderNotch lives in your menu bar and waits at the notch.")
                    .padding(.vertical, 4)
            }
            Section {
                Toggle("Enable SpiderNotch", isOn: $enabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show on screens without a notch", isOn: $virtualNotch)
            }
            Section {
                HStack {
                    Text("Test the character at your notch")
                    Spacer()
                    Button("Test Drop") { model.tryOnNotch(model.currentID) }
                }
            }
            Section("About") {
                Text("SpiderNotch \(AppInfo.version). Your stickers and photos are saved only on this Mac, in ~/Library/Application Support/SpiderNotch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pop-up messages

@MainActor
enum Alerts {
    static func show(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Asks a yes/no question. Returns true for `button`.
    static func confirm(title: String, message: String, button: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Asks for a bit of text. Returns nil if you cancel.
    static func askForText(title: String, message: String, initial: String, button: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
