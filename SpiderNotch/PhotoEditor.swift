//
//  PhotoEditor.swift
//  SpiderNotch
//
//  The "My Sticker" editor: crop a photo into a round face portrait, zoom,
//  move it, size the circle, remove the background, pick a background colour
//  and a ring, watch the live preview at a pretend notch, then save.
//
//  The controls are SwiftUI. The crop area is a plain AppKit view, because it
//  needs drags, scrolling and pinching. (No SwiftUI @State here: see
//  SettingsWindow.swift for why.)
//

import AppKit
import SwiftUI

// MARK: - The editor's data

@MainActor
final class PhotoEditorModel: ObservableObject {
    @Published var name: String
    @Published var edit: PhotoStickerEdit {
        didSet { scheduleRender() }
    }
    @Published private(set) var photo: CGImage
    @Published private(set) var cutout: CGImage?
    @Published private(set) var isRemovingBackground = false
    @Published var message: String?
    /// The finished sticker, kept up to date while you edit (for the live preview).
    @Published private(set) var preview: Sticker?
    @Published private(set) var previewVersion = 0

    let existingID: String?
    /// Called when the editor should close (with the saved sticker, or nil if cancelled).
    var onFinish: (@MainActor (MySticker?) -> Void)?
    private var renderTask: Task<Void, Never>?
    private var backgroundJob = 0

    init(photo: CGImage, name: String, edit: PhotoStickerEdit, existingID: String?) {
        self.photo = photo
        self.name = name
        self.edit = edit
        self.existingID = existingID
        if edit.removeBackground {
            startBackgroundRemoval()
        }
        renderPreviewNow()
    }

    /// A new photo: start from a face-centred crop if there's a face.
    static func forNewPhoto(_ photo: CGImage, name: String) -> PhotoEditorModel {
        var edit = PhotoStickerEdit()
        if let face = PhotoStickerRenderer.findFace(in: photo) {
            edit = PhotoStickerRenderer.centered(on: face, in: photo, edit: edit)
        }
        return PhotoEditorModel(photo: photo, name: name, edit: edit, existingID: nil)
    }

    var title: String {
        existingID == nil ? "New Sticker" : "Edit Sticker"
    }

    // MARK: Actions

    func setRemoveBackground(_ on: Bool) {
        edit.removeBackground = on
        message = nil
        if on && cutout == nil {
            startBackgroundRemoval()
        }
    }

    func replacePhoto(_ image: CGImage) {
        photo = image
        cutout = nil
        message = nil
        var fresh = edit
        fresh.zoom = 1
        fresh.offsetX = 0
        fresh.offsetY = 0
        if let face = PhotoStickerRenderer.findFace(in: image) {
            fresh = PhotoStickerRenderer.centered(on: face, in: image, edit: fresh)
        }
        edit = fresh
        if edit.removeBackground {
            startBackgroundRemoval()
        }
    }

    func centerOnFace() {
        if let face = PhotoStickerRenderer.findFace(in: photo) {
            edit = PhotoStickerRenderer.centered(on: face, in: photo, edit: edit)
            message = nil
        } else {
            message = "No face found. Drag the photo to move it, and scroll or pinch to zoom."
        }
    }

    func resetCrop() {
        var fresh = edit
        fresh.zoom = 1
        fresh.offsetX = 0
        fresh.offsetY = 0
        fresh.cropSize = 0.72
        edit = fresh
    }

    func save() {
        guard let rendered = PhotoStickerRenderer.render(photo: photo, cutout: cutout, edit: edit) else {
            Alerts.show(title: "Couldn't make the sticker", message: "Something went wrong while drawing it. Please try again.")
            return
        }
        do {
            let saved = try StickerStore.shared.savePhotoSticker(existingID: existingID, name: name, source: photo,
                                                                 rendered: rendered, edit: edit)
            onFinish?(saved)
        } catch {
            Alerts.show(title: "Couldn't save the sticker", message: error.localizedDescription)
        }
    }

    func cancel() {
        onFinish?(nil)
    }

    // MARK: Background removal (on-device, off the main thread)

