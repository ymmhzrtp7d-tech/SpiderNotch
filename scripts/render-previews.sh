#!/bin/bash
# Draws the island, Cocoon and update screens into PNGs (no display needed),
# using a throwaway data folder so your own Cocoon and stickers are never touched.
# Usage: bash scripts/render-previews.sh OUTPUT_FOLDER
set -e
cd "$(dirname "$0")/.."
OUT="${1:?Usage: render-previews.sh OUTPUT_FOLDER}"
mkdir -p "$OUT" build/previews
DATA="$(mktemp -d)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -parse-as-library -suppress-warnings -D SPIDERNOTCH_TESTS \
  -module-name SpiderNotch -target "$(uname -m)-apple-macos14.0" -sdk "$SDK" \
  -o build/previews/RenderPreviews SpiderNotch/*.swift Tests/RenderPreviews.swift
build/previews/RenderPreviews -SpiderNotchSupportFolder "$DATA" "$OUT"
rm -rf "$DATA"
