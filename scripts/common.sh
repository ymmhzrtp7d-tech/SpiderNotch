# shellcheck shell=bash
# ────────────────────────────────────────────────────────────────────
#  Shared build steps for SpiderNotch.
#  Used by "Install SpiderNotch.command" and "Make Release.command".
#  You don't run this file yourself.
#
#  Written for the bash that comes with macOS (version 3.2), so it avoids
#  newer bash features on purpose.
# ────────────────────────────────────────────────────────────────────

APP_NAME="SpiderNotch"
MIN_MACOS="14.0"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

# Repository, update feed and the public update key (see scripts/release.conf).
# shellcheck source=release.conf
source "$PROJECT_DIR/scripts/release.conf"
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  # On GitHub Actions: use whichever repository is building.
  GITHUB_REPO="$GITHUB_REPOSITORY"
  FEED_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml"
fi
SPARKLE_DIR=""

step() { printf "\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n" "$1"; }
note() { printf "   %s\n" "$1"; }
fail() {
  printf "\n\033[1;31mSomething went wrong:\033[0m %s\n" "$1"
  printf "Details were saved to: %s\n\n" "$LOG"
  exit 1
}

# Starts a fresh build.log.
start_log() {
  : > "$LOG"
  echo "SpiderNotch $1 — $(date)" >> "$LOG"
  sw_vers >> "$LOG" 2>&1
}

# Reads the version (like 1.1.0) from the VERSION file. The build number is
# the date and time, so every build gets a bigger number than the last.
read_version() {
  VERSION="$(tr -d ' \r\n' < "$PROJECT_DIR/VERSION" 2>/dev/null)"
  if [ -z "$VERSION" ]; then
    VERSION="1.0.0"
  fi
  # GitHub Actions passes its own BUILD_NUMBER so every file of one release agrees.
  BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
  echo "Version $VERSION (build $BUILD_NUMBER)" >> "$LOG"
}

# Finds Apple's Swift compiler (from the Command Line Tools or Xcode).
setup_toolchain() {
  step "Checking for Apple's developer tools…"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    printf "\nA window should have opened asking to install the \"Command Line Developer Tools\".\n"
    printf "Click Install, wait for it to finish, then run this again.\n\n"
    exit 1
  fi
  # If the selected tools don't work (for example an Xcode that hasn't been
  # opened yet), fall back to the Command Line Tools.
  if ! xcrun swiftc --version >> "$LOG" 2>&1; then
    if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
      export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    fi
  fi
  xcrun swiftc --version >> "$LOG" 2>&1 \
    || fail "Swift isn't ready yet. If you installed Xcode, open it once and click Agree, then try again."
  SDK="$(xcrun --sdk macosx --show-sdk-path 2>> "$LOG")" || fail "Couldn't find the macOS SDK."
  echo "Using SDK: $SDK" >> "$LOG"
  note "Swift: $(xcrun swiftc --version 2>/dev/null | head -n 1)"
}

# Gets the Sparkle update framework (downloaded once into vendor/).
# Without it the app still builds; it just can't update itself.
setup_sparkle() {
  step "Getting the Sparkle update framework…"
  if SPARKLE_DIR="$(bash "$PROJECT_DIR/scripts/fetch-sparkle.sh" 2>> "$LOG")"; then
    note "Sparkle $SPARKLE_VERSION"
  else
    SPARKLE_DIR=""
    if [ "${REQUIRE_SPARKLE:-no}" = "yes" ]; then
      fail "Couldn't download Sparkle, which releases need. Check the internet connection."
    fi
    note "Couldn't download Sparkle (offline?). Building without automatic updates."
  fi
}

arch_label() {
  case "$1" in
    arm64) echo "Apple silicon" ;;
    x86_64) echo "Intel" ;;
    *) echo "$1" ;;
  esac
}

