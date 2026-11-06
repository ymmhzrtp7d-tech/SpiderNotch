# SpiderNotch on Mac and Windows: the plan

*Status (6 November 2026, version 1.3.0): Phase 1 is done (code on GitHub,
CI on every push) and the Mac half of Phase 2/3 is done: Sparkle updates,
Settings → Updates and About, automatic GitHub Releases. Developer ID signing
and notarization are wired up and turn on when the secrets are added
(docs/RELEASING.md). The Windows app and the website are not built yet.*

*One change from the plan below: the Mac update feed is `appcast.xml`
attached to each GitHub Release, read from
`https://github.com/<owner>/SpiderNotch/releases/latest/download/appcast.xml`,
so no website is needed for updates. Releases are signed on GitHub Actions with
the `SPARKLE_PRIVATE_KEY` secret (so pushing a version publishes it), rather
than only on your Mac.*

This explains how SpiderNotch can become a Mac **and** Windows app, with a website
and automatic updates, without making the Mac version any worse. The companion
guide, [PUBLISHING-GUIDE.md](PUBLISHING-GUIDE.md), explains the accounts,
signing and publishing steps for a beginner.

## 1. The decision

**Two native apps that share one "core" of data, art and rules.**

- **Mac:** the app you have now, in Swift with AppKit and Core Animation. It
  stays exactly as it is, so the notch keeps all of its polish.
- **Windows:** a new app in C# with .NET 10 and WPF, Microsoft's own tools for
  Windows desktop apps.
- **Shared by both:** the character library and its art, the sticker and
  settings formats, a behaviour spec (sizes, timings, states), the release
  notes, the update rules, the website and the release tools.

The shared part is files, not code, on purpose. Almost everything SpiderNotch
does (see-through windows over the notch, Core Animation springs, reading what's
playing, switching apps, permissions) works completely differently on each
system. The things that *are* the same (the characters, the sticker format, the
settings, what changed in each version) are content, and content is easy to
share as files.

## 2. The options I compared

