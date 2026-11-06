#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  Builds the Now Playing helper (SpiderNotchMedia.dylib) from
#  SpiderNotch/MediaHelper/SpiderNotchMedia.m.
#
#  Usage: build-media-helper.sh OUTPUT_FOLDER [ARCH ...]
#  Used by scripts/common.sh and by the Xcode project. You don't run it yourself.
#  Written for the bash that comes with macOS (version 3.2).
# ────────────────────────────────────────────────────────────────────

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER_SOURCE="$HERE/../SpiderNotch/MediaHelper/SpiderNotchMedia.m"
OUT_DIR="$1"
if [ -z "$OUT_DIR" ]; then
  echo "Usage: build-media-helper.sh OUTPUT_FOLDER [ARCH ...]" >&2
  exit 2
fi
shift

ARCH_FLAGS=()
for arch in "$@"; do
  ARCH_FLAGS+=(-arch "$arch")
done
if [ "${#ARCH_FLAGS[@]}" -eq 0 ]; then
  ARCH_FLAGS=(-arch "$(uname -m)")
fi

SDK_PATH="${SDK:-}"
if [ -z "$SDK_PATH" ]; then
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)" || exit 1
fi

mkdir -p "$OUT_DIR" || exit 1
xcrun clang -dynamiclib -fobjc-arc -O2 -Wall \
  "${ARCH_FLAGS[@]}" \
  -mmacosx-version-min=14.0 \
  -isysroot "$SDK_PATH" \
  -framework Foundation \
  -install_name @rpath/SpiderNotchMedia.dylib \
  -o "$OUT_DIR/SpiderNotchMedia.dylib" \
  "$HELPER_SOURCE" || exit 1
# Sign it for this Mac (Make Release signs it again with your Developer ID, if you have one).
codesign --force --sign - --timestamp=none "$OUT_DIR/SpiderNotchMedia.dylib" || exit 1
