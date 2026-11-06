#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  SpiderNotch installer (for THIS Mac)
#
#  Builds the app from the Swift code in this folder, signs it for this
#  Mac, puts it in your Applications folder and opens it.
#  Safe to run again any time, for example after you change the code.
#
#  To make files you can send to other people, use "Make Release.command".
# ────────────────────────────────────────────────────────────────────

set -o pipefail

cd "$(dirname "$0")" || exit 1
PROJECT_DIR="$(pwd)"
SOURCE_DIR="$PROJECT_DIR/SpiderNotch"
BUILD_DIR="$PROJECT_DIR/build"
LOG="$PROJECT_DIR/build.log"

# shellcheck source=scripts/common.sh
source "$PROJECT_DIR/scripts/common.sh" || { echo "The scripts folder is missing."; exit 1; }

if [ "$(uname)" != "Darwin" ]; then
  echo "This installer only runs on a Mac."
  exit 1
fi

start_log "install"
setup_toolchain
read_version
setup_sparkle
build_app "$(uname -m)"

step "Signing it for this Mac…"
sign_app "-"

# ── Install and open ────────────────────────────────────────────────
step "Installing into your Applications folder…"
pkill -x "$APP_NAME" >/dev/null 2>&1 && sleep 1

INSTALLED=""
install_into() {
  mkdir -p "$1" 2>> "$LOG" || return 1
  rm -rf "${1:?}/$APP_NAME.app" 2>> "$LOG" || return 1
  ditto "$APP" "$1/$APP_NAME.app" 2>> "$LOG" || return 1
  INSTALLED="$1/$APP_NAME.app"
}
install_into "/Applications" || {
  note "(Couldn't write to /Applications, so using your personal Applications folder.)"
  install_into "$HOME/Applications"
} || fail "Couldn't copy the app into Applications."
echo "Installed to: $INSTALLED" >> "$LOG"

step "Opening SpiderNotch…"
open "$INSTALLED" || fail "The app was installed at $INSTALLED but didn't open."

printf "\n\033[1;32mAll done!\033[0m SpiderNotch %s is installed at:\n   %s\n\n" "$VERSION" "$INSTALLED"
printf "Look for the little spider icon in your menu bar, then move your\n"
printf "mouse up to the notch and say hi. You can close this window now.\n\n"
