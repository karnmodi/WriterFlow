#!/usr/bin/env bash
# Sign, notarize, and staple a Release build of WriterFlow.app.
#
# Requires a real paid Apple Developer Program membership + Developer ID Application
# certificate — there is no way around that, and this script deliberately fails fast
# with a clear message instead of silently skipping steps if the environment isn't set
# up for it. See README.md's "Releasing" section before running this.
#
# Required environment variables:
#   DEVELOPER_ID_APPLICATION     e.g. "Developer ID Application: Jane Doe (ABCDE12345)"
#   APPLE_ID                     Apple ID used for notarization
#   APPLE_TEAM_ID                10-character Team ID
#   APPLE_APP_SPECIFIC_PASSWORD  generated at https://appleid.apple.com (Security → App-Specific Passwords)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your \"Developer ID Application: Name (TEAMID)\" signing identity — see README.md}"
: "${APPLE_ID:?Set APPLE_ID to the Apple ID used for notarization}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your 10-character Team ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD — generate one at appleid.apple.com}"

echo "▸ Building release bundle"
scripts/bundle.sh release

APP="build/WriterFlow.app"
[[ -d "$APP" ]] || { echo "✗ $APP not found" >&2; exit 1; }

echo "▸ Codesigning with hardened runtime"
codesign --force --deep --options runtime \
    --entitlements WriterFlow.entitlements \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    "$APP"

echo "▸ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Zipping for notarization"
rm -f build/WriterFlow-notarize.zip
ditto -c -k --keepParent "$APP" build/WriterFlow-notarize.zip

echo "▸ Submitting to Apple notary service (this can take several minutes)"
xcrun notarytool submit build/WriterFlow-notarize.zip \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

echo "▸ Stapling notarization ticket to the app"
xcrun stapler staple "$APP"

echo "▸ Done — $APP is signed, notarized, and stapled."
echo "  Run scripts/make-dmg.sh next to package it for distribution."
