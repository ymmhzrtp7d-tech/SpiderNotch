# Developing SpiderNotch

How to change SpiderNotch, try your changes, and share new versions.
Everything here works with just Apple's free Command Line Tools. Xcode is optional.

The code lives on GitHub; every push is tested and built by GitHub Actions,
and changing `VERSION` on `main` publishes a release (docs/RELEASING.md).
`CLAUDE.md` is the short guide for AI assistants; `docs/ARCHITECTURE.md` has the
Mac + Windows plan.

## What you need

- A Mac with macOS 14 Sonoma or newer.
- Apple's Command Line Tools. If they're missing, the scripts pop up a window
  offering to install them: click **Install**, wait, then run the script again.

## Try a change on your own Mac

1. Edit the Swift files in the `SpiderNotch` folder with any code editor
   (VS Code, Xcode, or TextEdit in plain-text mode).
2. In Terminal, run:

   ```
   bash ~/SpiderNotch/"Install SpiderNotch.command"
   ```

   It builds the app, puts it in Applications and opens it.
3. If the build fails, the full error messages are in `build.log`.

Prefer Xcode? Open `SpiderNotch.xcodeproj` and press **⌘R**. After adding or
removing files, rebuild the project with `python3 tools/make_xcodeproj.py .`
(or add them in Xcode with File → Add Files…). The scripts pick up every `.swift`
file in the `SpiderNotch` folder by themselves.

## Share a new version

Releases are published automatically by GitHub Actions, and installed copies
update themselves (Sparkle). The full routine is in
[docs/RELEASING.md](docs/RELEASING.md). In short:

1. Test your change with the installer (above) and `bash scripts/test.sh`.
2. In `CHANGELOG.md`, turn `## Unreleased` into `## 1.4.0 (date)`.
3. `bash scripts/bump-version.sh 1.4.0`
4. `git add -A && git commit -m "Release 1.4.0" && git push`

`Make Release.command` still makes all the release files on your Mac (in
`dist/`), if you want to share a build without GitHub.

| File | What it's for |
|---|---|
| `SpiderNotch-<version>.dmg` | What people download: open it, drag to Applications |
| `SpiderNotch-<version>.zip` | The update Sparkle installs (EdDSA-signed) |
| `appcast.xml` | The update feed installed copies check |
| `SpiderNotch-<version>-source.zip` | The code (local builds only; GitHub adds its own) |
| `How to Install SpiderNotch.txt` | Steps for new users (also inside the .dmg) |
| `SHA256SUMS.txt` | Fingerprints, to check the files weren't changed |

Signing and notarization (no "Open Anyway" step, US$99/year) are set up as
GitHub secrets: see docs/RELEASING.md. On your own Mac, `Make Release.command`
also finds a Developer ID in your Keychain and a saved notarization login
(`xcrun notarytool store-credentials SpiderNotch …`) by itself.

## Add characters to the library

The library isn't a fixed list in the code. The app reads
`SpiderNotch/Resources/Characters/Library.json` and shows every character listed
there, grouped by category. Each character is one PNG "strip": its faces side by
side, in the order given under `"faces"` (normally open, blink, happy, all the
same size).

- **Draw them like the built-in ones**: `tools/character-art/make_characters.py`
  draws every built-in animal from code. Copy one of the functions (say `fox`),
  change it, give it a new `@character("id", "Name", "category")`, then run
  `python3 tools/character-art/make_characters.py SpiderNotch/Resources/Characters --preview sheet.png`.
  It needs Pillow and rsvg-convert (`pip3 install pillow`, `brew install librsvg`).
