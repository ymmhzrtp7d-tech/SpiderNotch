#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  SpiderNotch: make files you can send to other people.
#
#  Creates a folder dist/SpiderNotch-<version>/ with:
#    SpiderNotch-<version>.dmg          send this one (drag-to-install)
#    SpiderNotch-<version>.zip          the same app, zipped (handy for email)
#    SpiderNotch-<version>-source.zip   the code, for anyone who wants to develop it
#    How to Install SpiderNotch.txt     instructions for the people you send it to
#    Message to send.txt                a ready-to-paste message
#    SHA256SUMS.txt                     fingerprints to check the files weren't changed
#    appcast.xml                        the update feed (when the update key is available)
#
#  GitHub Actions runs this same script to publish releases
#  (.github/workflows/release.yml), with CI=true.
#
#  The app works on both Apple silicon and Intel Macs with macOS 14 or newer.
#  The version number comes from the VERSION file.
# ────────────────────────────────────────────────────────────────────

set -o pipefail

cd "$(dirname "$0")" || exit 1
PROJECT_DIR="$(pwd)"
SOURCE_DIR="$PROJECT_DIR/SpiderNotch"
BUILD_DIR="$PROJECT_DIR/build/release"
LOG="$PROJECT_DIR/build.log"

# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh" || { echo "The scripts folder is missing."; exit 1; }

if [ "$(uname)" != "Darwin" ]; then
  echo "This only runs on a Mac."
  exit 1
fi

start_log "release"
setup_toolchain
read_version
setup_sparkle
note "Making SpiderNotch $VERSION"
mkdir -p "$BUILD_DIR" || fail "Couldn't create the build folder."

# ── 1. Build for Apple silicon and Intel Macs ───────────────────────
build_app arm64 x86_64

# ── 2. Sign (and notarize, if you've set that up) ───────────────────
IDENTITY="$(find_developer_id)"
NOTARIZED="no"
if [ -n "$IDENTITY" ]; then
  step "Signing with your Developer ID…"
  note "$IDENTITY"
  sign_app "$IDENTITY"
  if notary_ready; then
    step "Sending the app to Apple to be notarized (usually a few minutes)…"
    rm -f "$BUILD_DIR/notarize.zip"
    ditto -c -k --keepParent "$APP" "$BUILD_DIR/notarize.zip" >> "$LOG" 2>&1 \
      || fail "Couldn't prepare the app for notarization."
    if notarize "$BUILD_DIR/notarize.zip" && xcrun stapler staple "$APP" >> "$LOG" 2>&1; then
      NOTARIZED="yes"
      note "Apple approved it: people can open it without any warning."
    else
      note "Notarization didn't go through (details in build.log)."
      note "The files still work; people just need the one-time \"Open Anyway\" step."
    fi
  else
    note "Tip: set up notarization (see DEVELOPING.md) so nobody sees a warning."
  fi
else
  step "Signing…"
  sign_app "-"
  note "No Developer ID on this Mac, so people approve SpiderNotch once in"
  note "System Settings → Privacy & Security. The instructions explain how."
fi

# ── 3. Instructions for the people you send it to ───────────────────
OUT="$PROJECT_DIR/dist/$APP_NAME-$VERSION"
DMG_NAME="$APP_NAME-$VERSION.dmg"
ZIP_NAME="$APP_NAME-$VERSION.zip"
SOURCE_NAME="$APP_NAME-$VERSION-source.zip"
GUIDE_NAME="How to Install SpiderNotch.txt"
rm -rf "$OUT"
mkdir -p "$OUT" || fail "Couldn't create the dist folder."

