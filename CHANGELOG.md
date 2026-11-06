# Changelog

What changed in each version of SpiderNotch. The newest version is at the top.

How to use this file (see docs/RELEASING.md): add changes to **Unreleased** as
you make them. When you release, rename it to `## X.Y.Z (date)` and start a new
empty Unreleased section. The release workflow publishes the matching section as
the release notes and as the "What's new" text in the update window.

## Unreleased

## 1.4.0 (6 November 2026)

- **The island is always there for you.** Hovering the notch now always opens
  the island, even when nothing is playing and Music, Spotify and your browsers
  are closed. Before, it only appeared while music or a video played. Media
  controls are now an extra: when something plays, the island opens on Now
  Playing with a tab for your files, and when it stops, the island switches to
  your files instead of going empty.
- **Cocoon, your file hub in the notch.** Drag files from Finder onto the notch
  and drop them on **Keep** (recent files), **Pin** (stays for good) or
  **AirDrop**. Open, preview (Quick Look), reveal in Finder, copy, pin, AirDrop
  or remove them from the island. Use **Add Files…** to pick files, and
  **AirDrop…** works even with nothing selected: choose a file and the standard
  AirDrop window opens. Your files never move: the Cocoon only keeps a link.
  Settings → Cocoon: how long recent files stay, and Downloads.
- **Screens without a notch** (external displays, a closed lid) show a small
  handle at the top of the screen, so you always know where to hover.
- **Update Center** in Settings: your version, the newest version, what's new
  and the release history. When an update is out, a small card in the corner
  and a dot on the menu bar spider tell you, with **Update Now** and **Remind Me
  Later**. After updating, a "What's new" card shows the changes. Updates keep
  your settings, stickers and Cocoon files.

## 1.3.0 (6 November 2026)

- **Automatic updates**: SpiderNotch now checks for new versions once a day
  (or choose **Check for Updates…** in the spider menu), shows what's new, and
  installs the update with one click. Every update is verified with
  SpiderNotch's signing key before it's installed. Your settings, characters
  and stickers are kept.
- **Settings → Updates**: check now, see when it last checked, and choose
  whether updates are checked and installed automatically.
- **Settings → About**: version, links to the source code, bug reports,
  feature requests, help and the privacy policy.
- SpiderNotch is now open source (MIT licence) on GitHub, with downloads on
  GitHub Releases.

## 1.2.0 (6 November 2026)

- **Character library**: 46 cute characters in 8 categories (Pets, Farm, Forest,
  Jungle & Savanna, Water & Ice, Night & Spooky, Dinos & Fantasy, and the classic
  spider). Cats, dogs, bats, cows, rabbits, pandas, frogs, ducks, bears, penguins,
  hamsters, foxes, lions, tigers, monkeys, elephants, deer, koalas, chickens,
  dinosaurs and many more, each with real blinking and smiling faces. New
  characters can be added without changing the code (see DEVELOPING.md).
- **My Stickers**: turn any photo into a round sticker (from Photos, the Desktop,
  Downloads, any file, or by dropping it on the window; PNG, JPEG, HEIC, WebP).
  Crop the face, zoom, move, size the circle, remove the background (on this Mac),
  pick a background colour and a ring, preview it at a pretend notch, save as
  many as you like, rename, edit, delete. Photos are never stretched or given
  fake expressions: they float, bounce and swing.
- **Appearance**: animation speed, three entrance styles (drop on a thread, peek
  out, pop & float), floating movement, sticker edge (white, outline, glow or
  none) and position (left, centre or right of the notch).
- **Now Playing**: when music or a video plays, hovering the notch opens a Dynamic
  Island with the artwork or video thumbnail, title, artist or channel, the app or
  website, a progress bar you can drag, play/pause, previous, next and volume.
  Works with Music, Spotify, Safari, Chrome, Edge, Brave, YouTube, YouTube Music
  and any app that tells macOS what it's playing. Click the song or video to jump
  to it (the exact browser tab, the Spotify track, the Music track). Little app
  icons switch between several things that play. Click your character to get the
  app switcher.
- Settings has a new look with a sidebar. The menu bar menu has Characters… and
  My Stickers….
- Your custom sticker from 1.1 moves to My Stickers by itself.

## 1.1.0 (5 November 2026)

- Click the spider to open the **Dynamic Island app switcher**: it springs out
  of the notch with a live list of your open apps (real icons, names on hover),
  highlights the app you're using, and switches app with one click.
  Esc, a click outside, or moving the mouse away closes it. ← → and Return work
  too, and the row scrolls sideways when lots of apps are open.
- The spider blinks and flashes a big smile while he hangs, and does a happy
  hop when you click him.
- Your own sticker can blink and smile too: add `name-blink.png` and
  `name-happy.png` next to it.
- Builds for both Apple silicon and Intel Macs, with a one-step release script
  for sharing the app.

## 1.0.0 (5 November 2026)

- First version: hover over the notch and the spider drops down on his web,
  bounces, swings gently, and climbs back when you move away.
- Menu bar icon with Enabled, Drop the Spider Now, Settings and Quit.
- Settings for size, web length, swing, bounciness, launch at login and a
  custom sticker picture.
