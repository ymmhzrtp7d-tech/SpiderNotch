//
//  CocoonSettings.swift
//  SpiderNotch
//
//  Settings → Cocoon. (No @State: see SettingsWindow.swift.)
//

import AppKit
import SwiftUI

struct CocoonSection: View {
    @ObservedObject var store = CocoonStore.shared
    @AppStorage(Preferences.Key.cocoonEnabled) private var enabled = Preferences.Default.cocoonEnabled
    @AppStorage(Preferences.Key.cocoonOpenOnHover) private var openOnHover = Preferences.Default.cocoonOpenOnHover
    @AppStorage(Preferences.Key.cocoonRecentHours) private var recentHours = Preferences.Default.cocoonRecentHours
    @AppStorage(Preferences.Key.cocoonShowDownloads) private var showDownloads = Preferences.Default.cocoonShowDownloads

    var body: some View {
        Form {
            Section {
                SectionHeader(title: "Cocoon",
                              subtitle: "Keep files handy in the island at the notch. Drag them in, pin the ones you use often, open, preview and AirDrop them.")
                    .padding(.vertical, 4)
                Toggle("Use the Cocoon", isOn: $enabled)
                Toggle("Open it when I hover the notch", isOn: $openOnHover)
                    .disabled(!enabled)
            } footer: {
                Text("Drag files from Finder onto the notch: drop on Keep (Recent), Pin (stays for good) or AirDrop. You can also choose Open Cocoon from the spider menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recent files") {
                Picker("Keep recent files for", selection: $recentHours) {
                    Text("1 hour").tag(1.0)
                    Text("1 day").tag(24.0)
                    Text("1 week").tag(168.0)
                    Text("Until I clear them").tag(0.0)
                }
                Text("Pinned files stay until you unpin or remove them. Removing a file from the Cocoon never deletes or moves the file itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("In the Cocoon now", value: "\(store.pinned.count) pinned · \(store.recent.count) recent")
                HStack {
                    Spacer()
                    Button("Clear Recent") { store.clearRecent() }
                        .disabled(store.recent.isEmpty)
                    Button("Remove All…") {
                        if Alerts.confirm(title: "Remove everything from the Cocoon?",
                                          message: "Pinned and recent files leave the Cocoon. The files themselves stay exactly where they are.",
                                          button: "Remove All") {
                            store.remove(Set(store.items.map { $0.id }))
                        }
                    }
                    .disabled(store.isEmpty)
                }
            }

            Section("Downloads") {
                Toggle("Show my newest downloads in the Cocoon", isOn: $showDownloads)
                Text("Adds a Downloads filter with the 6 newest files in your Downloads folder. The first time, macOS asks whether SpiderNotch may read the Downloads folder. Nothing is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Tips") {
                Text("• Click a file for its actions; ⌘-click or ⇧-click to pick several.\n• Double-click opens it. Space previews it, Delete takes it out of the Cocoon.\n• Drag a file out of the Cocoon into any app, or onto another file to rearrange.\n• The pin at the top right keeps the island open while you work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
