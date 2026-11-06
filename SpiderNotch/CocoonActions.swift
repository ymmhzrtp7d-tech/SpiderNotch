//
//  CocoonActions.swift
//  SpiderNotch
//
//  What you can do with files in the Cocoon: open, Quick Look, reveal in
//  Finder, copy, and share with AirDrop. Also the thumbnails.
//
//  AirDrop uses Apple's own sharing service (NSSharingService .sendViaAirDrop),
//  which shows the standard AirDrop window where you pick a nearby device.
//  SpiderNotch never talks to the AirDrop protocol itself.
//

import AppKit
import Quartz
import QuickLookThumbnailing

@MainActor
enum CocoonActions {
    /// Turns items into the files' current locations, telling you about any that are missing.
    static func urls(for items: [CocoonItem]) -> [URL] {
        let store = CocoonStore.shared
        var found: [URL] = []
        var lost: [String] = []
        for item in items {
            if let url = store.currentURL(for: item) {
                found.append(url)
            } else {
                lost.append(item.name)
            }
        }
        if !lost.isEmpty {
            store.refresh()
            Alerts.show(title: lost.count == 1 ? "“\(lost[0])” can't be found" : "\(lost.count) files can't be found",
                        message: "It may have been moved to the Trash, deleted, or be on a disk that isn't connected. You can remove it from the Cocoon.")
        }
        return found
    }

    static func open(_ items: [CocoonItem]) {
        for url in urls(for: items) {
            NSWorkspace.shared.open(url)
        }
    }

    static func reveal(_ items: [CocoonItem]) {
        let found = urls(for: items)
        guard !found.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(found)
    }

    /// Puts the files on the clipboard: paste in Finder to copy them, or in a
    /// document or chat to attach them.
    static func copy(_ items: [CocoonItem]) {
        let found = urls(for: items)
        guard !found.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(found as [NSURL])
    }

    // MARK: - Choosing files

    /// Shows the standard Open window (files and folders, several at once).
    /// SpiderNotch comes to the front for it, since it has no Dock icon.
    static func chooseFiles(prompt: String, message: String, completion: @escaping @MainActor ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        panel.message = message
        NSApp.activate()
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated {
                completion(urls)
            }
        }
    }

    // MARK: - AirDrop

    private static let sharingDelegate = SharingDelegate()

    /// Opens the standard AirDrop window for these files.
    static func airDrop(_ items: [CocoonItem]) {
        airDrop(urls: urls(for: items))
    }

    static func airDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            Alerts.show(title: "AirDrop isn't available", message: "This Mac doesn't offer AirDrop.")
            return
        }
        guard service.canPerform(withItems: urls) else {
            Alerts.show(title: "AirDrop can't share this right now",
                        message: "Make sure Wi-Fi and Bluetooth are on, and that AirDrop is allowed in Control Center (AirDrop: Contacts Only or Everyone).")
            return
        }
        service.delegate = sharingDelegate
        NSApp.activate()
        service.perform(withItems: urls)
    }

    private final class SharingDelegate: NSObject, NSSharingServiceDelegate {
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            let nsError = error as NSError
            // Closing the AirDrop window without sending isn't an error worth a message.
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
            Task { @MainActor in
                Alerts.show(title: "AirDrop didn't finish", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Quick Look

    static func quickLook(_ items: [CocoonItem]) {
        QuickLooker.shared.show(urls(for: items))
    }

    // MARK: - Thumbnails

    private static let thumbnails = NSCache<NSString, NSImage>()

    /// The file's icon right away (cached thumbnail if there is one).
    static func icon(for item: CocoonItem) -> NSImage {
        if let cached = thumbnails.object(forKey: cacheKey(item)) {
            return cached
        }
        return NSWorkspace.shared.icon(forFile: item.path)
    }

    /// Makes a real preview picture in the background (Quick Look), then calls back.
    static func loadThumbnail(for item: CocoonItem, side: CGFloat, completion: @escaping @MainActor (NSImage) -> Void) {
        let key = cacheKey(item)
        if let cached = thumbnails.object(forKey: key) {
            completion(cached)
            return
        }
        guard FileManager.default.fileExists(atPath: item.path) else { return }
        let request = QLThumbnailGenerator.Request(fileAt: item.url,
                                                   size: CGSize(width: side, height: side),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in
                thumbnails.setObject(image, forKey: key)
                completion(image)
            }
        }
    }

    private static func cacheKey(_ item: CocoonItem) -> NSString {
        "\(item.id.uuidString)|\(item.path)" as NSString
    }
}

/// Shows files in the standard Quick Look window (space bar in Finder).
@MainActor
final class QuickLooker: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLooker()
    private var urls: [URL] = []

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            urls.indices.contains(index) ? urls[index] as NSURL : nil
        }
    }
}