    private func startBackgroundRemoval() {
        backgroundJob += 1
        let job = backgroundJob
        let source = photo
        isRemovingBackground = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<CGImage, Error>
            do {
                result = .success(try PhotoStickerRenderer.removeBackground(from: source))
            } catch {
                result = .failure(error)
            }
            Task { @MainActor [weak self] in
                self?.finishBackgroundRemoval(result, job: job)
            }
        }
    }

    private func finishBackgroundRemoval(_ result: Result<CGImage, Error>, job: Int) {
        guard job == backgroundJob else { return }
        isRemovingBackground = false
        switch result {
        case .success(let image):
            cutout = image
            message = nil
            renderPreviewNow()
        case .failure(let error):
            cutout = nil
            edit.removeBackground = false
            message = error.localizedDescription
        }
    }

    // MARK: Live preview

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            self?.renderPreviewNow()
        }
    }

    private func renderPreviewNow() {
        guard let image = PhotoStickerRenderer.render(photo: photo, cutout: cutout, edit: edit, size: 256),
              let sticker = StickerArt.prepare(image, isPhoto: true)
        else { return }
        preview = sticker
        previewVersion += 1
    }
}

// MARK: - The editor window

@MainActor
final class PhotoEditorWindowController: NSObject, NSWindowDelegate {
    private static var open: [PhotoEditorWindowController] = []

    private let model: PhotoEditorModel
    private var window: NSWindow?
    private let onSaved: @MainActor (MySticker) -> Void

    /// Opens the editor. `onSaved` runs after a successful save.
    static func show(model: PhotoEditorModel, onSaved: @escaping @MainActor (MySticker) -> Void) {
        let controller = PhotoEditorWindowController(model: model, onSaved: onSaved)
        open.append(controller)
        controller.present()
    }

    private init(model: PhotoEditorModel, onSaved: @escaping @MainActor (MySticker) -> Void) {
        self.model = model
        self.onSaved = onSaved
        super.init()
    }

