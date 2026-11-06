//
//  SettingsSections.swift
//  SpiderNotch
//
//  The sections of the Settings window: the animal library, your own
//  stickers, appearance, and Now Playing.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Characters (the animal library)

struct LibrarySection: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Preferences.Key.libraryCategory) private var category = "all"

    var body: some View {
        let library = CharacterLibrary.shared
        let shownID = model.libraryShownID
        let shown = library.character(withID: shownID)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Characters",
                          subtitle: "\(library.characters.count) cute friends to live in your notch. Click one to preview it.")

            HStack(alignment: .center, spacing: 18) {
                CharacterPreview(characterID: shownID, settings: SpiderSettings.current())
                    .frame(width: 330, height: 168)
                VStack(alignment: .leading, spacing: 10) {
                    Text(shown?.name ?? "Spider").font(.title3.weight(.semibold))
                    if let shown = shown, let category = library.categories.first(where: { $0.id == shown.categoryID }) {
                        Label(category.name, systemImage: category.symbol)
                            .foregroundStyle(.secondary)
                    }
                    if model.isCurrent(shownID) {
                        Label("On your notch", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Button("Use This Character") { model.use(shownID) }
                            .keyboardShortcut(.defaultAction)
                    }
                    Button("Try on Notch") { model.tryOnNotch(shownID) }
                    Text("Hover the preview to bump it, click to make it hop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(title: "All", symbol: "square.grid.2x2.fill", selected: category == "all") {
                        category = "all"
                    }
                    ForEach(library.categories) { item in
                        CategoryChip(title: item.name, symbol: item.symbol, selected: category == item.id) {
                            category = item.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 10)], spacing: 10) {
                    ForEach(library.characters(in: category)) { character in
                        CharacterTile(image: library.thumbnail(for: character),
                                      name: character.name,
                                      isCurrent: model.isCurrent(character.id),
                                      isShown: character.id == shownID)
                            .onTapGesture(count: 2) { model.use(character.id) }
                            .onTapGesture { model.libraryPreviewID = character.id }
                            .contextMenu {
                                Button("Use This Character") { model.use(character.id) }
                                Button("Try on Notch") { model.tryOnNotch(character.id) }
                            }
                    }
                }
                .padding(4)
            }
        }
        .padding(22)
    }
}

