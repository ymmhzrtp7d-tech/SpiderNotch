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

    static func testDefaults() {
        expect(Preferences.Default.characterID == "builtin:spider", "the spider is the default character")
        expect(Preferences.Default.stickerSize >= 40 && Preferences.Default.stickerSize <= 160, "default size in range")
        expect(Preferences.Default.enabled, "enabled by default")
    }
}