    private func present() {
        let hosting = NSHostingController(rootView: PhotoEditorView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = model.title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        window.delegate = self
        self.window = window
        model.onFinish = { [weak self] saved in
            self?.finish(saved)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(_ saved: MySticker?) {
        if let saved = saved {
            onSaved(saved)
        }
        window?.delegate = nil
        window?.close()
        PhotoEditorWindowController.open.removeAll(where: { $0 === self })
    }

    func windowWillClose(_ notification: Notification) {
        PhotoEditorWindowController.open.removeAll(where: { $0 === self })
    }
}

// MARK: - The editor's controls

struct PhotoEditorView: View {
    @ObservedObject var model: PhotoEditorModel
    @AppStorage(Preferences.Key.border) private var border = BorderStyle.white
    @AppStorage(Preferences.Key.entrance) private var entrance = EntranceStyle.thread

    private let fillChoices: [String?] = [nil, "#FFFFFF", "#FFE3EC", "#FFE8D1", "#FFF6C7", "#DDF7E3", "#DCEEFF", "#EADFFF", "#2B2B3A"]
    private let ringChoices: [String] = ["#FFFFFF", "#FF8FB4", "#FFC94D", "#7FD6A8", "#7DB8FF", "#B79CFF", "#2B2B3A"]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 10) {
                PhotoCropCanvas(model: model)
                    .frame(width: 400, height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Drag to move · Scroll or pinch to zoom · Drag the circle's edge to resize · Drop another photo to replace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 400)
                HStack {
                    Button("Center on Face") { model.centerOnFace() }
                    Button("Reset") { model.resetCrop() }
                    Spacer()
                    Button("Another Photo…") {
                        PhotoImporter.shared.chooseFile(startingIn: nil) { image, _ in
                            if let image = image {
                                model.replacePhoto(image)
                            }
                        }
                    }
                }
                .frame(width: 400)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("Sticker name", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    LabeledSlider(title: "Zoom", value: $model.edit.zoom, range: 0.5...6)
                    LabeledSlider(title: "Circle size", value: $model.edit.cropSize, range: 0.3...0.95)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle("Remove background", isOn: Binding(get: { model.edit.removeBackground },
                                                                  set: { model.setRemoveBackground($0) }))
                        if model.isRemovingBackground {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let message = model.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Background").font(.headline)
                    HStack(spacing: 7) {
                        ForEach(fillChoices.indices, id: \.self) { index in
                            ColorSwatch(hex: fillChoices[index], selected: model.edit.fillColor == fillChoices[index]) {
                                model.edit.fillColor = fillChoices[index]
                            }
                        }
                        ColorPicker("", selection: Binding(get: { Color(nsColor: NSColor(hex: model.edit.fillColor ?? "#FFFFFF") ?? .white) },
                                                           set: { model.edit.fillColor = NSColor($0).hexString }),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .help("Any colour")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Ring").font(.headline)
                        Picker("Ring", selection: $model.edit.ringStyle) {
                            ForEach(RingStyle.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    HStack(spacing: 7) {
                        ForEach(ringChoices, id: \.self) { hex in
                            ColorSwatch(hex: hex, selected: model.edit.ringColor == hex) {
                                model.edit.ringColor = hex
                            }
                        }
                        ColorPicker("", selection: Binding(get: { Color(nsColor: NSColor(hex: model.edit.ringColor) ?? .white) },
                                                           set: { model.edit.ringColor = NSColor($0).hexString }),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .help("Any colour")
                    }
                    .disabled(model.edit.ringStyle == RingStyle.none.rawValue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview at the notch").font(.headline)
                    if let preview = model.preview {
                        CharacterPreview(characterID: "editor", settings: SpiderSettings.current(),
                                         sticker: preview, stickerVersion: model.previewVersion)
                            .frame(height: 140)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)).frame(height: 140)
                    }
                    Text("Photos stay on this Mac. The face is never stretched: it only bounces, floats and swings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                    Button(model.existingID == nil ? "Save Sticker" : "Save Changes") { model.save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isRemovingBackground)
                }
            }
            .frame(width: 380)
        }
        .padding(20)
        .frame(width: 860, height: 560)
    }
}

/// A slider with its name on the left.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title).frame(width: 82, alignment: .leading)
            Slider(value: $value, in: range)
        }
    }
}

/// One round colour button. `hex == nil` means "see-through".
struct ColorSwatch: View {
    let hex: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let hex = hex, let color = NSColor(hex: hex) {
                    Circle().fill(Color(nsColor: color))
                } else {
                    Circle().fill(Color.white)
                    Path { path in
                        path.move(to: CGPoint(x: 4, y: 18))
                        path.addLine(to: CGPoint(x: 18, y: 4))
                    }
                    .stroke(Color.red, lineWidth: 2)
                }
                Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                if selected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-4)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(hex == nil ? "See-through" : hex ?? "")
    }
}

// MARK: - The crop area

struct PhotoCropCanvas: NSViewRepresentable {
    @ObservedObject var model: PhotoEditorModel

    func makeNSView(context: Context) -> PhotoCropView {
        let view = PhotoCropView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.onEdit = { [weak model] edit in
            model?.edit = edit
        }
        view.onDropImage = { [weak model] image in
            model?.replacePhoto(image)
        }
        return view
    }

    func updateNSView(_ view: PhotoCropView, context: Context) {
        let picture = (model.edit.removeBackground ? model.cutout : nil) ?? model.photo
        view.update(picture: picture, edit: model.edit)
    }
}

/// Shows the photo under a round window. Drag to move, scroll or pinch to zoom,
/// drag the circle's edge to resize it.
@MainActor
final class PhotoCropView: NSView {
    var onEdit: (@MainActor (PhotoStickerEdit) -> Void)?
    var onDropImage: (@MainActor (CGImage) -> Void)?

    private var picture: CGImage?
    private var edit = PhotoStickerEdit()
    private enum Drag { case none, move, resize }
    private var drag = Drag.none
    private var lastPoint = NSPoint.zero
    private var hoveringEdge = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("PhotoCropView is only created in code.")
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func update(picture: CGImage, edit: PhotoStickerEdit) {
        let changed = picture !== self.picture || edit != self.edit
        self.picture = picture
        self.edit = edit
        if changed {
            needsDisplay = true
        }
    }

    private var side: CGFloat { min(bounds.width, bounds.height) }
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
    private var circleRadius: CGFloat { CGFloat(edit.cropSize) * side / 2 }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.16, alpha: 1).setFill()
        bounds.fill()
        drawChecks()

        let radius = circleRadius
        let circle = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        if let hex = edit.fillColor, let color = NSColor(hex: hex) {
            color.setFill()
            NSBezierPath(ovalIn: circle).fill()
        }

        if let picture = picture, let context = NSGraphicsContext.current?.cgContext {
            let frame = PhotoStickerRenderer.photoFrame(for: picture, edit: edit,
                                                        innerDiameter: radius * 2, center: center)
            context.interpolationQuality = .high
            context.draw(picture, in: frame)
        }

        // Dim everything outside the circle.
        let shade = NSBezierPath(rect: bounds)
        shade.appendOval(in: circle)
        shade.windingRule = .evenOdd
        NSColor(white: 0, alpha: 0.55).setFill()
        shade.fill()

        // The ring, roughly as it will look.
        let ring = RingStyle(rawValue: edit.ringStyle) ?? .classic
        if ring != .none {
            let width = ring.width(for: radius * 2 / 0.9)
            let ringPath = NSBezierPath(ovalIn: circle.insetBy(dx: -width / 2, dy: -width / 2))
            ringPath.lineWidth = width
            (NSColor(hex: edit.ringColor) ?? .white).withAlphaComponent(0.9).setStroke()
            ringPath.stroke()
        }

        // The circle's edge and its resize handle.
        let outline = NSBezierPath(ovalIn: circle)
        outline.lineWidth = hoveringEdge || drag == .resize ? 3 : 1.5
        NSColor(white: 1, alpha: 0.95).setStroke()
        outline.stroke()
        let knob = handlePoint
        let knobRect = NSRect(x: knob.x - 7, y: knob.y - 7, width: 14, height: 14)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSColor(white: 0, alpha: 0.35).setStroke()
        NSBezierPath(ovalIn: knobRect).stroke()
    }

