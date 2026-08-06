#!/usr/bin/env bash
# Deterministic single-command ad-hoc build + release verifier for WriterFlow.
#
# This retains the historical filename used by the v1 packaging workflow in RELEASE.md.
# It is NOT the deferred Developer ID / notarization path (scripts/release.sh).
# It performs a clean release build, wraps the ad-hoc-signed hardened-runtime app,
# proves the bundle identity/version/architecture/signature, scans the app AND the
# mounted DMG for forbidden credential files and secrets, then produces and verifies
# the DMG plus its SHA-256.
#
# Every check fails hard on the first problem. No secret value is ever printed:
# scanners report only file paths, match counts, and the name of the offending rule.
#
# Notes:
#   * spctl/Gatekeeper rejection is EXPECTED for this unidentified, non-notarized app
#     and is intentionally not treated as a failure here (see RELEASE.md).
#   * current releases are universal; the verifier checks every bundled Mach-O slice.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXPECTED_BUNDLE_ID="com.karan.writerflow"
# Prefer an explicit override; otherwise package whatever Info.plist advertises
# (v1.0.0 historically; private-beta / v2 uses the current Info.plist value).
EXPECTED_VERSION="${EXPECTED_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
NOTICE_NAME="THIRD-PARTY-NOTICES.txt"

APP="build/WriterFlow.app"
PLIST="$APP/Contents/Info.plist"
DMG="build/WriterFlow-${EXPECTED_VERSION}.dmg"
SHA_FILE="WriterFlow-${EXPECTED_VERSION}.dmg.sha256"

# Filenames that must never appear inside a public artifact.
FORBIDDEN_GLOBS=(".env" ".env.local" ".env.example" "secrets.env" "*.p8" "*.p12" "*.provisionprofile" "*.mobileprovision")

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
step "1/10  Clean"
rm -rf .build build
pass "removed .build and build/"

# ---------------------------------------------------------------------------
step "2/10  Unit tests"
swift test
pass "unit tests passed"

# ---------------------------------------------------------------------------
step "3/10  Universal Release build + bundle (ad-hoc, hardened runtime)"
CONFIG=release scripts/bundle.sh release
[[ -d "$APP" ]] || fail "$APP was not produced"
pass "built $APP"

# ---------------------------------------------------------------------------
step "4/10  Bundle identity, version, architecture, deployment target"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || fail "bundle id is '$BUNDLE_ID', expected '$EXPECTED_BUNDLE_ID'"
pass "bundle id = $BUNDLE_ID"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[[ "$VERSION" == "$EXPECTED_VERSION" ]] || fail "CFBundleShortVersionString is '$VERSION', expected '$EXPECTED_VERSION'"
pass "version = $VERSION"

scripts/check-macos-compatibility.sh --app "$APP" \
    || fail "macOS compatibility verification failed"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/WriterFlow")"
pass "architectures = $ARCHS; deployment target = macOS 14.0"

WEBSITE_VERSION="$(node -e 'process.stdout.write(require("./website/lib/release.json").version)')"
[[ "$WEBSITE_VERSION" == "$EXPECTED_VERSION" ]] \
    || fail "website release version is '$WEBSITE_VERSION', expected '$EXPECTED_VERSION'"
pass "website release metadata version = $WEBSITE_VERSION"

# ---------------------------------------------------------------------------
step "5/10  Signature + hardened runtime"

codesign --verify --deep --strict --verbose=2 "$APP" 2>/dev/null || fail "codesign --verify failed"
pass "codesign --verify --deep --strict"

SIGN_INFO="$(codesign -dvvv --verbose=4 "$APP" 2>&1)"
grep -q 'Signature=adhoc' <<<"$SIGN_INFO" || fail "signature is not ad-hoc"
pass "Signature=adhoc"

grep -Eq 'flags=0x[0-9a-fA-F]*\(?[^)]*runtime' <<<"$SIGN_INFO" || fail "hardened runtime flag not set on the signature"
pass "hardened runtime enabled"

