//
//  AboutSections.swift
//  SpiderNotch
//
//  The Updates and About pages of the Settings window.
//  (No @State here on purpose: see the note at the top of SettingsWindow.swift.)
//

import AppKit
import SwiftUI

// MARK: - Update Center

struct UpdatesSection: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var center = UpdateCenter.shared

    var body: some View {
        Form {
            Section {
                SectionHeader(title: "Update Center",
                              subtitle: "SpiderNotch is actively developed. New versions are published on GitHub and installed with one click.")
                    .padding(.vertical, 4)
            }

            Section {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 30))
                        .foregroundStyle(statusColor)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle).font(.headline)
                        Text(statusDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if center.status == .available {
                        Button("Update Now") { center.updateNow() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Check for Updates") { updater.checkForUpdates() }
                            .disabled(updater.isAvailable && !updater.canCheckForUpdates)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Installed version", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("Latest version", value: center.latestVersion)
                LabeledContent("Last checked", value: lastCheckText)
            }

            if let release = center.available ?? center.history.first(where: { !$0.isPrerelease }) {
                Section(center.available != nil ? "What's new in \(release.version)" : "What's new in the latest version (\(release.version))") {
                    let kind = ReleaseNotes.kind(from: AppInfo.version, to: release.version)
                    if center.available != nil {
                        Label(kind.label, systemImage: kind.symbol)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(kind == .major ? Color.orange : (kind == .feature ? Color.purple : Color.blue))
                    }
                    ReleaseNotesText(markdown: release.notes)
                }
            }

            Section {
                if updater.isAvailable {
                    Toggle("Check for updates automatically (once a day)", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }))
                    Toggle("Notify me when an update is available", isOn: Binding(
                        get: { center.notifyEnabled },
                        set: { center.notifyEnabled = $0 }))
                    Picker("Installing updates", selection: Binding(
                        get: { updater.automaticallyDownloads },
                        set: { updater.automaticallyDownloads = $0 })) {
                        Text("Ask me first (Update Now)").tag(false)
                        Text("Automatically, when I quit SpiderNotch").tag(true)
                    }
                    .disabled(!updater.automaticallyChecks)
                } else {
                    Text("This copy was built without the automatic updater. “Check for Updates” opens the download page instead.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("“Notify me” shows a small card in the corner and a dot on the menu bar spider; it never interrupts what you're doing. “Remind Me Later” keeps quiet for a day. Every update is checked against SpiderNotch's signing key before it's installed, and your settings, stickers and Cocoon files are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if center.isLoadingHistory && center.history.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Loading from GitHub…").foregroundStyle(.secondary) }
                } else if let error = center.historyError, center.history.isEmpty {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(center.history) { release in
                    DisclosureGroup {
                        ReleaseNotesText(markdown: release.notes)
                        if let url = release.url {
                            LinkRow(title: "Open on GitHub", symbol: "arrow.up.right.square", url: url)
                        }
                    } label: {
                        HStack {
                            Text(release.version).font(.body.monospacedDigit().weight(.semibold))
                            if release.version == AppInfo.version {
                                Text("Installed").font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            }
                            if release.isPrerelease {
                                Text("Beta").font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                            }
                            Spacer()
                            if let date = release.date {
                                Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Release history")
                    Spacer()
                    Button {
                        center.loadHistory(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reload from GitHub")
                }
            }

            Section {
                LinkRow(title: "All downloads on GitHub", symbol: "arrow.down.circle", url: AppInfo.releasesURL)
                LinkRow(title: "Full changelog", symbol: "list.bullet.rectangle", url: AppInfo.changelogURL)
            }
        }
        .formStyle(.grouped)
        .onAppear { center.loadHistory() }
    }

    private var statusTitle: String {
        switch center.status {
        case .available: return "A new update is available: \(center.available?.version ?? "")"
        case .checking: return "Checking for updates…"
        case .failed: return "The update didn't work"
        case .upToDate, .idle:
            if ReleaseNotes.compare(center.latestVersion, AppInfo.version) == .orderedDescending {
                return "Version \(center.latestVersion) is out"
            }
            return "SpiderNotch is up to date"
        }
    }

    private var statusDetail: String {
        switch center.status {
        case .available: return "Click Update Now: SpiderNotch downloads it, checks its signature, installs it and reopens."
        case .checking: return "Asking GitHub for the newest version."
        case .failed(let message): return message
        case .upToDate, .idle:
            if ReleaseNotes.compare(center.latestVersion, AppInfo.version) == .orderedDescending {
                return "Click Check for Updates to install it."
            }
            return "You have the newest version, \(AppInfo.version)."
        }
    }

    private var statusSymbol: String {
        switch center.status {
        case .available: return "arrow.down.circle.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        case .upToDate, .idle: return "checkmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch center.status {
        case .available: return .accentColor
        case .checking: return .secondary
        case .failed: return .orange
        case .upToDate, .idle: return .green
        }
    }

    private var lastCheckText: String {
        guard let date = updater.lastCheck else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Release notes (Markdown from GitHub or the changelog), shown as tidy bullet points.
struct ReleaseNotesText: View {
    let markdown: String

    var body: some View {
        let lines = ReleaseNotesText.bullets(markdown)
        return VStack(alignment: .leading, spacing: 6) {
            if lines.isEmpty {
                Text("Bug fixes and improvements.").foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Joins wrapped bullet lines and stops at the "---" download instructions.
    static func bullets(_ markdown: String) -> [String] {
        var result: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("---") { break }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(String(line.dropFirst(2)))
            } else if !line.isEmpty, !line.hasPrefix("#"), !result.isEmpty, raw.hasPrefix("  ") {
                result[result.count - 1] += " " + line
            } else if !line.isEmpty, !line.hasPrefix("#") {
                result.append(line)
            }
        }
        return result
    }
}

// MARK: - About

struct AboutSection: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SpiderNotch").font(.title.weight(.semibold))
                        Text("Version \(AppInfo.version) (build \(AppInfo.build)) · \(AppInfo.machineKind)")
                            .foregroundStyle(.secondary)
                        Text("A cute character that lives in your Mac's notch. Free and open source (MIT licence).")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Project") {
                LinkRow(title: "Source code on GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: AppInfo.repositoryURL)
                LinkRow(title: "Report a bug", symbol: "ladybug", url: AppInfo.bugReportURL)
                LinkRow(title: "Request a feature", symbol: "lightbulb", url: AppInfo.featureRequestURL)
                LinkRow(title: "Help and troubleshooting", symbol: "questionmark.circle", url: AppInfo.helpURL)
            }
            Section("Privacy") {
                Text("No account, no ads, no analytics. Your photos and stickers stay on this Mac in ~/Library/Application Support/SpiderNotch. Update checks contact GitHub, which sees your IP address and the file requested; nothing else is sent.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LinkRow(title: "Privacy policy", symbol: "hand.raised", url: AppInfo.privacyURL)
            }
            Section("Credits") {
                Text("Made by Huang with Claude. Updates by Sparkle (MIT). Now Playing approach inspired by mediaremote-adapter (BSD-3-Clause).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LinkRow(title: "Licence", symbol: "doc.text", url: AppInfo.licenseURL)
            }
        }
        .formStyle(.grouped)
    }
}

/// A row that opens a web page.
struct LinkRow: View {
    let title: String
    let symbol: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
