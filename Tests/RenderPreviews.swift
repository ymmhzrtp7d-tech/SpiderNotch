//
//  RenderPreviews.swift
//  Draws the new screens into PNG files without needing a display
//  (bash scripts/render-previews.sh OUTPUT_FOLDER). Used to check the design.
//

import AppKit
import SwiftUI

@main
@MainActor
enum RenderPreviews {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments.last!)
        Preferences.registerDefaults()
        let model = CocoonModel.shared
        // Run with -SpiderNotchSupportFolder <temp folder> so your own Cocoon is never touched.
        if model.store.isEmpty {
            let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let samples = ["README.md", "LICENSE", "CHANGELOG.md", "docs/images/characters.png", "docs/images/icon.png"]
                .map { here.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            let ids = model.store.add(samples)
            model.store.setPinned(Set(ids.prefix(2)), true)
        }
        model.willAppear()

        // 1. The Cocoon with files, one selected.
        if let first = model.store.items.first(where: { $0.name == "README.md" }) {
            model.selection = [first.id]
        }
        render(island(CocoonView(model: model)), size: CGSize(width: 700, height: 230), to: out.appendingPathComponent("cocoon.png"))

        // 2. Dragging files in: the drop zones, with "Pin" under the cursor.
        model.selection = []
        model.isDraggingFiles = true
        model.targetedZone = .pin
        render(island(CocoonView(model: model)), size: CGSize(width: 700, height: 230), to: out.appendingPathComponent("cocoon-drop.png"))
        model.isDraggingFiles = false
        model.targetedZone = nil

        // 3. Empty Cocoon.
        model.store.remove(Set(model.store.items.map(\.id)))
        render(island(CocoonView(model: model)), size: CGSize(width: 700, height: 230), to: out.appendingPathComponent("cocoon-empty.png"))

        // 4. The update card.
        let notes = "- **Cocoon**: keep files handy in the island. Drag files onto the notch to keep, pin or AirDrop them.\n- **Update Center** in Settings, with release history.\n- Bug fixes."
        let release = ReleaseInfo(version: "1.4.0", title: "SpiderNotch 1.4.0", date: Date(), notes: notes, url: nil, isPrerelease: false)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(AnnouncementCard(content: .available(release, kind: .feature)).padding(20), size: CGSize(width: 400, height: 330),
                   to: out.appendingPathComponent("update-card-\(name).png"), appearance: appearance)
        }

        // 5. Update Center and Cocoon settings, light and dark.
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(UpdatesSection().frame(width: 704, height: 900), size: CGSize(width: 704, height: 900),
                   to: out.appendingPathComponent("update-center-\(name).png"), appearance: appearance)
            render(CocoonSection().frame(width: 704, height: 700), size: CGSize(width: 704, height: 700),
                   to: out.appendingPathComponent("cocoon-settings-\(name).png"), appearance: appearance)
        }
    }

    /// The black island around the content, like at the notch.
    static func island<V: View>(_ content: V) -> some View {
        content
            .padding(.horizontal, 18)
            .padding(.top, 40)
            .padding(.bottom, 12)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30).fill(Color.black))
            .padding(20)
            .background(Color(white: 0.55))
    }

    static func render<V: View>(_ view: V, size: CGSize, to url: URL, appearance: NSAppearance.Name = .darkAqua) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6)) // let thumbnails and layout settle
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.lastPathComponent)")
    }
}