# ---------------------------------------------------------------------------
step "6/10  Bundle resources (license notice + app icon)"
[[ -f "$APP/Contents/Resources/$NOTICE_NAME" ]] || fail "$NOTICE_NAME missing from $APP/Contents/Resources"
grep -q 'GRDB' "$APP/Contents/Resources/$NOTICE_NAME" || fail "$NOTICE_NAME does not mention GRDB"
pass "$NOTICE_NAME bundled and mentions GRDB"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "AppIcon.icns missing from $APP/Contents/Resources"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST" 2>/dev/null || true)"
[[ "$ICON_FILE" == "AppIcon" ]] || fail "CFBundleIconFile is '$ICON_FILE', expected 'AppIcon'"
pass "AppIcon.icns bundled and CFBundleIconFile=AppIcon"

# ---------------------------------------------------------------------------
# scan_tree <label> <root-dir>
# Fails on any forbidden credential file, common secret pattern, or exact match of
# a nonempty value from the local .env. Never echoes a secret's contents.
scan_tree() {
    local label="$1" dir="$2" hit path count

    # (a) forbidden credential filenames anywhere in the tree
    for glob in "${FORBIDDEN_GLOBS[@]}"; do
        while IFS= read -r path; do
            [[ -n "$path" ]] && fail "[$label] forbidden credential file present: ${path#"$dir"/}"
        done < <(find "$dir" -type f -name "$glob" 2>/dev/null)
    done
    pass "[$label] no forbidden credential filenames"

    # (b) common secret patterns across text AND binary files (`-a`). Report only
    #     the path and rule name — never matched content.
    local -a rules=(
        "openai-key:sk-[A-Za-z0-9]{20,}"
        "bearer-token:[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{20,}"
        "aws-access-key:AKIA[0-9A-Z]{16}"
        "private-key-block:-----BEGIN[[:space:]][A-Z ]*PRIVATE KEY-----"
        "api-key-assign:[Aa][Pp][Ii]_?[Kk][Ee][Yy][\"'[:space:]]*[:=][\"'[:space:]]*[A-Za-z0-9._-]{20,}"
    )
    for rule in "${rules[@]}"; do
        local name="${rule%%:*}" pat="${rule#*:}"
        if hit="$(grep -rlaE -- "$pat" "$dir" 2>/dev/null)"; then
            [[ -n "$hit" ]] && fail "[$label] possible secret ($name) found in: $(echo "$hit" | sed "s#$dir/##" | tr '\n' ' ')"
        fi
    done
    pass "[$label] no common secret patterns"

    # (c) private Azure endpoints across text and compiled binaries. The literal
    #     onboarding placeholder is expected; any concrete Azure resource hostname
    #     embedded in the artifact is forbidden.
    local azure_pattern='https://[A-Za-z0-9][A-Za-z0-9-]*\.(cognitiveservices|openai)\.azure\.com'
    while IFS= read -r path; do
        [[ -f "$path" ]] || continue
        if strings "$path" 2>/dev/null \
            | grep -E "$azure_pattern" \
            | grep -Fv 'https://YOUR-RESOURCE.' \
            | grep -q .; then
            fail "[$label] concrete Azure endpoint embedded in: ${path#"$dir"/}"
        fi
    done < <(find "$dir" -type f 2>/dev/null)
    pass "[$label] no concrete Azure endpoint embedded"

    # (d) exact nonempty values of the SECRET-BEARING variables in the local .env
    #     (definitive; scans binary too via -F fixed-string, no -I). Never prints the
    #     value — only the variable name.
    #
    #     Only credential/endpoint variables are enforced here: those are precisely the
    #     "API key, bearer token, signing credential, or private endpoint" that
    #     RELEASE.md forbids in the artifact. Non-secret config (deployment/model
    #     names, api-version) is intentionally excluded, because those values ship as
    #     legitimate compiled-in defaults (e.g. "2025-04-01-preview", "gpt-5.4-mini")
    #     and would otherwise cause false failures on a correct, secret-free build.
    if [[ -f "$ROOT/.env" ]]; then
        local leaked=0
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" != *=* ]] && continue
            local var="${line%%=*}" val="${line#*=}"
            var="${var#"${var%%[![:space:]]*}"}"
            var="${var%"${var##*[![:space:]]}"}"
            # only credential/endpoint variables carry secrets worth enforcing
            shopt -s nocasematch
            local sensitive=0
            [[ "$var" =~ (KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|TARGET_URI|ENDPOINT|_URI|_URL) ]] && sensitive=1
            shopt -u nocasematch
            [[ "$sensitive" -eq 1 ]] || continue
            # strip surrounding quotes/whitespace from the value
            val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            # only meaningful (long) values are worth matching; short/empty are skipped
            [[ ${#val} -lt 12 ]] && continue
            if count="$(grep -rlF -- "$val" "$dir" 2>/dev/null)" && [[ -n "$count" ]]; then
                printf '  \033[31m✗ [%s] value of secret .env var %s leaked into artifact\033[0m\n' "$label" "$var" >&2
                leaked=1
            fi
        done < "$ROOT/.env"
        [[ "$leaked" -eq 0 ]] || fail "[$label] one or more .env credential/endpoint values are present in the artifact"
        pass "[$label] no local .env credential/endpoint values present"
    else
        pass "[$label] no local .env to compare against (skipped value scan)"
    fi
}

step "7/10  Secret + credential scan (app bundle)"
scan_tree "app" "$APP"

# ---------------------------------------------------------------------------
step "8/10  Build DMG, verify structure, scan mounted contents"
scripts/make-dmg.sh
[[ -f "$DMG" ]] || fail "$DMG was not produced"
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "hdiutil verify failed for $DMG"
pass "hdiutil verify passed"

MOUNT_DIR="$(mktemp -d)"
ATTACHED=0
cleanup() {
    if [[ "$ATTACHED" -eq 1 ]]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT

hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null || fail "could not mount $DMG"
ATTACHED=1
pass "mounted $DMG"

# Installer-window structure: app + Applications drop target + background art + Finder layout.
[[ -d "$MOUNT_DIR/WriterFlow.app" ]] || fail "DMG missing WriterFlow.app"
[[ -L "$MOUNT_DIR/Applications" ]] || fail "DMG missing Applications symlink"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || fail "Applications symlink does not point to /Applications"
[[ -f "$MOUNT_DIR/.background/background.png" ]] || fail "DMG missing .background/background.png installer art"
[[ -f "$MOUNT_DIR/.DS_Store" ]] || fail "DMG missing .DS_Store (Finder window layout was not baked in)"
[[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]] || fail "DMG missing .VolumeIcon.icns"
pass "DMG installer layout (app, Applications, background, .DS_Store, volume icon)"
scripts/check-macos-compatibility.sh --app "$MOUNT_DIR/WriterFlow.app" \
    || fail "mounted DMG contains an incompatible app"
pass "mounted DMG contains the verified universal app"
"$MOUNT_DIR/WriterFlow.app/Contents/MacOS/WriterFlow" --smoke-launch \
    || fail "mounted WriterFlow app failed its native launch smoke check"
pass "mounted WriterFlow app loads native dependencies, AppKit, and required resources"
scan_tree "dmg" "$MOUNT_DIR"

# ---------------------------------------------------------------------------
step "9/10  SHA-256 checksum"
( cd build && shasum -a 256 "WriterFlow-${EXPECTED_VERSION}.dmg" > "$SHA_FILE" )
( cd build && shasum -a 256 -c "$SHA_FILE" >/dev/null ) || fail "SHA-256 verification failed"
pass "wrote and verified build/$SHA_FILE"

# ---------------------------------------------------------------------------
step "10/10  V2 release scanner (cloud endpoint required; BYO/secrets forbidden)"
node scripts/scan-v2-release.mjs "$APP" || fail "scan-v2-release.mjs failed for $APP"
pass "scan-v2-release.mjs passed"

printf '\n\033[1;32mRelease verification passed.\033[0m\n'
printf '  Version:  %s\n' "$EXPECTED_VERSION"
printf '  DMG:      %s\n' "$DMG"
printf '  Checksum: build/%s\n' "$SHA_FILE"
printf '  (Gatekeeper/spctl rejection is expected for this unidentified ad-hoc build — see RELEASE.md.)\n'
