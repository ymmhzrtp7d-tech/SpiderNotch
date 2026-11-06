//
//  PhotoImporter.swift
//  SpiderNotch
//
//  Getting a picture into SpiderNotch: from your Photos library, from the
//  Desktop or Downloads folder, from any file, or by dragging it in.
//  PNG, JPEG, HEIC, WebP and every other image format macOS can open.
//
//  The Photos picker runs in a separate, private system process: SpiderNotch
//  only ever sees the one photo you choose, and needs no Photos permission.
//

import AppKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class PhotoImporter: NSObject, PHPickerViewControllerDelegate {
    static let shared = PhotoImporter()

    /// The picture (the right way up), and a suggested name for the sticker.
    typealias Completion = @MainActor (CGImage?, String?) -> Void

    enum Place {
        case desktop, downloads, pictures, anywhere
    }

    private var pickerCompletion: Completion?
    private var pickerWindow: NSWindow?

    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .webP, .image]

    // MARK: - Files

    func chooseFile(in place: Place, completion: @escaping Completion) {
        let manager = FileManager.default
        let folder: URL?
        switch place {
        case .desktop: folder = manager.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .downloads: folder = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .pictures: folder = manager.urls(for: .picturesDirectory, in: .userDomainMask).first
        case .anywhere: folder = nil
        }
        chooseFile(startingIn: folder, completion: completion)
    }

    func chooseFile(startingIn folder: URL?, completion: @escaping Completion) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Photo"
        panel.message = "Pick a photo of a face (yours, a friend's, a pet's…). PNG, JPEG, HEIC and WebP all work."
        panel.prompt = "Use This Photo"
        panel.allowedContentTypes = PhotoImporter.imageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let folder = folder {
            panel.directoryURL = folder
        }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = StickerArt.loadPhoto(at: url) else {
            Alerts.show(title: "Couldn't open that picture", message: StickerError.unreadable.localizedDescription)
            return
        }
        completion(image, url.deletingPathExtension().lastPathComponent)
    }

    /// For a ready-made character picture (used as it is, not cropped).
    func choosePictureFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Character Picture"
        panel.message = "A PNG with a transparent background looks best. Put “name-blink.png” (eyes closed) and “name-happy.png” (big smile) next to it and it will blink and smile too."
        panel.prompt = "Add Picture"
        panel.allowedContentTypes = PhotoImporter.imageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Photos library

    /// Shows the system Photos picker (as a sheet on `controller`'s window if given).
    func pickFromPhotos(presentingFrom controller: NSViewController?, completion: @escaping Completion) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        pickerCompletion = completion
        NSApp.activate()
        if let controller = controller, controller.view.window != nil {
            controller.presentAsSheet(picker)
        } else {
            let window = NSWindow(contentViewController: picker)
            window.title = "Choose a Photo"
            window.setContentSize(NSSize(width: 760, height: 560))
            window.center()
            window.isReleasedWhenClosed = false
            pickerWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        if let window = pickerWindow {
            window.close()
            pickerWindow = nil
        } else {
            picker.dismiss(nil)
        }
        let completion = pickerCompletion
        pickerCompletion = nil
        guard let result = results.first, let completion = completion else { return }
        PhotoImporter.loadImage(from: result.itemProvider, completion: completion)
    }

    // MARK: - Dragging pictures in

    /// The first image file on a drag pasteboard.
    static func imageURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    /// Loads a picture from dropped items (files, or images dragged from Photos or a browser).
    /// Returns false if none of them looks like a picture.
    @discardableResult
    static func loadImage(from providers: [NSItemProvider], completion: @escaping Completion) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let fileURL = item as? URL {
                    url = fileURL
                }
                let image = url.flatMap { StickerArt.loadPhoto(at: $0) }
                let name = url?.deletingPathExtension().lastPathComponent
                Task { @MainActor in
                    completion(image, name)
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            loadImage(from: provider, completion: completion)
            return true
        }
        return false
    }

    /// Reads the image data an item provider offers (HEIC, JPEG, PNG…).
    static func loadImage(from provider: NSItemProvider, completion: @escaping Completion) {
        let typeID = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) ?? UTType.image.identifier
        let name = provider.suggestedName
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
            let image = data.flatMap { StickerArt.loadPhoto(data: $0) }
            Task { @MainActor in
                completion(image, name)
            }
        }
    }
}
