# CLAUDE.md: guide for AI assistants

This file tells Claude (and any other AI assistant or new developer) how to work
on SpiderNotch safely. Read it before changing anything.

## What this is

SpiderNotch is a native macOS menu-bar app (Swift 5 mode, AppKit + SwiftUI,
macOS 14+, universal arm64 + x86_64). A character hangs from the notch; clicking
opens an island with an app switcher; while media plays the island shows Now
Playing. It's distributed as a DMG on GitHub Releases and updates itself with
Sparkle 2. The owner builds with **only the Command Line Tools** (no Xcode).

## Golden rules

1. **Don't break existing features.** Hover/drop animation, click → island app
   switcher, Now Playing (all sources), characters, photo stickers, settings,
   launch at login, updates. Change only what the task needs; no drive-by
   refactors or renames.
2. **Never change** the bundle id `com.huang.SpiderNotch`, the `Preferences.Key`
   strings, the Application Support layout, `SUFeedURL`/`FEED_URL`, or
   `SPARKLE_PUBLIC_KEY`. Installed copies depend on them (settings would be
   lost or updates would stop).
3. **No SwiftUI macros**: no `@State`, `@Observable`, `#Preview`, `@Entry`,
   `@Animatable`. They need Xcode's macro plugins. Use `@AppStorage`,
   `ObservableObject` + `@Published` + `@ObservedObject`, and `Binding(get:set:)`.
4. **Never commit secrets** (keys, certificates, passwords, `.p12`, `.env`).
   The tests scan for private keys. The Sparkle private key lives only in the
   Keychain and the `SPARKLE_PRIVATE_KEY` GitHub secret.
5. **Photos are never distorted**: stickers with `isPhoto` only move, rotate and
   scale uniformly (see `SpiderStageView.swift`).
6. Shell scripts must run on macOS's bash 3.2 (no `mapfile`, no `${x,,}`, guard
   empty arrays).
7. Ask the owner before publishing a release, pushing, or anything outward-facing.

## Commands

```bash
bash scripts/test.sh                  # all checks (plist/JSON lint, shell parse, Python + Swift tests)
bash scripts/build.sh arm64 x86_64    # build build/SpiderNotch.app (universal), no install
bash scripts/smoke-test.sh build/SpiderNotch.app   # launches it for 8 s
bash "Install SpiderNotch.command"    # build for this Mac, install to /Applications, open
bash "Make Release.command"           # full release files into dist/ (local)
bash scripts/bump-version.sh X.Y.Z    # set a new version (needs a CHANGELOG section)
```

Build errors go to `build.log` (full compiler output). Read it when a build fails.

## Map of the code

| Area | Files |
|---|---|
| Startup, menu bar menu | `SpiderNotchApp.swift`, `MenuBarIcon.swift` |
| Notch detection, window, mouse | `NotchGeometry.swift`, `NotchPanel.swift`, `MouseWatcher.swift` |
| Orchestration (hover, click, island, media) | `NotchController.swift` |
| Animation | `StageLayout.swift` (pure math), `SpiderStageView.swift` (Core Animation) |
| Characters | `CharacterLibrary.swift` + `Resources/Characters/Library.json` and PNG strips |
| Stickers | `StickerStore.swift`, `StickerArt.swift`, `PhotoEditor.swift`, `PhotoSticker.swift`, `PhotoImporter.swift` |
| Island | `IslandController.swift`, `IslandView.swift`, `IslandPanel.swift`, `AppSwitcherView.swift`, `RunningApps.swift`, `NowPlayingView.swift` |
| Now Playing | `MediaCenter.swift` (merges sources), `MediaSources.swift`, `SystemNowPlaying.swift` + `MediaHelper/` (private MediaRemote via `/usr/bin/perl`), `ScriptRunner.swift`, `SystemVolume.swift` |
| Settings window | `SettingsWindow.swift` (window, sidebar, General, `Alerts`), `SettingsSections.swift` (Characters, Stickers, Appearance, Now Playing), `AboutSections.swift` (Updates, About) |
| Saved settings, app facts, links | `Preferences.swift` (`Preferences`, `SpiderSettings`, `LoginItem`, `AppInfo`) |
| Updates | `Updater.swift` (Sparkle wrapper; compiles without Sparkle via `#if canImport(Sparkle)`) |
| Tests | `Tests/SpiderNotchTests.swift` (Swift, no XCTest), `Tests/test_release_tools.py` |
| Build & release | `scripts/common.sh` (shared build steps), `scripts/release.conf`, `scripts/fetch-sparkle.sh`, `Make Release.command`, `scripts/release_tools.py` |
| CI/CD | `.github/workflows/ci.yml` (every push), `.github/workflows/release.yml` (when `VERSION` changes on main) |

Every `.swift` file in `SpiderNotch/` is compiled automatically by the scripts.
After adding or removing files, optionally regenerate the Xcode project with
`python3 tools/make_xcodeproj.py .` (Xcode isn't required).

## Adding a feature (checklist)

1. Read the files in the area you're touching, and DEVELOPING.md.
2. Put new code in a new file when it's a new feature; keep edits to existing
   files small. New settings: add a key + default in `Preferences.swift`
   (`Key`, `Default`, `registerDefaults`) and a control in the Settings section.
3. If it has logic that can be tested without the screen, add a test in
   `Tests/SpiderNotchTests.swift` (add it to `all`).
4. `bash scripts/test.sh` must pass. Then `bash scripts/build.sh arm64 x86_64`
   and `bash scripts/smoke-test.sh build/SpiderNotch.app`.
5. Ask the owner to try it (`Install SpiderNotch.command`) for anything visual.
6. Add a user-facing line under `## Unreleased` in `CHANGELOG.md`.

## Releasing (when the owner asks)

Follow [docs/RELEASING.md](docs/RELEASING.md): turn `## Unreleased` into
`## X.Y.Z (date)` (add a new empty Unreleased), `bash scripts/bump-version.sh
X.Y.Z`, commit, and (with the owner's OK) push to `main`. The Release workflow
tests, builds, signs, and publishes; installed apps then update via Sparkle.
Use `-beta.N` versions for test releases (published as pre-releases, not offered
to everyone).

## Known constraints

- Now Playing relies on Apple's private MediaRemote through a perl-hosted
  helper; macOS updates may break it. The app then falls back to Music/Spotify/
  browser integrations. Don't remove the fallbacks.
- Not App Store compatible (private framework). Distribution is Developer ID or
  ad-hoc signing + GitHub Releases.
- Without a Developer ID, builds are ad-hoc signed: first launch needs *Open
  Anyway*, and Automation permissions may be asked again after updates.
- Windows: planned as a separate native app sharing data files
  (docs/ARCHITECTURE.md). The CI has a disabled Windows job
  (`vars.ENABLE_WINDOWS`). Keep shared data (characters, Library.json,
  CHANGELOG) platform-neutral.
