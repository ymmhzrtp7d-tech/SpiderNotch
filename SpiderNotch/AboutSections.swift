//
//  AboutSections.swift
//  SpiderNotch
//
//  The Updates and About pages of the Settings window.
//  (No @State here on purpose: see the note at the top of SettingsWindow.swift.)
//

import AppKit
import SwiftUI

// MARK: - Updates

struct UpdatesSection: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                SectionHeader(title: "Updates",
                              subtitle: "New versions are published on GitHub. SpiderNotch can find and install them for you.")
                    .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Installed version", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("Last checked", value: lastCheckText)
                HStack {
                    Spacer()
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(updater.isAvailable && !updater.canCheckForUpdates)
                        .keyboardShortcut(.defaultAction)
                }
            }
            if updater.isAvailable {
                Section {
                    Toggle("Check for updates automatically (once a day)", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }))
                    Toggle("Download and install updates automatically", isOn: Binding(
                        get: { updater.automaticallyDownloads },
                        set: { updater.automaticallyDownloads = $0 }))
                        .disabled(!updater.automaticallyChecks)
                } footer: {
                    Text("Every update is checked against SpiderNotch's signing key before it's installed. Your settings, characters and stickers are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("This copy was built without the automatic updater. “Check for Updates…” opens the download page instead.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                LinkRow(title: "What's new in each version", symbol: "list.bullet.rectangle", url: AppInfo.changelogURL)
                LinkRow(title: "All downloads on GitHub", symbol: "arrow.down.circle", url: AppInfo.releasesURL)
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckText: String {
        guard let date = updater.lastCheck else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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