struct CategoryChip: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// One character in a grid: its picture and name, a ring when it's on the notch.
struct CharacterTile: View {
    let image: NSImage?
    let name: String
    let isCurrent: Bool
    let isShown: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isShown ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .background(Circle().fill(Color.white).padding(2))
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - My Stickers

struct StickersSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let shown = model.stickerShown
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "My Stickers",
                          subtitle: "Turn a photo into a round, bouncy sticker. Your photos stay on this Mac.")

            if let sticker = shown {
                HStack(alignment: .center, spacing: 18) {
                    CharacterPreview(characterID: sticker.characterID, settings: SpiderSettings.current())
                        .id("\(sticker.characterID)#\(model.stickerVersion)")
                        .frame(width: 330, height: 168)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(sticker.name).font(.title3.weight(.semibold))
                        Text(sticker.kind == .photo ? "Made from a photo" : "Ready-made picture")
                            .foregroundStyle(.secondary)
                        if model.isCurrent(sticker.characterID) {
                            Label("On your notch (your default)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Button("Use as My Character") { model.use(sticker.characterID) }
                                .keyboardShortcut(.defaultAction)
                        }
                        HStack {
                            Button("Edit…") { model.edit(sticker) }
                                .disabled(sticker.kind != .photo)
                            Button("Rename…") { model.rename(sticker) }
                            Button("Delete…") { model.delete(sticker) }
                        }
                        Button("Try on Notch") { model.tryOnNotch(sticker.characterID) }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                emptyState
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 10)], spacing: 10) {
                    newStickerTile
                    ForEach(model.stickers) { sticker in
                        CharacterTile(image: StickerStore.shared.thumbnail(id: sticker.id),
                                      name: sticker.name,
                                      isCurrent: model.isCurrent(sticker.characterID),
                                      isShown: sticker.id == shown?.id)
                            .id("\(sticker.id)#\(model.stickerVersion)")
                            .onTapGesture(count: 2) { model.use(sticker.characterID) }
                            .onTapGesture { model.stickerPreviewID = sticker.id }
                            .contextMenu {
                                Button("Use as My Character") { model.use(sticker.characterID) }
                                Button("Try on Notch") { model.tryOnNotch(sticker.characterID) }
                                Divider()
                                Button("Edit…") { model.edit(sticker) }
                                    .disabled(sticker.kind != .photo)
                                Button("Rename…") { model.rename(sticker) }
                                Button("Delete…") { model.delete(sticker) }
                            }
                    }
                }
                .padding(4)
            }
        }
        .padding(22)
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: nil) { providers in
            model.newSticker(fromDropped: providers)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("Make your first sticker").font(.title3.weight(.semibold))
                Text("Click New Sticker below and pick a photo from Photos, your Desktop, Downloads or anywhere else, or just drop a photo onto this window. You'll crop it into a round face, and it will bounce and swing at your notch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(Color.secondary.opacity(0.5)))
    }

    private var newStickerTile: some View {
        Menu {
            Button("From Photos Library…") { model.newSticker(from: .photos) }
            Button("From Desktop…") { model.newSticker(from: .desktop) }
            Button("From Downloads…") { model.newSticker(from: .downloads) }
            Button("Choose Any File…") { model.newSticker(from: .anywhere) }
            Divider()
            Button("Add a Ready-Made Picture (PNG)…") { model.addReadyMadePicture() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 62, height: 62)
                Text("New Sticker").font(.caption.weight(.semibold))
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Appearance

struct AppearanceSection: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Preferences.Key.stickerSize) private var stickerSize = Preferences.Default.stickerSize
    @AppStorage(Preferences.Key.animationSpeed) private var speed = Preferences.Default.animationSpeed
    @AppStorage(Preferences.Key.entrance) private var entrance = EntranceStyle.thread
    @AppStorage(Preferences.Key.floatAmount) private var floatAmount = Preferences.Default.floatAmount
    @AppStorage(Preferences.Key.swing) private var swing = Preferences.Default.swing
    @AppStorage(Preferences.Key.bounce) private var bounce = Preferences.Default.bounce
    @AppStorage(Preferences.Key.webLength) private var webLength = Preferences.Default.webLength
    @AppStorage(Preferences.Key.border) private var border = BorderStyle.white
    @AppStorage(Preferences.Key.position) private var position = StickerPosition.center

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    CharacterPreview(characterID: model.currentID, settings: SpiderSettings.current())
                        .frame(width: 330, height: 168)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Appearance").font(.title2.weight(.semibold))
                        Text("Changes apply to every character, straight away.")
                            .foregroundStyle(.secondary)
                        Button("Test on Notch") { model.tryOnNotch(model.currentID) }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Size and speed") {
                Slider(value: $stickerSize, in: 48...140) {
                    Text("Sticker size")
                } minimumValueLabel: {
                    Image(systemName: "circle.fill").font(.system(size: 7))
                } maximumValueLabel: {
                    Image(systemName: "circle.fill").font(.system(size: 13))
                }
                Slider(value: $speed, in: 0.5...1.8) {
                    Text("Animation speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill")
                } maximumValueLabel: {
                    Image(systemName: "hare.fill")
                }
            }

            Section("Entrance and exit") {
                Picker("Style", selection: $entrance) {
                    ForEach(EntranceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(entranceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Movement") {
                Slider(value: $floatAmount, in: 0...2) { Text("Floating") }
                Slider(value: $swing, in: 0...2) { Text("Swing") }
                Slider(value: $bounce, in: 0...1) { Text("Bounciness") }
                if entrance == .thread {
                    Slider(value: $webLength, in: 30...220) { Text("Thread length") }
                }
            }

            Section("Look and position") {
                Picker("Border", selection: $border) {
                    ForEach(BorderStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Position", selection: $position) {
                    ForEach(StickerPosition.allCases) { place in
                        Text(place.title).tag(place)
                    }
                }
                .pickerStyle(.segmented)
                Text("Position: hang from the middle of the notch, or near its left or right corner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var entranceDescription: String {
        switch entrance {
        case .thread: return "Drops down on a silk thread, swings, and climbs back up."
        case .peek: return "Peeks out from under the notch and slides back in."
        case .pop: return "Pops out with a springy bounce, floats, and shrinks away."
        }
    }
}

// MARK: - Now Playing

struct NowPlayingSection: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Preferences.Key.nowPlaying) private var nowPlaying = Preferences.Default.nowPlaying

    var body: some View {
        let report = model.media
        return Form {
            Section {
                SectionHeader(title: "Now Playing",
                              subtitle: "When music or a video is playing, hovering the notch opens a Dynamic Island with what's playing and its controls.")
                    .padding(.vertical, 4)
                Toggle("Show what's playing when I hover the notch", isOn: $nowPlaying)
                Text("Click your character to open the app switcher, click the song or video to jump to where it's playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What SpiderNotch can see") {
                StatusRow(title: "System Now Playing",
                          detail: report.systemDetail,
                          state: report.systemState)
                if let current = report.currentTitle {
                    StatusRow(title: "Playing now", detail: current, state: .good)
                }
            }

            Section("Permissions") {
                Text("To control Music and Spotify directly, and to find the exact browser tab that's playing, macOS asks once per app: “SpiderNotch wants to control …”. Click Allow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(report.apps) { app in
                    HStack {
                        StatusRow(title: app.name, detail: app.detail, state: app.state)
                        if app.canAsk {
                            Button("Allow…") {
                                MediaCenter.shared.askPermission(for: app.bundleID)
                            }
                        }
                    }
                }
                HStack {
                    Button("Open Automation Settings") { MediaCenter.openAutomationSettings() }
                    Button("Check Again") { model.refreshMedia(force: true) }
                }
            }

            Section("YouTube and other websites") {
                Text("Safari, Chrome, Edge, Brave and other browsers show up automatically while they play, with their controls. To control a video in a tab that isn't the one macOS is showing, also turn on JavaScript from Apple Events (only needed once):")
                    .fixedSize(horizontal: false, vertical: true)
                Text("• Chrome, Edge, Brave: View › Developer › Allow JavaScript from Apple Events\n• Safari: Settings › Advanced › Show features for web developers, then Develop › Allow JavaScript from Apple Events")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Firefox doesn't let other apps see its tabs: SpiderNotch shows what it's playing and brings Firefox forward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshMedia(force: true) }
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    let state: MediaStatusReport.State

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var color: Color {
        switch state {
        case .good: return .green
        case .waiting: return .orange
        case .off: return .gray
        case .problem: return .red
        }
    }
}
