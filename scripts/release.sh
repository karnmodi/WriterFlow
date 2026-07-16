#!/usr/bin/env bash
# V2 ONLY: Sign, notarize, and staple a Release build of WriterFlow.app.
#
# This is retained as future Developer ID infrastructure. It is not the v1 production
# path and Apple Developer Program membership is not a v1 release requirement. The v1
# runbook calls for a manually verified DMG containing an ad-hoc-signed app, checksum,
# manual Gatekeeper approval, and manual updates; the current scripts do not automate
# every verification.
# See RELEASE.md before running any release command.
#
# When v2 trusted distribution is started, this requires a paid Apple Developer Program
# membership + Developer ID Application certificate and deliberately fails fast rather
# than silently skipping a security step.
#
# Required environment variables:
#   DEVELOPER_ID_APPLICATION     e.g. "Developer ID Application: Jane Doe (ABCDE12345)"
#   APPLE_ID                     Apple ID used for notarization
#   APPLE_TEAM_ID                10-character Team ID
#   APPLE_APP_SPECIFIC_PASSWORD  generated at https://appleid.apple.com (Security → App-Specific Passwords)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your \"Developer ID Application: Name (TEAMID)\" signing identity — see the v2 section of RELEASE.md}"
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