write_install_guide() {
  {
    echo "SpiderNotch $VERSION: how to install"
    echo "===================================="
    echo
    echo "SpiderNotch puts a cute character in your MacBook's notch: a spider, one of"
    echo "45 other animals, or a sticker made from your own photo. Hover over the notch"
    echo "and it drops down on its thread. Click it and a Dynamic Island pops out to"
    echo "switch between your open apps. While music or a video plays, hovering the"
    echo "notch shows what's playing, with controls."
    echo
    echo "You need macOS 14 Sonoma or newer ($MAC_KINDS)."
    echo "No notch on your screen? A small pretend notch appears at the top instead."
    echo
    echo "1. Open $DMG_NAME."
    echo "2. Drag SpiderNotch onto the Applications folder in that window."
    echo "3. Open your Applications folder and double-click SpiderNotch."
    if [ "$NOTARIZED" = "yes" ]; then
      echo "4. Look for the little spider in your menu bar, then move your mouse"
      echo "   up to the notch and say hi."
    else
      cat <<'GUIDE'
4. The first time, macOS says it "could not verify" SpiderNotch. That's
   only because it doesn't come from the App Store. To allow it (just once):
   - Click Done.
   - Open the Apple menu > System Settings > Privacy & Security.
   - Scroll down to "Security". Next to the message about SpiderNotch,
     click "Open Anyway", then confirm with your password or Touch ID.
   - Click "Open Anyway" once more in the box that appears.
5. Look for the little spider in your menu bar, then move your mouse
   up to the notch and say hi.
GUIDE
    fi
    cat <<'GUIDE'

Tips
- Click the character to open the app switcher. Esc or a click outside closes it.
- Pick another animal, or make a sticker from your own photo: spider menu in the
  menu bar > Characters... or My Stickers... Your photos stay on your Mac.
- Settings > Appearance: size, speed, how it comes out, floating, border, position.
- Now Playing: the first time you control Music or Spotify, or click a video to
  jump to its browser tab, macOS asks "SpiderNotch wants to control ...":
  click Allow.
- Updating: SpiderNotch checks for new versions by itself once a day, or choose
  Check for Updates... from the spider menu. Your settings and stickers are kept.
- Uninstalling: choose Quit from the spider menu, then drag SpiderNotch
  from Applications to the Trash.
GUIDE
  } > "$1"
}

# Each paragraph is one long line, so it pastes nicely into Messages or an email.
write_message() {
  {
    echo "Hi! I made a little Mac app called SpiderNotch: a cute character lives in your MacBook's notch (a spider, lots of other animals, or a sticker of your own photo). Hover over the notch and it drops down on its thread; click it and a Dynamic Island pops out to switch between your open apps. When music or a video plays, hovering the notch shows what's playing, with controls."
    echo
    echo "To install: open $DMG_NAME, drag SpiderNotch into Applications, then open it from Applications. It needs macOS 14 or newer ($MAC_KINDS)."
    if [ "$NOTARIZED" != "yes" ]; then
      echo
      echo "The first time, your Mac will say it can't verify the app (it's not from the App Store). Click Done, open System Settings > Privacy & Security, and click \"Open Anyway\" next to SpiderNotch. You only do that once."
    fi
  } > "$1"
}

write_install_guide "$OUT/$GUIDE_NAME"
write_message "$OUT/Message to send.txt"

# ── 4. The disk image (.dmg) ────────────────────────────────────────
step "Making the disk image…"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE" || fail "Couldn't create the disk image folder."
ditto "$APP" "$STAGE/$APP_NAME.app" || fail "Couldn't copy the app into the disk image."
ln -s /Applications "$STAGE/Applications"
cp "$OUT/$GUIDE_NAME" "$STAGE/$GUIDE_NAME"
# hdiutil sometimes says "Resource busy" for no good reason, so it gets a few tries.
DMG_MADE="no"
for attempt in 1 2 3; do
  if hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
       -ov "$OUT/$DMG_NAME" >> "$LOG" 2>&1; then
    DMG_MADE="yes"
    break
  fi
  echo "hdiutil try $attempt didn't work, trying again…" >> "$LOG"
  sleep 3
done
[ "$DMG_MADE" = "yes" ] || fail "Couldn't create the disk image."
if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$OUT/$DMG_NAME" >> "$LOG" 2>&1 \
    || fail "Couldn't sign the disk image."
  if [ "$NOTARIZED" = "yes" ]; then
    step "Notarizing the disk image too…"
    if notarize "$OUT/$DMG_NAME" && xcrun stapler staple "$OUT/$DMG_NAME" >> "$LOG" 2>&1; then
      note "Done."
    else
      note "The disk image wasn't notarized (the app inside still is)."
    fi
  fi
fi

# ── 5. The zipped app and the source code ───────────────────────────
step "Zipping the app…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP_NAME" >> "$LOG" 2>&1 \
  || fail "Couldn't zip the app."

