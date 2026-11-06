# Privacy

*Last updated: 6 November 2026*

SpiderNotch is a small app that runs entirely on your Mac. In short: **no
account, no ads, no analytics, no tracking.**

## What stays on your Mac

- **Your photos and stickers.** Saved only in
  `~/Library/Application Support/SpiderNotch`. Background removal and face
  centring use Apple's Vision framework on your Mac. Nothing is uploaded.
- **Your settings.** Saved in macOS's preferences for `com.huang.SpiderNotch`.
- **What you're playing.** SpiderNotch reads the title, artist and artwork of
  what's playing to show it in the island. This is never stored or sent
  anywhere.
- **Your open apps.** The app switcher reads the list of running apps from
  macOS. It's never stored or sent anywhere.

## What uses the internet

| What | Sent to | What they can see |
|---|---|---|
| Update checks (once a day, or when you click *Check for Updates…*) | GitHub (github.com and its download servers) | Your IP address, the file requested, and SpiderNotch's version in the user agent. Sparkle's optional "system profile" is **off** |
| Downloading an update | GitHub | The same |
| Album covers and video thumbnails for what's playing | Apple (Music artwork), YouTube (thumbnails), or the address the playing app provides | Your IP address and which picture was requested |

You can turn off automatic update checks in **Settings → Updates**.

## Permissions SpiderNotch may ask for

- **Automation** ("SpiderNotch wants to control Music/Spotify/Safari/Chrome…"):
  only to play/pause/skip and to find the tab or track that's playing. You can
  change this any time in System Settings → Privacy & Security → Automation.
- **Photos** (only when you choose *From Photos* in My Stickers): to pick the
  one photo you choose.
- **Login Items** (only if you turn on *Launch at login*).

## Contact

Questions? [Open an issue](https://github.com/ymmhzrtp7d-tech/SpiderNotch/issues).
SpiderNotch is open source, so anyone can check exactly what it does.
