#!/usr/bin/env bash
# Package build/WriterFlow.app into a drag-to-Applications DMG.
#
# For an actual release, run scripts/release.sh first so the app inside the DMG is
# signed and notarized — an ad-hoc-signed DMG (plain `make bundle`) is fine for local
# testing but Gatekeeper will refuse it on another Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/WriterFlow.app"
[[ -d "$APP" ]] || { echo "✗ $APP not found — run 'make bundle' (or scripts/release.sh) first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG_NAME="WriterFlow-${VERSION}.dmg"
STAGING="build/dmg-staging"

echo "▸ Staging DMG contents"
rm -rf "$STAGING" "build/${DMG_NAME}"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▸ Creating ${DMG_NAME}"
hdiutil create -volname "WriterFlow" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "build/${DMG_NAME}"

rm -rf "$STAGING"
echo "▸ Built build/${DMG_NAME}"
echo "  Double-click it locally to confirm the drag-to-Applications window looks right."