- **Or use your own pictures**: put `myanimal.png` (a strip) in
  `Resources/Characters` and add a line to `Library.json`:
  `{"id": "myanimal", "name": "My Animal", "category": "pets", "image": "myanimal.png", "faces": ["open", "blink", "happy"]}`.
  A single picture works too: `"faces": ["open"]` (it won't blink).
- **Character packs** (no rebuild needed): a folder with its own `Library.json`
  and pictures in `~/Library/Application Support/SpiderNotch/Character Packs/`
  shows up after reopening Settings.

Draw characters without a white edge: the app adds the sticker edge itself
(Settings → Appearance → Border). Characters with blink/happy faces blink and
smile; photo stickers never get fake expressions.

## How Now Playing works

Apps share what they play in different ways, so SpiderNotch uses several sources
(see `MediaCenter.swift`):

| Source | What it gives | Permission |
|---|---|---|
| System Now Playing (`SystemNowPlaying.swift` + `MediaHelper/`) | Whatever Control Center shows: Music, Spotify, Safari, Chrome, Edge, Brave, Firefox, Podcasts, VLC… with play/pause/next/previous/seek | None |
| Music and Spotify broadcasts (`MediaSources.swift`) | Their current track, even when another app is in Control Center | None |
| AppleScript to Music / Spotify | Controls, artwork, showing the track | “Control Music/Spotify” (asked once) |
| AppleScript to Safari / Chromium browsers | The tab that's playing (title, address), bringing it forward | “Control Safari/Chrome” (asked once) |
| JavaScript in a browser tab | The page's video/audio, for tabs Control Center isn't showing | The browser's “Allow JavaScript from Apple Events” option |

Apple's public `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` only let an
app publish and control its *own* playback, so they can't be used to read other
apps. The system-wide information comes from Apple's private MediaRemote
framework, which since macOS 15.4 only answers Apple's own programs; the helper
therefore runs inside Apple's `/usr/bin/perl` (the same approach as the
open-source mediaremote-adapter project). If a future macOS stops that, the
Settings → Now Playing page says so, and Music, Spotify and browser tabs keep
working through their own integrations. Accessibility (screen reading) and a
browser extension aren't needed.

macOS remembers the Automation permissions per app signature: after you rebuild
SpiderNotch on your own Mac (ad-hoc signed), it may ask again.

## Things to know when changing the code

- **Tests:** `bash scripts/test.sh` runs everything CI runs. Swift tests are in
  `Tests/SpiderNotchTests.swift` (a small runner, no Xcode needed).
- **Updates:** `Updater.swift` wraps Sparkle, which `scripts/fetch-sparkle.sh`
  downloads into `vendor/` (checked by its SHA-256). The feed address and public
  key come from `scripts/release.conf`; never change them after release.
- **Build settings:** Swift 5 language mode, macOS 14 minimum, compiled by
  `scripts/common.sh`. New `.swift` files in `SpiderNotch/` are included
  automatically, and new pictures go in `SpiderNotch/Resources/`.
- **No SwiftUI macros without Xcode:** on macOS 27, SwiftUI's `@State` is a
  macro, and macros need the full Xcode app. Use `@AppStorage` for saved
  settings and an `ObservableObject` with `@Published` + `@ObservedObject` for
  everything else (those are not macros). Avoid `@State`, `#Preview`,
  `@Observable`, `@Entry` and `@Animatable` unless you build with Xcode.
- **Photos are never distorted:** stickers made from photos (`isPhoto`) only move,
  turn and scale evenly (see `SpiderStageView.swift`). Keep it that way.
- **Async gotcha:** inside `Task { … }` some Apple calls switch to an "async"
  version. If you see "expression is 'async' but is not marked with 'await'",
  move that call into a normal function and call the function instead.
- **Clicks:** the character's window lets clicks pass through, except while the
  cursor is right on it (`NotchController.setStickerClickable`). The island's
  window sits one level above it, so the character hangs below the island.
- **Switching apps** uses macOS 14 "cooperative activation", with a Dock-style
  fallback (`RunningApps.activate`).
- **Keep the bundle identifier** (`com.huang.SpiderNotch` in `Info.plist`) the
  same in every version. Otherwise macOS treats it as a different app, and
  settings and Launch at Login don't carry over.
