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

# Copy processed resource bundle if it exists (SwiftPM emits WriterFlow_WriterFlow.bundle).
BUNDLE="${BIN_PATH}/WriterFlow_WriterFlow.bundle"
if [[ -d "$BUNDLE" ]]; then
    cp -R "$BUNDLE" "$APP/Contents/Resources/"
fi

# Attempt an ad-hoc signature for local development and the current v1 packaging path. Public v1 still
# requires the validation/checksum/Gatekeeper procedure in RELEASE.md; Developer ID is
# deferred to v2.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "▸ built $APP"
