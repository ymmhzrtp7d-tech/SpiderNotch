//
//  UpdateAnnouncementPanel.swift
//  SpiderNotch
//
//  The small card in the top-right corner that says
//  "A New Update Is Available!" (or "SpiderNotch was updated").
//  It never takes the keyboard focus or steals clicks from your work, and it
//  goes away by itself after a while; the menu bar dot and Settings →
//  Update Center keep showing the update until you install it.
//

import AppKit
import SwiftUI

@MainActor
final class UpdateAnnouncementPanel {
    static let shared = UpdateAnnouncementPanel()

    enum Content: Equatable {
        case available(ReleaseInfo, kind: UpdateKind)
        case updated(ReleaseInfo, kind: UpdateKind)
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private(set) var current: Content?

    func show(_ content: Content, after delay: TimeInterval = 0) {
        hideTask?.cancel()
        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            self?.present(content)
        }
    }

    private func present(_ content: Content) {
        current = content
        let view = AnnouncementCard(content: content)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let card = panel ?? makePanel()
        panel = card
        card.contentView = hosting
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 10,
                           width: size.width, height: size.height)
        card.setFrame(frame.offsetBy(dx: 0, dy: 12), display: false)
        card.alphaValue = 0
        card.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().alphaValue = 1
            card.animator().setFrame(frame, display: true)
        }
        // It doesn't stay forever: the menu bar dot and Update Center remember it.
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        current = nil
        guard let card = panel, card.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            card.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if card.alphaValue == 0 { card.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let card = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        card.isFloatingPanel = true
        card.level = .floating
        card.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        card.backgroundColor = .clear
        card.isOpaque = false
        card.hasShadow = true
        card.hidesOnDeactivate = false
        card.isReleasedWhenClosed = false
        card.becomesKeyOnlyIfNeeded = true
        return card
    }
}

struct AnnouncementCard: View {
    let content: UpdateAnnouncementPanel.Content

    private var release: ReleaseInfo {
        switch content {
        case .available(let r, _), .updated(let r, _): return r
        }
    }

    private var kind: UpdateKind {
        switch content {
        case .available(_, let k), .updated(_, let k): return k
        }
    }

    private var isAvailable: Bool {
        if case .available = content { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAvailable ? "A New Update Is Available!" : "SpiderNotch was updated")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    isAvailable ? UpdateCenter.shared.remindLater() : UpdateAnnouncementPanel.shared.hide()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isAvailable ? "Remind me later" : "Close")
            }

            Label(kind.label, systemImage: kind.symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(kindColor.opacity(0.18)))
                .foregroundStyle(kindColor)

            let highlights = release.highlights
            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(highlights.prefix(3), id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
            }

            HStack {
                Button(isAvailable ? "Release Notes" : "What's New") { UpdateCenter.shared.showReleaseNotes() }
                Spacer()
                if isAvailable {
                    Button("Remind Me Later") { UpdateCenter.shared.remindLater() }
                    Button("Update Now") { UpdateCenter.shared.updateNow() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("OK") { UpdateAnnouncementPanel.shared.hide() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var subtitle: String {
        let dateText = release.date.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        if isAvailable {
            return "Version \(release.version)\(dateText) · you have \(AppInfo.version)"
        }
        return "You're now on version \(release.version). Here's what's new:"
    }

    private var kindColor: Color {
        switch kind {
        case .major: return .orange
        case .feature: return .purple
        case .fixes: return .blue
        }
    }
}