    /// A soft checkerboard, so see-through parts show as see-through.
    private func drawChecks() {
        let size: CGFloat = 12
        NSColor(white: 0.22, alpha: 1).setFill()
        var y: CGFloat = 0
        var row = 0
        while y < bounds.height {
            var x: CGFloat = row % 2 == 0 ? 0 : size
            while x < bounds.width {
                NSRect(x: x, y: y, width: size, height: size).fill()
                x += size * 2
            }
            y += size
            row += 1
        }
    }

    private var handlePoint: NSPoint {
        let angle = -CGFloat.pi / 4
        return NSPoint(x: center.x + cos(angle) * circleRadius, y: center.y + sin(angle) * circleRadius)
    }

    private func isOnEdge(_ point: NSPoint) -> Bool {
        let distance = hypot(point.x - center.x, point.y - center.y)
        let nearKnob = hypot(point.x - handlePoint.x, point.y - handlePoint.y) < 14
        return nearKnob || abs(distance - circleRadius) < 8
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let onEdge = isOnEdge(convert(event.locationInWindow, from: nil))
        if onEdge != hoveringEdge {
            hoveringEdge = onEdge
            needsDisplay = true
        }
        (onEdge ? NSCursor.crosshair : NSCursor.openHand).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            centerOnFace()
            return
        }
        drag = isOnEdge(point) ? .resize : .move
        lastPoint = point
        if drag == .move {
            NSCursor.closedHand.set()
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var changed = edit
        switch drag {
        case .move:
            changed.offsetX += Double((point.x - lastPoint.x) / side)
            changed.offsetY += Double((point.y - lastPoint.y) / side)
            changed.offsetX = min(max(changed.offsetX, -1.5), 1.5)
            changed.offsetY = min(max(changed.offsetY, -1.5), 1.5)
        case .resize:
            let distance = hypot(point.x - center.x, point.y - center.y)
            changed.cropSize = Double(min(max(distance * 2 / side, 0.3), 0.95))
        case .none:
            return
        }
        lastPoint = point
        apply(changed)
    }

    override func mouseUp(with event: NSEvent) {
        drag = .none
        NSCursor.openHand.set()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        zoom(by: exp(Double(delta) * 0.01))
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + Double(event.magnification))
    }

    /// Zooms around the middle of the circle.
    private func zoom(by factor: Double) {
        var changed = edit
        let newZoom = min(max(changed.zoom * factor, 0.5), 6)
        let applied = newZoom / changed.zoom
        changed.zoom = newZoom
        changed.offsetX *= applied
        changed.offsetY *= applied
        apply(changed)
    }

    private func centerOnFace() {
        guard let picture = picture, let face = PhotoStickerRenderer.findFace(in: picture) else { return }
        apply(PhotoStickerRenderer.centered(on: face, in: picture, edit: edit))
    }

    private func apply(_ changed: PhotoStickerEdit) {
        edit = changed
        needsDisplay = true
        onEdit?(changed)
    }

    // MARK: Dropping a photo onto it

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PhotoImporter.imageURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = PhotoImporter.imageURL(from: sender.draggingPasteboard),
              let image = StickerArt.loadPhoto(at: url)
        else { return false }
        onDropImage?(image)
        return true
    }
}
