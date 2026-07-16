#!/usr/bin/env bash
# Package build/WriterFlow.app into a drag-to-Applications DMG.
#
# The v1 plan calls for an ad-hoc-signed Release bundle; no Apple membership is
# required. This script accepts whatever bundle already exists and does not verify that
# requirement. Gatekeeper blocks normal first launch on another Mac, so users must follow
# Apple's System Settings → Privacy & Security → Open Anyway flow. This script does not
# validate build freshness/configuration, version, architectures, secrets, licenses, or
# produce a checksum; complete every check in RELEASE.md before public upload.
#
# V2 may run scripts/release.sh first for Developer ID signing/notarization.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/WriterFlow.app"
[[ -d "$APP" ]] || { echo "✗ $APP not found — run 'CONFIG=release make bundle' first (see RELEASE.md)" >&2; exit 1; }

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
