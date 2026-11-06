#!/bin/bash
# Starts the built app for a few seconds and checks it doesn't crash on launch.
# Usage: scripts/smoke-test.sh path/to/SpiderNotch.app
APP="${1:?Usage: smoke-test.sh path/to/SpiderNotch.app}"
BIN="$APP/Contents/MacOS/SpiderNotch"
[ -x "$BIN" ] || { echo "No app at $APP"; exit 1; }
codesign --verify --deep --strict "$APP" || { echo "Signature check failed"; exit 1; }
"$BIN" > "${TMPDIR:-/tmp}/spidernotch-smoke.log" 2>&1 &
PID=$!
sleep 8
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "Smoke test passed: SpiderNotch started and kept running."
else
  wait "$PID"
  echo "SpiderNotch quit or crashed on launch (exit $?). Its output:"
  cat "${TMPDIR:-/tmp}/spidernotch-smoke.log"
  exit 1
fi
