# Contributing to SpiderNotch

Thanks for wanting to help! Bug reports, ideas, new characters, fixes and
documentation are all welcome.

## Reporting bugs and ideas

- **Bugs:** use the [bug report form](https://github.com/ymmhzrtp7d-tech/SpiderNotch/issues/new?template=bug_report.yml).
  Include your SpiderNotch version, macOS version and Mac (Apple silicon or Intel).
- **Ideas:** use the [feature request form](https://github.com/ymmhzrtp7d-tech/SpiderNotch/issues/new?template=feature_request.yml).
- **Security problems:** privately, see [SECURITY.md](SECURITY.md).

## Setting up

You need macOS 14+ and Apple's Command Line Tools (`xcode-select --install`).
Xcode is optional.

```bash
git clone https://github.com/ymmhzrtp7d-tech/SpiderNotch.git
cd SpiderNotch
bash "Install SpiderNotch.command"   # build, install, open
bash scripts/test.sh                 # all the checks CI runs
```

Read [DEVELOPING.md](DEVELOPING.md) for how the code is organised and the
gotchas (for example: don't use SwiftUI's `@State`, because the project builds
without Xcode's macro plugins).

## Making a change

1. Fork the repository and create a branch: `git checkout -b fix-swing-speed`.
2. Keep changes focused. Don't reformat or rename code you're not changing.
3. Keep existing features working: hover, click → island, Now Playing,
   characters, stickers, settings. Settings keys in `Preferences.swift` and the
   bundle identifier `com.huang.SpiderNotch` must never change (people's saved
   settings depend on them).
4. Add or update tests in `Tests/` when you change logic.
5. Run `bash scripts/test.sh` and try the app with `Install SpiderNotch.command`.
6. If users will notice the change, add a line under `## Unreleased` in
   [CHANGELOG.md](CHANGELOG.md).
7. Open a pull request. GitHub Actions builds and tests it automatically.

## Adding characters

See "Add characters to the library" in [DEVELOPING.md](DEVELOPING.md). Characters
must be original art (no copyrighted characters, logos or mascots).

## Code style

- Swift 5 language mode, AppKit + SwiftUI, macOS 14 minimum.
- One type or feature per file; a short comment at the top says what it's for.
- Comments explain *why*, in plain words.
- Shell scripts work with the bash 3.2 that ships with macOS.

## Licence

By contributing, you agree that your contributions are licensed under the
[MIT licence](LICENSE).