# compile_for ARCH OUTPUT: compiles every Swift file for one kind of Mac.
compile_for() {
  local -a extra
  extra=()
  if [ -n "$SPARKLE_DIR" ]; then
    extra=(-F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
  fi
  xcrun swiftc \
    -O -whole-module-optimization \
    -swift-version 5 \
    -parse-as-library \
    -suppress-warnings \
    -module-name "$APP_NAME" \
    -target "$1-apple-macos$MIN_MACOS" \
    -sdk "$SDK" \
    -o "$2" \
    ${extra[@]+"${extra[@]}"} \
    "$SOURCE_DIR"/*.swift 2>&1 | tee -a "$LOG"
}

# build_app ARCH [ARCH…]: builds build/SpiderNotch.app.
# With "arm64 x86_64" the app runs on both Apple silicon and Intel Macs.
build_app() {
  APP="$BUILD_DIR/$APP_NAME.app"
  local slices_dir="$BUILD_DIR/slices"
  local native
  native="$(uname -m)"
  rm -rf "$APP" "$slices_dir"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$slices_dir"

  local arch
  local -a built
  local -a built_archs
  built=()
  built_archs=()
  for arch in "$@"; do
    step "Building for $(arch_label "$arch") Macs (about a minute)…"
    if compile_for "$arch" "$slices_dir/$APP_NAME-$arch"; then
      built+=("$slices_dir/$APP_NAME-$arch")
      built_archs+=("$arch")
    elif [ "$arch" = "$native" ] || [ "$#" -eq 1 ]; then
      fail "The code didn't compile. Tell Claude \"the build failed\" and it will read build.log and fix it."
    else
      note "Skipping $(arch_label "$arch") Macs (that part didn't compile)."
    fi
  done

  # Combine the versions into one app ("universal") when there's more than one.
  # MAC_KINDS says which Macs it runs on; "Make Release.command" uses it.
  # shellcheck disable=SC2034
  if [ "${#built[@]}" -gt 1 ]; then
    lipo -create "${built[@]}" -output "$APP/Contents/MacOS/$APP_NAME" >> "$LOG" 2>&1 \
      || fail "Couldn't combine the Apple silicon and Intel versions."
    MAC_KINDS="Apple silicon or Intel Mac"
  else
    cp "${built[0]}" "$APP/Contents/MacOS/$APP_NAME" || fail "Couldn't copy the app."
    MAC_KINDS="$(arch_label "${built[0]##*-}") Mac"
  fi
  lipo -info "$APP/Contents/MacOS/$APP_NAME" >> "$LOG" 2>&1

  step "Packaging the app…"
  cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist" || fail "Couldn't copy Info.plist."
  # The pictures, including the Characters folder (the animal library).
  ditto "$SOURCE_DIR/Resources" "$APP/Contents/Resources" >> "$LOG" 2>&1 || fail "Couldn't copy the pictures."
  cp "$SOURCE_DIR/MediaHelper/now-playing.pl" "$APP/Contents/Resources/now-playing.pl" \
    || fail "Couldn't copy the Now Playing helper."
  # This version's notes from CHANGELOG.md, for the "What's new" card after an update.
  python3 "$PROJECT_DIR/scripts/release_tools.py" notes "$VERSION" > "$APP/Contents/Resources/WhatsNew.md" 2>> "$LOG" \
    || rm -f "$APP/Contents/Resources/WhatsNew.md"
  printf 'APPL????' > "$APP/Contents/PkgInfo"
  "$PLISTBUDDY" -c "Set :CFBundleShortVersionString $VERSION" \
                -c "Set :CFBundleVersion $BUILD_NUMBER" \
                "$APP/Contents/Info.plist" >> "$LOG" 2>&1 \
    || fail "Couldn't write the version number into the app."
  "$PLISTBUDDY" -c "Add :SpiderNotchRepository string $GITHUB_REPO" "$APP/Contents/Info.plist" >> "$LOG" 2>&1 \
    || fail "Couldn't write the repository into the app."
  if [ -n "$SPARKLE_DIR" ]; then
    "$PLISTBUDDY" -c "Add :SUFeedURL string $FEED_URL" \
                  -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" \
                  -c "Add :SUEnableAutomaticChecks bool true" \
                  -c "Add :SUScheduledCheckInterval integer 86400" \
                  -c "Add :SUAllowsAutomaticUpdates bool true" \
                  "$APP/Contents/Info.plist" >> "$LOG" 2>&1 \
      || fail "Couldn't write the update settings into the app."
    mkdir -p "$APP/Contents/Frameworks"
    ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework" >> "$LOG" 2>&1 \
      || fail "Couldn't copy Sparkle into the app."
    # SpiderNotch isn't sandboxed, so Sparkle's XPC services aren't needed.
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
           "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
  fi
  build_media_helper "${built_archs[@]}"
  # Remove download "quarantine" tags and Finder extras: they stop code signing.
  xattr -cr "$APP" 2>> "$LOG"
}

# build_media_helper ARCH…: the small helper that reads the system Now Playing
# (see SpiderNotch/MediaHelper). If it doesn't build, the app still works: Now
# Playing then uses its Music, Spotify and browser integrations only.
build_media_helper() {
  step "Building the Now Playing helper…"
  local frameworks="$APP/Contents/Frameworks"
  HELPER_BUILT="no"
  if SDK="$SDK" bash "$PROJECT_DIR/scripts/build-media-helper.sh" "$frameworks" "$@" >> "$LOG" 2>&1; then
    HELPER_BUILT="yes"
  elif [ "$#" -gt 1 ] && SDK="$SDK" bash "$PROJECT_DIR/scripts/build-media-helper.sh" "$frameworks" "$(uname -m)" >> "$LOG" 2>&1; then
    HELPER_BUILT="yes"
    note "(The Now Playing helper was built for this kind of Mac only.)"
  fi
  if [ "$HELPER_BUILT" != "yes" ]; then
    rm -f "$frameworks/SpiderNotchMedia.dylib"
    note "The Now Playing helper didn't build (details in build.log). Everything else works,"
    note "and Now Playing still works with Music, Spotify and browser tabs."
  fi
}

# sign_app IDENTITY: "-" signs for your own Mac; a "Developer ID Application"
# identity signs it so it can be notarized by Apple for other people.
sign_app() {
  local entitlements="$SOURCE_DIR/SpiderNotch.entitlements"
  local helper="$APP/Contents/Frameworks/SpiderNotchMedia.dylib"
  sign_sparkle "$1"
  if [ "$1" = "-" ]; then
    if [ -f "$helper" ]; then
      codesign --force --sign - --timestamp=none "$helper" >> "$LOG" 2>&1 \
        || fail "Couldn't sign the Now Playing helper."
    fi
    codesign --force --sign - --timestamp=none --entitlements "$entitlements" "$APP" >> "$LOG" 2>&1 \
      || fail "Couldn't sign the app."
  else
    # Everything inside the app is signed first, then the app itself.
    if [ -f "$helper" ]; then
      codesign --force --options runtime --timestamp --sign "$1" "$helper" >> "$LOG" 2>&1 \
        || fail "Couldn't sign the Now Playing helper with \"$1\"."
    fi
    codesign --force --options runtime --timestamp --entitlements "$entitlements" --sign "$1" "$APP" >> "$LOG" 2>&1 \
      || fail "Couldn't sign the app with \"$1\"."
  fi
  codesign --verify --strict "$APP" >> "$LOG" 2>&1 || fail "The app's signature didn't check out."
}

# sign_sparkle IDENTITY: signs Sparkle's pieces inside-out (Sparkle's own advice).
sign_sparkle() {
  local fw="$APP/Contents/Frameworks/Sparkle.framework"
  [ -d "$fw" ] || return 0
  local -a flags
  if [ "$1" = "-" ]; then
    flags=(--force --sign - --timestamp=none)
  else
    flags=(--force --options runtime --timestamp --sign "$1")
  fi
  local part
  for part in "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do
    codesign "${flags[@]}" "$part" >> "$LOG" 2>&1 || fail "Couldn't sign Sparkle ($part)."
  done
}

# Prints your "Developer ID Application" signing identity, if you have one.
find_developer_id() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }'
}

# The name of the saved notarization login (see DEVELOPING.md).
NOTARY_PROFILE="${NOTARY_PROFILE:-SpiderNotch}"

# On GitHub Actions the login comes from secrets instead:
# NOTARY_APPLE_ID, NOTARY_PASSWORD (app-specific password) and NOTARY_TEAM_ID.
notary_ready() {
  xcrun --find notarytool >/dev/null 2>&1 || return 1
  if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
    return 0
  fi
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}

# notarize FILE: sends a .zip or .dmg to Apple and waits for the result.
notarize() {
  if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
    xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
      --team-id "$NOTARY_TEAM_ID" --wait >> "$LOG" 2>&1
  else
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait >> "$LOG" 2>&1
  fi
}
