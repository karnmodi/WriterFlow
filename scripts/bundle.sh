#!/usr/bin/env bash
# Wrap the SPM-built executable as WriterFlow.app.
# Xcode is not required — Command Line Tools + swift build is enough.
set -euo pipefail

CONFIG="${1:-debug}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
EXE="${BIN_PATH}/WriterFlow"
[[ -x "$EXE" ]] || { echo "✗ executable not found at $EXE" >&2; exit 1; }

APP="build/WriterFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$EXE" "$APP/Contents/MacOS/WriterFlow"
cp Info.plist "$APP/Contents/Info.plist"

# Required third-party license notices must travel inside the distributed artifact.
NOTICE="THIRD-PARTY-NOTICES.txt"
if [[ -f "$NOTICE" ]]; then
    cp "$NOTICE" "$APP/Contents/Resources/$NOTICE"
else
    echo "✗ $NOTICE not found — required third-party license notice is missing" >&2
    exit 1
fi

# Copy processed resource bundle if it exists (SwiftPM emits WriterFlow_WriterFlow.bundle).
BUNDLE="${BIN_PATH}/WriterFlow_WriterFlow.bundle"
if [[ -d "$BUNDLE" ]]; then
    cp -R "$BUNDLE" "$APP/Contents/Resources/"
fi

# Ad-hoc signature. Developer ID is deferred to v2 (scripts/release.sh).
#
# For a release build this is a production packaging step: enable the hardened
# runtime (the v1 default per RELEASE.md) and fail the build if signing errors —
# the script must never silently ship an unsigned or non-hardened artifact.
# For debug builds keep the lenient, quiet path so the local dev loop is not
# interrupted by transient signing hiccups.
if [[ "$CONFIG" == "release" ]]; then
    echo "▸ ad-hoc codesigning with hardened runtime (release)"
    codesign --force --sign - --options runtime --timestamp=none "$APP"
else
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
fi

echo "▸ built $APP"
