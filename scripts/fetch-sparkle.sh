#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  Downloads the Sparkle update framework into vendor/Sparkle-<version>/
#  (once), checking its SHA-256 fingerprint. Prints the folder on success.
#  Used by scripts/common.sh. vendor/ is not stored in Git.
# ────────────────────────────────────────────────────────────────────
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=release.conf
source "$HERE/release.conf"

DEST="$ROOT/vendor/Sparkle-$SPARKLE_VERSION"
if [ -d "$DEST/Sparkle.framework" ] && [ -x "$DEST/bin/sign_update" ]; then
  echo "$DEST"
  exit 0
fi

mkdir -p "$ROOT/vendor"
ARCHIVE="$ROOT/vendor/Sparkle-$SPARKLE_VERSION.tar.xz"
if [ ! -f "$ARCHIVE" ]; then
  curl -fsSL --retry 3 -o "$ARCHIVE.part" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" >&2
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL" != "$SPARKLE_SHA256" ]; then
  echo "Sparkle download doesn't match its fingerprint ($ACTUAL)." >&2
  rm -f "$ARCHIVE"
  exit 1
fi
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xJf "$ARCHIVE" -C "$DEST" >&2
echo "$DEST"
