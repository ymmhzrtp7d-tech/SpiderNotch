//
//  SpiderNotchTests.swift
//  SpiderNotch unit tests
//
//  A tiny test runner that needs only the Command Line Tools (no Xcode, no
//  XCTest). scripts/test.sh compiles it together with every app source file,
//  with -D SPIDERNOTCH_TESTS so the app's own @main is left out.
//
//  Add a test: write a `func testSomething()` below and list it in `all`.
//

import AppKit

@main
@MainActor
enum TestRunner {
    static var failures = 0
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                       file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        if !condition() {
            failures += 1
            print("  ✗ \(message) (\(file):\(line))")
        }
    }

    static let all: [(String, () -> Void)] = [
        ("Stage layout keeps the character inside its window", testStageLayout),
        ("Stage layout works for every entrance style and position", testStageLayoutVariants),
        ("Notch hot zone surrounds the notch", testHotZone),
        ("App links point at the GitHub repository", testAppLinks),
        ("Default settings are sensible", testDefaults),
        ("Hovering opens the island even when nothing plays", testHoverIslandWithoutMedia),
        ("The notch handle only shows on screens without a notch", testNotchHandle),
        ("Cocoon adds, pins, rearranges and removes without touching files", testCocoonBasics),
        ("Cocoon remembers its files after restarting", testCocoonPersistence),
        ("Cocoon follows moved files and notices missing ones", testCocoonMovedAndMissing),
        ("Cocoon lets old recent files expire, keeps pinned ones", testCocoonExpiry),
        ("Recent downloads: newest first, skips unfinished", testRecentDownloads),
        ("Version numbers compare correctly", testVersionCompare),
        ("Updates are labelled major / features / fixes", testUpdateKind),
        ("Release notes highlights from Markdown and HTML", testReleaseHighlights),
        ("GitHub release list is read correctly", testGitHubReleases),
    ]

    static func main() {
        for (name, test) in all {
            let before = failures
            test()
            print(failures == before ? "✓ \(name)" : "✗ \(name)")
        }
        print("\n\(checks) checks, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    static func makeSticker(width: Int = 120, height: Int = 100) -> Sticker {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return Sticker(image: context.makeImage()!, blinkImage: nil, happyImage: nil,
                       anchor: CGPoint(x: 0.5, y: 1))
    }

    static func makeGeometry() -> NotchGeometry {
        // A 14-inch MacBook Pro style screen.
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NSRect(x: 1512 / 2 - 100, y: 982 - 32, width: 200, height: 32)
        return NotchGeometry(screenFrame: screen, notchRect: notch, isHardwareNotch: true, backingScale: 2)
    }

    static func settings(entrance: EntranceStyle = .thread, position: StickerPosition = .center) -> SpiderSettings {
        SpiderSettings(enabled: true, stickerSize: 78, webLength: 72, swing: 1, bounce: 0.55, virtualNotch: true,
                       speed: 1, entrance: entrance, floatAmount: 1, border: .white, position: position,
                       characterID: "builtin:spider", nowPlaying: true)
    }

    // MARK: - Tests

    static func testStageLayout() {
        let geometry = makeGeometry()
        let layout = StageLayout(geometry: geometry, settings: settings(), sticker: makeSticker())
        expect(layout.panelFrame.width > 0 && layout.panelFrame.height > 0, "panel has a size")
        expect(layout.panelFrame.maxY <= geometry.screenFrame.maxY + 0.5, "panel doesn't go above the screen")
        expect(layout.hiddenY > layout.hangingY, "hidden position is above the hanging position")
        expect(abs(layout.stickerSize.height - 78) < 0.5, "sticker is as tall as the setting")
        expect(layout.maxSwingAngle > 0 && layout.maxSwingAngle < .pi / 2, "swing angle is reasonable")
    }

    static func testStageLayoutVariants() {
        let geometry = makeGeometry()
        for entrance in [EntranceStyle.thread, .peek, .pop] {
            for position in [StickerPosition.left, .center, .right] {
                let layout = StageLayout(geometry: geometry, settings: settings(entrance: entrance, position: position),
                                         sticker: makeSticker())
                expect(layout.panelFrame.intersects(geometry.notchRect), "\(entrance)/\(position): window covers the notch")
                expect(layout.notchMidX >= 0 && layout.notchMidX <= layout.panelFrame.width,
                       "\(entrance)/\(position): notch middle is inside the window")
            }
        }
        let open = StageLayout(geometry: geometry, settings: settings(), sticker: makeSticker(), extraDrop: 80)
        let closed = StageLayout(geometry: geometry, settings: settings(), sticker: makeSticker())
        expect(open.hangingY < closed.hangingY, "the character hangs lower while the island is open")
    }

    static func testHotZone() {
        let geometry = makeGeometry()
        expect(geometry.hotZone.contains(geometry.notchRect), "hot zone contains the notch")
        expect(geometry.hotZone.maxY > geometry.screenFrame.maxY, "hot zone reaches past the top edge")
    }

    static func testAppLinks() {
        expect(AppInfo.repository.contains("/"), "repository looks like owner/name")
        expect(AppInfo.repositoryURL.host == "github.com", "repository is on GitHub")
        expect(AppInfo.releasesURL.absoluteString.hasSuffix("/releases"), "releases link")
        let bug = AppInfo.bugReportURL.absoluteString
        expect(bug.contains("issues/new") && bug.contains("template=bug_report.yml"), "bug report link uses the form")
        expect(AppInfo.featureRequestURL.absoluteString.contains("feature_request.yml"), "feature request link")
    }

    // MARK: - Cocoon

    /// A fresh temporary folder with a few files to play with.
    static func makeSandbox() -> (folder: URL, files: [URL]) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpiderNotchTests-\(UUID().uuidString)", isDirectory: true)
        let docs = folder.appendingPathComponent("Docs", isDirectory: true)
        try! FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let a = docs.appendingPathComponent("Report.pdf")
        let b = docs.appendingPathComponent("Photo.png")
        let c = docs.appendingPathComponent("Project", isDirectory: true)
        try! Data("pdf".utf8).write(to: a)
        try! Data("png".utf8).write(to: b)
        try! FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return (folder, [a, b, c])
    }

    static func testCocoonBasics() {
        let (folder, files) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CocoonStore(folder: folder.appendingPathComponent("Support"))
        let added = store.add(files)
        expect(added.count == 3 && store.items.count == 3, "three items added (including a folder)")
        expect(store.items.contains { $0.isDirectory && $0.name == "Project" }, "folder is recognised")
        expect(store.add([files[0]]).count == 1 && store.items.count == 3, "adding the same file again doesn't duplicate it")
        expect(store.add([folder.appendingPathComponent("nope.txt")]).isEmpty, "files that don't exist are ignored")

        let report = store.items.first { $0.name == "Report.pdf" }!
        let photo = store.items.first { $0.name == "Photo.png" }!
        store.setPinned([report.id, photo.id], true)
        expect(store.pinned.count == 2 && store.items.first?.pinned == true, "pinned files come first")
        let firstPinned = store.pinned[0].id
        store.move(store.pinned[1].id, to: firstPinned)
        expect(store.pinned[1].id == firstPinned, "drag to rearrange pinned files")
        let projectID = store.recent[0].id
        store.move(projectID, to: firstPinned)
        expect(store.recent.first?.id == projectID, "a recent file can't be dragged among pinned ones")

        store.setPinned([report.id], false)
        expect(store.recent.contains { $0.id == report.id }, "unpinned files become recent")
        store.clearRecent()
        expect(store.items.map(\.name) == ["Photo.png"], "Clear Recent keeps pinned files")
        store.remove(Set(store.items.map(\.id)))
        expect(store.isEmpty, "remove empties the Cocoon")
        for file in files {
            expect(FileManager.default.fileExists(atPath: file.path), "original \(file.lastPathComponent) still exists")
        }
        expect(CocoonKind.of(files[0], isDirectory: false) == .pdf, "PDF kind")
        expect(CocoonKind.of(files[1], isDirectory: false) == .image, "image kind")
        expect(CocoonKind.of(files[2], isDirectory: true) == .folder, "folder kind")
    }

    static func testCocoonPersistence() {
        let (folder, files) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: folder) }
        let support = folder.appendingPathComponent("Support")
        let store = CocoonStore(folder: support)
        store.add([files[0]], pin: true)
        store.add([files[1]])
        let reopened = CocoonStore(folder: support)
        expect(reopened.items.count == 2, "both files are back after a restart")
        expect(reopened.pinned.first?.name == "Report.pdf", "pinned stays pinned")
        expect(reopened.recent.first?.name == "Photo.png", "recent stays recent")

        try! Data("not json".utf8).write(to: support.appendingPathComponent("Cocoon.json"))
        let broken = CocoonStore(folder: support)
        expect(broken.isEmpty, "an unreadable file doesn't crash")
        expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("Cocoon.unreadable.json").path),
               "and a copy of it is kept")
    }

    static func testCocoonMovedAndMissing() {
        let (folder, files) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CocoonStore(folder: folder.appendingPathComponent("Support"))
        store.add([files[0], files[1]])
        let moved = files[0].deletingLastPathComponent().appendingPathComponent("Report (final).pdf")
        try! FileManager.default.moveItem(at: files[0], to: moved)
        try! FileManager.default.removeItem(at: files[1])
        store.refresh()
        let report = store.items.first { $0.path.hasSuffix(".pdf") }
        expect(report?.path == moved.standardizedFileURL.path, "follows a renamed file")
        expect(report?.name == "Report (final).pdf", "shows the new name")
        expect(store.missing.count == 1, "notices the deleted file")
        if let photo = store.items.first(where: { $0.name == "Photo.png" }) {
            expect(store.currentURL(for: photo) == nil, "a missing file has no location")
        }
    }

    static func testCocoonExpiry() {
        let (folder, files) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = Preferences.Key.cocoonRecentHours
        UserDefaults.standard.set(24.0, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let support = folder.appendingPathComponent("Support")
        let start = Date()
        let store = CocoonStore(folder: support, now: { start })
        store.add([files[0]], pin: true)
        store.add([files[1]])
        let later = CocoonStore(folder: support, now: { start.addingTimeInterval(2 * 24 * 3600) })
        later.refresh()
        expect(later.items.map(\.name) == ["Report.pdf"], "recent file expired after a day, pinned stayed")
        UserDefaults.standard.set(0.0, forKey: key)
        let keepAll = CocoonStore(folder: support, now: { start.addingTimeInterval(30 * 24 * 3600) })
        keepAll.add([files[1]])
        keepAll.refresh()
        expect(keepAll.items.count == 2, "“Until I clear them” keeps recent files")
    }

    static func testRecentDownloads() {
        let (folder, _) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloads = folder.appendingPathComponent("Downloads", isDirectory: true)
        try! FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        for (index, name) in ["old.zip", "new.pdf", "partial.crdownload"].enumerated() {
            let url = downloads.appendingPathComponent(name)
            try! Data().write(to: url)
            try! FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(Double(index) * 60)], ofItemAtPath: url.path)
        }
        let newest = RecentDownloads.newest(limit: 5, in: downloads).map(\.lastPathComponent)
        expect(!newest.contains("partial.crdownload"), "unfinished downloads are skipped")
        expect(Set(newest) == ["old.zip", "new.pdf"], "finished downloads are listed")
    }

    // MARK: - Updates

    static func testVersionCompare() {
        expect(ReleaseNotes.compare("1.10.0", "1.9.2") == .orderedDescending, "1.10.0 > 1.9.2")
        expect(ReleaseNotes.compare("1.4.0", "1.4.0-beta.2") == .orderedDescending, "release > beta")
        expect(ReleaseNotes.compare("1.4.0-beta.10", "1.4.0-beta.2") == .orderedDescending, "beta.10 > beta.2")
        expect(ReleaseNotes.compare("v1.3.0", "1.3") == .orderedSame, "v1.3.0 == 1.3")
        expect(ReleaseNotes.compare("1.3.0", "1.4.0") == .orderedAscending, "1.3.0 < 1.4.0")
    }

    static func testUpdateKind() {
        expect(ReleaseNotes.kind(from: "1.3.0", to: "2.0.0") == .major, "major")
        expect(ReleaseNotes.kind(from: "1.3.0", to: "1.4.0") == .feature, "features")
        expect(ReleaseNotes.kind(from: "1.3.0", to: "1.3.1") == .fixes, "fixes")
    }

    static func testReleaseHighlights() {
        let markdown = "- **Cocoon**: keep files handy.\n  More text.\n- Fixed a [bug](https://x.y).\n\n---\n\n- Download below"
        let lines = ReleaseNotes.highlights(fromMarkdown: markdown)
        expect(lines == ["Cocoon: keep files handy. More text.", "Fixed a bug."], "markdown bullets, joined and cleaned")
        let html = "<ul><li><b>Cocoon</b>: files &amp; more</li><li>Fix</li></ul>"
        expect(ReleaseNotes.highlights(fromHTML: html) == ["Cocoon: files & more", "Fix"], "html bullets")
        expect(ReleaseNotesText.bullets(markdown).count == 2, "release notes view stops at the download part")
    }

    static func testGitHubReleases() {
        let json = """
        [{"tag_name":"v1.4.0","name":"SpiderNotch 1.4.0","published_at":"2026-11-07T10:00:00Z","body":"- New","html_url":"https://github.com/a/b/releases/tag/v1.4.0","prerelease":false,"draft":false},
         {"tag_name":"v1.5.0-beta.1","name":"Beta","published_at":"2026-11-08T10:00:00Z","body":"","prerelease":true,"draft":false},
         {"tag_name":"v9.0.0","draft":true}]
        """
        let releases = ReleaseNotes.parseGitHubReleases(Data(json.utf8))
        expect(releases.count == 2, "drafts are skipped")
        expect(releases.first?.version == "1.4.0" && releases.first?.date != nil, "version and date")
        expect(releases.last?.isPrerelease == true, "betas are marked")
    }

    static func testHoverIslandWithoutMedia() {
        // Nothing playing (Music, Spotify and browsers closed): the file hub opens.
        expect(HoverIsland.choose(enabled: true, mediaAvailable: false, cocoonOnHover: true) == .files,
               "no media → the Cocoon opens")
        // Something playing: Now Playing first (the Cocoon is a tab away).
        expect(HoverIsland.choose(enabled: true, mediaAvailable: true, cocoonOnHover: true) == .nowPlaying,
               "media → Now Playing")
        expect(HoverIsland.choose(enabled: true, mediaAvailable: true, cocoonOnHover: false) == .nowPlaying,
               "media with the Cocoon off → Now Playing")
        // Only switched off by the person, never by media stopping.
        expect(HoverIsland.choose(enabled: true, mediaAvailable: false, cocoonOnHover: false) == .none,
               "Cocoon hover switched off and nothing playing → just the character")
        expect(HoverIsland.choose(enabled: false, mediaAvailable: true, cocoonOnHover: true) == .none,
               "SpiderNotch disabled → nothing")
        // The defaults open the Cocoon on hover.
        expect(Preferences.Default.cocoonEnabled && Preferences.Default.cocoonOpenOnHover,
               "Cocoon and open-on-hover are on by default")
    }

    static func testNotchHandle() {
        let real = makeGeometry()
        expect(NotchHandle.frame(for: real) == nil, "no handle on a real notch")
        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let pretend = NotchGeometry(screenFrame: screen, notchRect: NSRect(x: 1190, y: 1416, width: 180, height: 24),
                                    isHardwareNotch: false, backingScale: 2)
        if let frame = NotchHandle.frame(for: pretend) {
            expect(abs(frame.midX - 1280) < 0.5, "handle is centred on the pretend notch")
            expect(frame.maxY <= screen.maxY && frame.minY >= pretend.notchRect.minY, "handle sits in the menu bar")
            expect(pretend.hotZone.intersects(frame), "hovering the handle reaches the island's hot zone")
        } else {
            expect(false, "a screen without a notch gets a handle")
        }
    }

    static func testDefaults() {
        expect(Preferences.Default.characterID == "builtin:spider", "the spider is the default character")
        expect(Preferences.Default.stickerSize >= 40 && Preferences.Default.stickerSize <= 160, "default size in range")
        expect(Preferences.Default.enabled, "enabled by default")
        expect(Preferences.Default.cocoonEnabled && !Preferences.Default.cocoonShowDownloads,
               "Cocoon on, Downloads off until you allow it")
    }
}
