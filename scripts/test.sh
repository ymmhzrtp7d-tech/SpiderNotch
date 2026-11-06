#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  Runs every automatic check. Used by GitHub Actions on every push, and
#  safe to run on your Mac:   bash scripts/test.sh
#
#   1. Info.plist, entitlements and Library.json are valid
#   2. The shell scripts parse (and pass shellcheck, if it's installed)
#   3. Python tests: release tools, changelog, character library, no secrets
#   4. Swift unit tests (Tests/SpiderNotchTests.swift) compiled with the app code
# ────────────────────────────────────────────────────────────────────
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
FAILED=0
section() { printf "\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n" "$1"; }
bad() { printf "\033[1;31m✗ %s\033[0m\n" "$1"; FAILED=1; }

section "Property lists and data files"
for f in SpiderNotch/Info.plist SpiderNotch/SpiderNotch.entitlements; do
  plutil -lint "$f" || bad "$f"
done
python3 -m json.tool SpiderNotch/Resources/Characters/Library.json >/dev/null && echo "Library.json: OK" || bad "Library.json"

section "Shell scripts"
for f in scripts/*.sh "Install SpiderNotch.command" "Make Release.command"; do
  bash -n "$f" || bad "$f doesn't parse"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x scripts/*.sh "Install SpiderNotch.command" "Make Release.command" || bad "shellcheck"
else
  echo "(shellcheck not installed; skipped)"
fi
echo "Scripts: OK"

section "Python tests"
python3 -m unittest discover -s Tests -p 'test_*.py' -v 2>&1 | tail -n 15 || bad "Python tests"

section "Swift unit tests"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p build/tests
APP_SOURCES=()
for f in SpiderNotch/*.swift; do
  # The updater needs Sparkle, which the tests don't link.
  [ "$(basename "$f")" = "Updater.swift" ] && continue
  APP_SOURCES+=("$f")
done
cat > build/tests/UpdaterStub.swift <<'SWIFT'
import Foundation
@MainActor final class Updater: ObservableObject {
    static let shared = Updater()
    @Published var isAvailable = false
    @Published var canCheckForUpdates = false
    @Published var lastCheck: Date?
    var automaticallyChecks = false
    var automaticallyDownloads = false
    func start() {}
    func checkForUpdates() {}
}
SWIFT
if xcrun swiftc -swift-version 5 -parse-as-library -suppress-warnings -D SPIDERNOTCH_TESTS \
     -module-name SpiderNotch -target "$(uname -m)-apple-macos14.0" -sdk "$SDK" \
     -o build/tests/SpiderNotchTests "${APP_SOURCES[@]}" build/tests/UpdaterStub.swift Tests/SpiderNotchTests.swift; then
  build/tests/SpiderNotchTests || bad "Swift unit tests"
else
  bad "Swift unit tests didn't compile"
fi

if [ "$FAILED" -ne 0 ]; then
  printf "\n\033[1;31mSome checks failed.\033[0m\n"
  exit 1
fi
printf "\n\033[1;32mAll checks passed.\033[0m\n"
