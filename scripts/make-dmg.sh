#!/usr/bin/env bash
# Package build/WriterFlow.app into a polished drag-to-Applications DMG.
#
# Produces a Finder installer window that opens automatically when the user
# double-clicks the downloaded DMG (standard macOS disk-image behavior):
#   • WriterFlow.app on the left
#   • Applications symlink on the right
#   • Brand background, icon positions, and window bounds baked into .DS_Store
#
# The v1 plan calls for an ad-hoc-signed Release bundle; no Apple membership is
# required. This script accepts whatever bundle already exists and does not verify
# that requirement. Gatekeeper blocks normal first launch on another Mac, so users
# must follow Apple's System Settings → Privacy & Security → Open Anyway flow.
# Complete every check in RELEASE.md before public upload.
#
# V2 may run scripts/release.sh first for Developer ID signing/notarization.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/WriterFlow.app"
BACKGROUND_SRC="packaging/dmg/background.png"
BACKGROUND_2X_SRC="packaging/dmg/background@2x.png"
VOLUME_ICON_SRC="packaging/AppIcon.icns"

[[ -d "$APP" ]] || { echo "✗ $APP not found — run 'CONFIG=release make bundle' first (see RELEASE.md)" >&2; exit 1; }
[[ -f "$BACKGROUND_SRC" ]] || { echo "✗ $BACKGROUND_SRC missing — run: python3 packaging/generate-assets.py" >&2; exit 1; }
[[ -f "$VOLUME_ICON_SRC" ]] || { echo "✗ $VOLUME_ICON_SRC missing — run: python3 packaging/generate-assets.py" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG_NAME="WriterFlow-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"
RW_DMG="build/.WriterFlow-rw.dmg"
VOLUME_NAME="WriterFlow"
VOLUME_PATH="/Volumes/${VOLUME_NAME}"

# Finder window geometry (must match packaging/generate-assets.py WINDOW_*).
WINDOW_X=200
WINDOW_Y=160
WINDOW_W=720
WINDOW_H=460
ICON_SIZE=128
# Icon centers — aligned with the circular pads on the background art.
APP_ICON_X=180
APP_ICON_Y=230
APPS_ICON_X=540
APPS_ICON_Y=230

detach_volume() {
    if [[ -d "$VOLUME_PATH" ]]; then
        /usr/bin/hdiutil detach "$VOLUME_PATH" >/dev/null 2>&1 \
            || /usr/bin/hdiutil detach "$VOLUME_PATH" -force >/dev/null 2>&1 \
            || true
    fi
}

cleanup() {
    detach_volume
    rm -f "$RW_DMG"
}
trap cleanup EXIT

# Clear any stale volume from a previous interrupted run.
detach_volume

echo "▸ Preparing compressed staging estimate"
APP_SIZE_KB="$(/usr/bin/du -sk "$APP" | awk '{print $1}')"
# App + background + volume icon + Finder metadata headroom.
IMAGE_SIZE_KB=$((APP_SIZE_KB + 15360))
if (( IMAGE_SIZE_KB < 51200 )); then
    IMAGE_SIZE_KB=51200
fi

echo "▸ Creating read-write disk image (${IMAGE_SIZE_KB} KB)"
rm -f "$RW_DMG" "$DMG_PATH"
/usr/bin/hdiutil create \
    -size "${IMAGE_SIZE_KB}k" \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    -ov \
    "$RW_DMG" >/dev/null

echo "▸ Mounting ${VOLUME_PATH}"
/usr/bin/hdiutil attach "$RW_DMG" -nobrowse -mountpoint "$VOLUME_PATH" >/dev/null

echo "▸ Copying app, Applications link, and installer artwork"
/usr/bin/ditto "$APP" "$VOLUME_PATH/WriterFlow.app"
ln -s /Applications "$VOLUME_PATH/Applications"

mkdir -p "$VOLUME_PATH/.background"
cp "$BACKGROUND_SRC" "$VOLUME_PATH/.background/background.png"
if [[ -f "$BACKGROUND_2X_SRC" ]]; then
    cp "$BACKGROUND_2X_SRC" "$VOLUME_PATH/.background/background@2x.png"
fi

# Hide support files from the installer icon view.
/usr/bin/chflags hidden "$VOLUME_PATH/.background"
/usr/bin/SetFile -a V "$VOLUME_PATH/.background" >/dev/null 2>&1 || true

echo "▸ Configuring Finder installer window (auto-opens on mount)"
# AppleScript writes .DS_Store: icon positions, icon size, window bounds, background.
# macOS opens this Finder window automatically when the user double-clicks the DMG
# (and when Safari's "Open safe files after downloading" preference is enabled).
/usr/bin/osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$WINDOW_X, $WINDOW_Y, $(($WINDOW_X + WINDOW_W)), $(($WINDOW_Y + WINDOW_H))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set text size of opts to 12
        set background picture of opts to file ".background:background.png"
        delay 0.5
        set position of item "WriterFlow.app" of container window to {$APP_ICON_X, $APP_ICON_Y}
        set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}
        update without registering applications
        delay 1
        close
        -- Re-open once so Finder commits .DS_Store with the final layout.
        open
        delay 1
        close
    end tell
end tell
EOF

# Apply the volume icon AFTER Finder layout so Finder cannot discard it mid-update.
cp "$VOLUME_ICON_SRC" "$VOLUME_PATH/.VolumeIcon.icns"
/usr/bin/SetFile -c icnC "$VOLUME_PATH/.VolumeIcon.icns" >/dev/null 2>&1 || true
/usr/bin/SetFile -a C "$VOLUME_PATH" >/dev/null 2>&1 || true

[[ -f "$VOLUME_PATH/.VolumeIcon.icns" ]] || { echo "✗ .VolumeIcon.icns missing before detach" >&2; exit 1; }
[[ -f "$VOLUME_PATH/.DS_Store" ]] || { echo "✗ .DS_Store missing — Finder layout was not saved" >&2; exit 1; }
[[ -f "$VOLUME_PATH/.background/background.png" ]] || { echo "✗ background.png missing" >&2; exit 1; }

# Flush Finder state to the volume before converting.
sync
sleep 1

echo "▸ Detaching"
# Close any Finder windows on the volume first so .DS_Store is final.
/usr/bin/osascript -e 'tell application "Finder" to tell disk "'"$VOLUME_NAME"'" to close' >/dev/null 2>&1 || true
sleep 1
detach_volume
sleep 1

echo "▸ Compressing to ${DMG_NAME}"
/usr/bin/hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG"

echo "▸ Built $DMG_PATH"
echo "  Double-click the DMG to confirm the installer window opens with:"
echo "    WriterFlow (left) → Applications (right), branded background."
