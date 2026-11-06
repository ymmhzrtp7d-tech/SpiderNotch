# Installing and troubleshooting SpiderNotch

## Installing

1. Download `SpiderNotch-<version>.dmg` from
   [the latest release](https://github.com/ymmhzrtp7d-tech/SpiderNotch/releases/latest).
2. Open it and drag **SpiderNotch** onto **Applications**.
3. Open **Applications** and double-click **SpiderNotch**.
4. Look for the little spider in the menu bar, then move the mouse to the notch.

## "SpiderNotch could not be verified" / "Apple could not verify…"

SpiderNotch doesn't come from the App Store, so macOS asks you to allow it once:

1. Click **Done** (not *Move to Trash*).
2. Open  **→ System Settings → Privacy & Security**.
3. Scroll down to **Security**. Next to the message about SpiderNotch, click
   **Open Anyway**, then confirm with your password or Touch ID.
4. Click **Open Anyway** once more.

You only do this once. Updates installed by SpiderNotch itself don't ask again.

## I don't see the spider in the menu bar

- If your menu bar is full, macOS hides icons behind the notch. Quit an app
  with a menu bar icon, or hold ⌘ and drag icons to rearrange them.
- On macOS 26 and newer: System Settings → Menu Bar → make sure SpiderNotch is
  allowed to show.
- Check SpiderNotch is running: open Activity Monitor and search "SpiderNotch".

## Nothing happens when I hover the notch

- Spider menu → make sure **Enabled** is ticked.
- Using an external display or the lid is closed? Settings → General → turn on
  **Show on screens without a notch**.
- Try spider menu → **Say Hi Now**.

## Now Playing doesn't show my music or video

- Settings → Now Playing shows what SpiderNotch can see and what's missing.
- When macOS asks *"SpiderNotch wants to control Music/Spotify/Safari…"*, click
  **Allow**. Said no by mistake? System Settings → Privacy & Security →
  **Automation** → SpiderNotch → turn the app on.
- For browser videos in tabs Control Center doesn't show, the browser needs
  *View → Developer → Allow JavaScript from Apple Events* (Safari: Settings →
  Advanced → Show features for web developers, then Develop menu).
- After an update of an app that isn't signed with a Developer ID, macOS may ask
  for the Automation permissions again. Click Allow once more.

## Updates

- Spider menu → **Check for Updates…**, or Settings → Updates.
- "You're up to date" but GitHub shows a newer version? Pre-releases (versions
  like `1.4.0-beta.1`) aren't offered automatically; download them by hand.
- An update failed? Download the newest `.dmg` from
  [Releases](https://github.com/ymmhzrtp7d-tech/SpiderNotch/releases/latest) and
  drag it into Applications, choosing **Replace**. Settings and stickers are kept.

## Launch at login doesn't stick

Settings → General → turn on **Launch at login**. If macOS asks, allow
SpiderNotch in System Settings → General → **Login Items & Extensions**.

## Reset everything

Quit SpiderNotch, then in Terminal:

```bash
defaults delete com.huang.SpiderNotch
```

To also delete your stickers: remove `~/Library/Application Support/SpiderNotch`.

## Still stuck?

[Report a bug](https://github.com/ymmhzrtp7d-tech/SpiderNotch/issues/new?template=bug_report.yml)
with your SpiderNotch version, macOS version and what you tried.
