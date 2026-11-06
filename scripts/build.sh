#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  Builds build/SpiderNotch.app without installing it.
#  Used by GitHub Actions (CI) and handy for a quick compile check.
#
#  Usage: scripts/build.sh [ARCH ...]     (default: arm64 x86_64 = universal)
# ────────────────────────────────────────────────────────────────────
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
PROJECT_DIR="$(pwd)"
SOURCE_DIR="$PROJECT_DIR/SpiderNotch"
BUILD_DIR="$PROJECT_DIR/build"
LOG="$PROJECT_DIR/build.log"
# shellcheck source=common.sh
source "$PROJECT_DIR/scripts/common.sh" || exit 1

start_log "build"
setup_toolchain
read_version
setup_sparkle
if [ "$#" -eq 0 ]; then
  set -- arm64 x86_64
fi
build_app "$@"
for arch in "$@"; do
  lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch "$arch" 2>/dev/null \
    || fail "The app wasn't built for $(arch_label "$arch") Macs."
done
sign_app "-"
step "Built $APP ($VERSION, build $BUILD_NUMBER)"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