# GitHub adds its own source downloads to every release, so CI skips this.
if [ "${CI:-}" != "true" ]; then
  step "Packing up the source code…"
  PARENT_DIR="$(dirname "$PROJECT_DIR")"
  FOLDER="$(basename "$PROJECT_DIR")"
  (
    cd "$PARENT_DIR" && zip -qrX "$OUT/$SOURCE_NAME" "$FOLDER" \
      -x "$FOLDER/build/*" "$FOLDER/dist/*" "$FOLDER/vendor/*" "$FOLDER/build.log" "$FOLDER/.git/*" \
         "*.DS_Store" "*/xcuserdata/*"
  ) >> "$LOG" 2>&1 || fail "Couldn't zip the source code."
fi

# ── 6. Update signature and feed (appcast.xml) ──────────────────────
# Sparkle installs the .zip. It must carry an EdDSA signature made with the
# private update key: from the SPARKLE_PRIVATE_KEY secret on GitHub Actions,
# or from this Mac's Keychain.
APPCAST_MADE="no"
if [ -n "$SPARKLE_DIR" ]; then
  step "Signing the update…"
  SIGN_UPDATE="$SPARKLE_DIR/bin/sign_update"
  SIGNATURE=""
  KEY_ARGS=()
  KEY_FILE=""
  if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    KEY_FILE="$(mktemp)"
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
    KEY_ARGS=(--ed-key-file "$KEY_FILE")
  fi
  SIGNATURE="$("$SIGN_UPDATE" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} -p "$OUT/$ZIP_NAME" 2>> "$LOG")"
  if [ -n "$SIGNATURE" ]; then
    # Check it the way Sparkle will: against the public key built into the app.
    xcrun swift "$PROJECT_DIR/scripts/verify_update_signature.swift" "$OUT/$ZIP_NAME" "$SIGNATURE" "$SPARKLE_PUBLIC_KEY" >> "$LOG" 2>&1 \
      || { rm -f "$KEY_FILE"; fail "The update signature doesn't match SPARKLE_PUBLIC_KEY in scripts/release.conf (wrong key?)."; }
  fi
  rm -f "$KEY_FILE"
  if [ -n "$SIGNATURE" ]; then
    LENGTH="$(stat -f%z "$OUT/$ZIP_NAME")"
    python3 "$PROJECT_DIR/scripts/release_tools.py" appcast \
      --version "$VERSION" --build "$BUILD_NUMBER" \
      --url "https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$ZIP_NAME" \
      --length "$LENGTH" --signature "$SIGNATURE" --min-macos "$MIN_MACOS" \
      --link "https://github.com/$GITHUB_REPO/releases/tag/v$VERSION" \
      --out "$OUT/appcast.xml" >> "$LOG" 2>&1 || fail "Couldn't write appcast.xml."
    APPCAST_MADE="yes"
    note "Signed. appcast.xml is ready."
  else
    note "No update signing key found, so no appcast.xml (people can still download the .dmg)."
  fi
fi
if [ "${REQUIRE_UPDATE_SIGNATURE:-no}" = "yes" ] && [ "$APPCAST_MADE" != "yes" ]; then
  fail "The update couldn't be signed. Add the SPARKLE_PRIVATE_KEY secret (see docs/RELEASING.md)."
fi

# ── 7. Checksums ────────────────────────────────────────────────────
(
  cd "$OUT" && shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt \
    && if [ -f "$SOURCE_NAME" ]; then shasum -a 256 "$SOURCE_NAME" >> SHA256SUMS.txt; fi
) || fail "Couldn't write the checksums."
echo "Release files in: $OUT" >> "$LOG"
# Tell GitHub Actions where the files are.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "dir=$OUT"
    echo "version=$VERSION"
    echo "notarized=$NOTARIZED"
  } >> "$GITHUB_OUTPUT"
fi
[ "${CI:-}" = "true" ] && exit 0

open "$OUT"
printf "\n\033[1;32mDone!\033[0m SpiderNotch %s is ready to share. A Finder window shows:\n\n" "$VERSION"
printf "   %-34s %s\n" "$DMG_NAME" "send this to people"
printf "   %-34s %s\n" "$ZIP_NAME" "the same app, zipped"
printf "   %-34s %s\n" "$SOURCE_NAME" "the code, for other developers"
printf "   %-34s %s\n" "$GUIDE_NAME" "steps for the people you send it to"
printf "   %-34s %s\n\n" "Message to send.txt" "copy and paste when you share it"
printf "The files are in: %s\n\n" "$OUT"
