#!/bin/bash
# ────────────────────────────────────────────────────────────────────
#  Prepares a new version:  bash scripts/bump-version.sh 1.3.0
#
#  1. Checks CHANGELOG.md already has a "## 1.3.0 (date)" section
#  2. Writes 1.3.0 into VERSION
#  3. Runs all the tests
#  Then commit and push to main: GitHub Actions builds and publishes the
#  release, and everyone's SpiderNotch offers the update.
# ────────────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")/.."
NEW="${1:?Usage: bump-version.sh NEW_VERSION   (like 1.3.0 or 1.3.0-beta.1)}"
OLD="$(tr -d ' \r\n' < VERSION)"
python3 scripts/release_tools.py check-version "$NEW"
printf '%s\n' "$NEW" > VERSION
echo "VERSION: $OLD → $NEW"
bash scripts/test.sh
cat <<MSG

Ready. To publish SpiderNotch $NEW:
  git add -A && git commit -m "Release $NEW" && git push
GitHub Actions will build, sign and publish it (Actions tab shows progress).
MSG