| Option | How it works | Verdict |
|---|---|---|
| **Electron** | A web page running inside its own copy of Chrome | ✗ Ships a whole browser, so it uses far more memory and disk than a native app for a small overlay. The notch tricks would need native add-ons anyway. |
| **Tauri 2** | A web page in the system's web view, with Rust underneath | ✗ Lighter than Electron, but the notch panel, click-through, Now Playing and app switcher would all become native plugins. We'd rewrite a working Mac app and lose polish. |
| **Flutter, Avalonia, Qt, .NET MAUI** | One toolkit draws the same screens on both systems | ✗ None gives direct access to what makes the notch feel native (window levels above the menu bar, panels that don't steal focus, Core Animation). .NET MAUI runs on the Mac as a "Catalyst" app, which can't do menu-bar overlays. |
| **Swift on Windows** | Apple's Swift compiler also runs on Windows | ✗ Both apps could share Swift code, but Windows UI tools for Swift are young and hard to debug, especially for a beginner. |
| **Shared Rust or C++ library + native screens** | Logic written once, called from Swift and C# | ✗ Adds a third language and two bridges. SpiderNotch's truly shared logic is small. It can be added later if that changes. |
| **Native apps + shared data core** | Each app in its system's own language; data, art and rules shared as files | ✓ **Recommended.** Best quality on both systems, simplest to build and debug. |

The price of this choice is that each feature is programmed twice. The shared
core keeps that manageable: one source for the art, sizes, timings and texts,
shared test files, and a feature checklist so both apps stay in step.

### Why these Windows tools

- **WPF** (rather than WinUI 3 or Windows Forms): mature, well documented,
  smooth animations, and good at see-through, always-on-top windows, which is
  exactly what the island needs. WinUI 3 is newer but makes see-through overlay
  windows hard; Windows Forms is too limited for smooth animation.
- **C# and .NET 10**: Microsoft's main language for Windows apps. .NET 10 has
  long-term support until November 2028.
- **Win32 calls**: small calls straight into Windows for what WPF doesn't cover:
  not stealing focus, staying above other windows, monitor and display-scaling
  details, and the window list for the app switcher.
- **GSMTC** (Windows' "Global System Media Transport Controls"): Windows' own way
  to read and control what's playing, the same information Windows shows in its
  media pop-up.
- **Velopack**: open-source installer and updater for the direct download. No
  admin rights needed, and updates download only what changed.

## 3. How the pieces fit

```
                      shared/   (one source of truth)
       characters + art · sticker & settings formats · behaviour spec
           release notes · test files · website text and images
                   │                                   │
           copied in when building             copied in when building
                   ▼                                   ▼
   ┌───────────────────────────────┐   ┌───────────────────────────────┐
   │ SpiderNotch for Mac            │   │ SpiderNotch for Windows        │
   │ Swift · AppKit · Core Anim.    │   │ C# · .NET 10 · WPF · Win32     │
   │ notch, or island on Macs       │   │ floating island at the top     │
   │   without a notch              │   │   of the chosen monitor        │
   │ Now Playing: MediaRemote,      │   │ Now Playing: Windows media     │
   │   Music, Spotify, browsers     │   │   controls (GSMTC)             │
   │ updates: Sparkle               │   │ updates: Microsoft Store, or   │
   │                                │   │   Velopack (direct download)   │
   └───────────────────────────────┘   └───────────────────────────────┘
                   │                                   │
                   └─────────────────┬─────────────────┘
                                     ▼
        GitHub Releases: the download files (every version kept)
        GitHub Pages: the website + update feeds (small signed files)
```

## 4. The folder layout (set up in Phase 1)

```
SpiderNotch/
├── VERSION                       one version number for both apps
├── CHANGELOG.md                  made from shared/release-notes
├── Install SpiderNotch.command   unchanged: build and install on this Mac
├── Make Release.command          grows into the release tool
├── shared/
│   ├── characters/               Library.json + the 46 character pictures
│   ├── formats/                  how sticker folders, character packs,
│   │                             settings and update feeds are written
│   ├── spec/                     sizes, timings and behaviour both apps follow
│   ├── release-notes/            one file per version: the single source for
│   │                             every "what's new" text
│   └── test-data/                sample stickers, packs and feeds for tests
├── macos/                        the Mac app (today's SpiderNotch/ folder)
├── windows/                      the Windows app and its tests
├── website/                      the public website
├── tools/                        release tools: notes → feeds, website,
│                                 signing, rollback
├── docs/                         this plan and the publishing guide
└── .github/workflows/            automatic builds and tests on GitHub's
                                  Mac and Windows machines
```

The double-click scripts stay at the top, so building on your Mac works the
same as today.

## 5. Feature by feature

| Feature | Mac | Windows | What people will notice |
|---|---|---|---|
| Where it lives | The notch. Macs without one get a pretend notch today, to be polished into the same floating island as Windows | A floating island at the top of the screen: choose the monitor, left/centre/right and a fine offset; sharp at any display scaling | Windows has no notch, so the island floats |
| Characters | `Library.json` + picture strips | The same files | Same library, same character IDs |
| Animations | Core Animation springs | WPF animations tuned to the same spec | Should feel the same |
| Photo stickers | Apple Vision: background removal, face centring | Same editor and sticker format; background removal still to be decided (see Risks) | Stickers can move between Mac and Windows |
| App switcher | macOS's list of running apps | Windows' window list (like Alt+Tab) | Same idea, Windows style |
| Now Playing | MediaRemote helper + Music, Spotify and browser scripting | Windows media controls: Spotify, Chrome, Edge, Firefox (YouTube and other sites), Media Player and most modern apps | Windows brings the browser forward but can't open the exact tab |
| Volume | Core Audio | Windows Core Audio | Same |
| Settings | macOS preferences | A settings file in the user's folder | Same choices, same names |
| Your stickers and packs | `~/Library/Application Support/SpiderNotch` | `%AppData%\SpiderNotch` | Never touched by updates |
| The icon with the menu | Menu bar | System tray, next to the clock | Same menu |
| Updates | Sparkle | Microsoft Store, or Velopack for the direct download | Same update window and settings |
| Clock, file drop, productivity tools | — | — | **Not built yet on either system** (no spec yet) |

## 6. Automatic updates

### What people see (the same on both systems)

1. SpiderNotch checks quietly when it starts and once a day, or when you choose
   **Check for Updates…**.
2. When there's a new version: a small dot on the menu-bar or tray icon, a
   notification, and a window with the version, date and what's new:
   **Update Now**, **Remind Me Later**, **Skip This Version**.
3. It downloads with a progress bar. The signatures are checked, and anything
   that doesn't match is thrown away.
4. SpiderNotch quits, is replaced and reopens. Settings and stickers are stored
   outside the app, so they're never touched.
5. After the restart, a **What's New** window (can be turned off).

### Settings → Updates

- Check for updates automatically (on)
- Download and install automatically (off: ask first)
- Update channel: **Stable** or **Beta**
- Show What's New after updating (on)
- Notify me about new features (off until you turn it on)
- **Check Now**, and when it last checked

The What's New texts are built into each version of the app, so they work
offline and nothing is tracked.

### Mac: Sparkle

Sparkle is the open-source updater used by thousands of Mac apps (current
version 2.10.1). It checks, downloads, verifies, installs and relaunches. Every
update must carry two valid signatures: our own update key (EdDSA) and Apple's
Developer ID signature. Sparkle can also require the update feed itself to be
signed, which we'll turn on. Because SpiderNotch is a menu-bar app, it uses
Sparkle's "gentle reminders", so update alerts don't pop up out of nowhere or
hide behind other windows. Sparkle also handles beta channels, critical updates
and phased rollouts (a new version reaches people gradually over about a week).

### Windows: one update window, two ways to install

- **Microsoft Store version** (the main Windows download): the Store signs it and
  keeps it updated. Our update window asks the Store for updates through Windows'
  Store API, with the same buttons and progress bar. Stable channel only.
- **Direct download** (`SpiderNotch-Setup.exe`, for people who can't use the
  Store, and for beta testers): Velopack installs it without admin rights and
  updates it with small "delta" downloads. Velopack checks each download's size
  and hash against its feed but doesn't sign the feed, so we add our own signed
  list of files and hashes. The app refuses any update that doesn't match it.

### Channels

- **Stable**: everyone, by default.
- **Beta**: opt in from Settings. Betas have versions like `1.4.0-beta.1`.
- Leaving beta: you keep the beta until a stable version newer than it comes out.
  Updaters never install an older version, by design.

### Where the update files live

- Big files: GitHub Releases. Every version is kept, anyone can download, and
  there are no bandwidth bills.
- Small feed files the apps check: on the website (GitHub Pages), for example
  `…/updates/macos/appcast.xml`.
- **Important:** every copy of the app remembers its feed address forever, so we
  choose the web address (free `github.io` or your own domain) *before* the first
  public release with updates.

### The signing keys stay on your Mac

Sparkle's private key and the Windows feed key live in your Mac's Keychain.
GitHub's machines build and test; your Mac signs and publishes. So even someone
who broke into the GitHub account couldn't publish an update the apps would
accept.

## 7. Versions, history and rollback

- One `VERSION` for both apps, as MAJOR.MINOR.PATCH (`1.3.0`). Betas add
  `-beta.N`. The Mac build number stays a date and time, which always goes up.
- Every release gets one file in `shared/release-notes/`. That text becomes the
  Sparkle notes, the Windows notes, the website changelog, `CHANGELOG.md` and the
  in-app What's New.
- Every version stays on GitHub Releases with its checksums. That's the release
  history.
- If a release turns out bad:
  1. **Pull it** (one command): it's removed from the feeds and the website goes
     back to the previous version. Nobody else gets it.
  2. **Fix forward**: publish `1.3.1` with the fix, or with the previous good code
     under the new number. Updaters only move forward, so this is how people who
     already updated get back to a good version.
  3. **Limit the damage up front**: beta first, then a phased rollout on the Mac,
     and on Windows a rollout percentage in our signed feed.

## 8. Signing and trust

| | Mac | Windows: Store | Windows: direct download |
|---|---|---|---|
| Who signs | You, with an Apple **Developer ID** certificate | Microsoft, automatically | You, with a code-signing certificate (optional at first) |
| Extra check | **Notarization**: Apple scans it, then Macs open it without warnings | Store review (usually a few days) | None |
| Without it | People click "Open Anyway" in System Settings, and macOS asks again for permissions after every update | — | "Windows protected your PC": people click More info → Run anyway |
| Cost | US$99/year (Apple Developer Program) | Free for individual developers | Free if unsigned; about US$120–300+/year if signed |

The Mac version can't go in the Mac App Store: Now Playing uses a private Apple
framework, which the App Store doesn't allow. That's normal for notch utilities;
they're distributed directly, signed with Developer ID and notarized.

## 9. The website

Plain static pages (fast, free, nothing to hack), hosted on GitHub Pages:

- **Home**: what it is, a short looping video, download buttons that pick Mac or
  Windows, the latest version and its date
- **Features**, with screenshots
- **Download**: Mac (.dmg), Windows (Microsoft Store and direct installer),
  requirements, checksums, older versions
- **What's New**: the changelog, generated from the release notes
- **Help**: installing on Mac and Windows, troubleshooting (permissions, Now
  Playing, warnings), uninstalling
- **Privacy policy**
- **Support**: an email address, and GitHub Issues if the code is public

The download page reads a small `latest.json` that the release tool updates, so
the version shown is never out of date.

## 10. Privacy (the basis for the privacy policy)

- No account, no ads, no analytics, no tracking.
- Photos, stickers and what you're playing never leave the computer.
- Update checks contact GitHub (and Microsoft, for Store copies). They see your
  IP address and which file was requested, nothing else. Sparkle's optional
  "system profile" stays off.
- As today, album covers and YouTube thumbnails are downloaded for what's
  playing.

## 11. Risks and honest limits

- **Mac Now Playing** uses a private Apple framework through a helper. That's
  allowed outside the App Store, but a future macOS could break it. The app then
  falls back to its Music, Spotify and browser integrations (already built).
- **Windows Now Playing** only sees apps that report to Windows' media controls.
  Most do. Apps that don't are simply not shown: never fake information.
- **Background removal on Windows**: Windows has no built-in equivalent of Apple's
  Vision on every PC. Newer Copilot+ PCs have a built-in Windows AI feature for
  it; other PCs would need a bundled open-source model (a bigger download) or go
  without. To be decided in Phase 5.
- **Store app data**: Windows deletes a Store app's data when the app is
  uninstalled (updates keep it). The direct-download version keeps data in
  `%AppData%` even after uninstalling.
- **I can't run Windows in my workspace**, just as I can't run your Mac app.
  GitHub's Windows machines will compile it and run the automatic tests; you'll do
  the hands-on testing on a Windows PC, or in a Windows virtual machine on your
  Mac.
- **Names**: keep "SpiderNotch" and our own original spider. Don't use
  "Spider-Man" or Apple's term "Dynamic Island" in the app's name, the website or
  store listings. The website will just say "island".
- **Not built yet:** the clock, file-drop and productivity features mentioned in
  Feature 10 don't exist on either system. The layout leaves room for them; they
  need their own specs.
- **Windows 10** is out of Microsoft support since October 2025, but many people
  still use it, so we'll support version 1809 and newer (the media API we need
  exists there) as well as Windows 11.

## 12. The plan, one step at a time

Each phase ends with a short test list for you. The next phase starts only after
you've tried it and said OK.

| Phase | What we build | How you test it |
|---|---|---|
| **0. Done** | SpiderNotch 1.2.0 builds and installs on your Mac | Try the new characters, stickers and Now Playing |
| **1. Foundation** | Code on GitHub; folders reorganised as in section 4; automatic build checks on every change | Installing on your Mac works exactly as before |
| **2. Mac: trusted + self-updating** | Developer ID signing and notarization; Sparkle; Settings → Updates; What's New; beta switch | Install on a second user account (no warning); update from a test feed |
| **3. Website + release tool** | The website on GitHub Pages; one command that builds, signs, notarizes, uploads to GitHub Releases and updates the feed, changelog and website; a "pull" command for rollback | Publish `1.3.0-beta.1` to yourself, then `1.3.0`; practise a rollback |
| **4. Windows, part 1: the app** | Floating island, characters, animations, app switcher, Now Playing, settings, tray icon, several monitors and display scaling | Run GitHub's builds on a Windows PC or virtual machine |
| **5. Windows, part 2: shipping it** | Installer and updates (Velopack), Microsoft Store package and submission, signing, update window, What's New, photo stickers | Install from the Store and from the website; update both |
| **6. One release for both** | One release flow for Mac and Windows, beta → stable, phased rollout, rollback drill, website with both downloads, floating-island polish for Macs without a notch | A real public release |

Phases 2 and 3 make the Mac version ready for the public before any Windows work,
so you get a polished, self-updating Mac app first.
