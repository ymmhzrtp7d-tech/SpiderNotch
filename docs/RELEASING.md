# Releasing a new version

Releases are automatic. You (or Claude) change the code, raise the version,
describe the change, and push. GitHub Actions does the rest, and every
installed SpiderNotch offers the update within a day.

## The routine

1. Make and test the change (`bash "Install SpiderNotch.command"`,
   `bash scripts/test.sh`).
2. In `CHANGELOG.md`, rename `## Unreleased` to `## 1.4.0 (7 December 2026)`
   (your new version and today's date), make sure it lists what changed in
   plain words, and add a fresh empty `## Unreleased` above it.
3. Run:

   ```bash
   bash scripts/bump-version.sh 1.4.0
   ```

   It checks the changelog, writes `VERSION`, and runs all the tests.
4. Commit and push to `main`:

   ```bash
   git add -A && git commit -m "Release 1.4.0" && git push
   ```

5. Watch the **Actions** tab on GitHub. The **Release** workflow:
   - runs the tests again (a failing test stops the release),
   - builds the universal app (Apple silicon + Intel),
   - signs it (Developer ID if configured, otherwise ad-hoc) and notarizes it
     (if configured),
   - makes the `.dmg` and the update `.zip`,
   - signs the `.zip` with the Sparkle update key and writes `appcast.xml`,
   - checks that the app launches,
   - publishes GitHub Release `v1.4.0` with the notes from `CHANGELOG.md`.
6. Done. Installed copies check `releases/latest/download/appcast.xml` once a
   day and offer the update.

Choosing the number (semantic versioning):

| Change | Example |
|---|---|
| Bug fixes only | 1.3.0 → 1.3.1 |
| New features | 1.3.0 → 1.4.0 |
| Big changes or something removed | 1.3.0 → 2.0.0 |
| Test version for volunteers | 1.4.0-beta.1 (published as a pre-release: NOT offered to everyone) |

You can also start a release by hand: GitHub → Actions → Release → *Run
workflow*. If a release for the current `VERSION` already exists, it does
nothing.

## If a release is bad

Updaters only move forward. Fix the problem (or revert the change) and publish
a higher version, such as `1.4.1`. To stop more people getting the bad version
in the meantime, delete its GitHub Release (the tag can stay): the update feed
then points at the previous release again.

## One-time setup

### The update signing key (required)

Sparkle refuses updates that aren't signed with the key whose public half is
in the app (`SPARKLE_PUBLIC_KEY` in `scripts/release.conf`). The private half:

- lives in the login Keychain of the Mac where it was created (Keychain Access
  → search "Sparkle"), and
- must be added to GitHub as the secret **`SPARKLE_PRIVATE_KEY`**:

  ```bash
  vendor/Sparkle-2.10.1/bin/generate_keys -x /tmp/sparkle-key.txt
  gh secret set SPARKLE_PRIVATE_KEY < /tmp/sparkle-key.txt
  rm -P /tmp/sparkle-key.txt
  ```

**Back it up** in a password manager. If it's lost, already installed copies
can't verify new updates and everyone has to download the next version by hand.
Never commit it, paste it in chats, or email it.

### Developer ID signing and notarization (optional, US$99/year)

Without it, people click *Open Anyway* once (see TROUBLESHOOTING.md), and
macOS may ask again for Automation permissions after updates. With it, there
are no warnings.

1. Join the Apple Developer Program (developer.apple.com/programs).
2. Create a **Developer ID Application** certificate and export it from
   Keychain Access as a `.p12` with a strong password.
3. Create an app-specific password at account.apple.com (Sign-In and Security).
4. Add these GitHub secrets (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `MACOS_CERTIFICATE_P12` | `base64 -i DeveloperID.p12 \| pbcopy`, then paste |
   | `MACOS_CERTIFICATE_PASSWORD` | the `.p12` password |
   | `NOTARY_APPLE_ID` | your Apple Account email |
   | `NOTARY_PASSWORD` | the app-specific password |
   | `NOTARY_TEAM_ID` | your 10-character Team ID (developer.apple.com → Membership) |

5. Delete the `.p12` file from your disk (keep it in the password manager).

The next release is signed and notarized automatically. Switching from ad-hoc
to Developer ID is safe for updates because Sparkle checks the EdDSA signature.

### Making releases on your Mac instead

`bash "Make Release.command"` builds the same files into `dist/` using the
signing key from your Keychain (and your Developer ID, if you have one). Upload
them to a GitHub Release by hand, including `appcast.xml`.

## Files involved

| File | Role |
|---|---|
| `VERSION` | The version number (the only place to change it) |
| `CHANGELOG.md` | Release notes; the matching section is published |
| `scripts/release.conf` | Repository, update feed address, public key, Sparkle version |
| `scripts/bump-version.sh` | Checks and sets the new version, runs tests |
| `Make Release.command` | Builds, signs, notarizes, packages, writes `appcast.xml` |
| `scripts/release_tools.py` | Changelog extraction and appcast writing |
| `.github/workflows/release.yml` | Runs all of the above on GitHub and publishes |
| `SpiderNotch/Updater.swift` | The in-app updater (Sparkle) |
