#!/usr/bin/env bash
# Verify WriterFlow's macOS support contract and, optionally, compile or inspect it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MIN_MACOS="14.0"
EXPECTED_ARCHS=(arm64 x86_64)
BUILD_RELEASE=0
APP_PATH=""

usage() {
    echo "Usage: $0 [--build] [--app /path/to/WriterFlow.app]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)
            BUILD_RELEASE=1
            shift
            ;;
        --app)
            [[ $# -ge 2 ]] || usage
            APP_PATH="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

normalized_archs() {
    tr ' ' '\n' <<<"$1" | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//'
}

version_equals() {
    awk -v lhs="$1" -v rhs="$2" 'BEGIN {
        split(lhs, l, "."); split(rhs, r, ".")
        for (i = 1; i <= 3; i++) {
            if ((l[i] + 0) != (r[i] + 0)) exit 1
        }
    }'
}

version_lte() {
    awk -v lhs="$1" -v rhs="$2" 'BEGIN {
        split(lhs, l, "."); split(rhs, r, ".")
        for (i = 1; i <= 3; i++) {
            if ((l[i] + 0) < (r[i] + 0)) exit 0
            if ((l[i] + 0) > (r[i] + 0)) exit 1
        }
        exit 0
    }'
}

minimum_os_for_arch() {
    local binary="$1" arch="$2" output minimum
    output="$(xcrun vtool -arch "$arch" -show-build "$binary" 2>/dev/null)" \
        || fail "could not inspect deployment target for $binary ($arch)"
    minimum="$(awk '
        $1 == "minos" { print $2; exit }
        $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { legacy = 1; next }
        legacy && $1 == "version" { print $2; exit }
    ' <<<"$output")"
    [[ -n "$minimum" ]] || fail "no macOS deployment target found for $binary ($arch)"
    printf '%s\n' "$minimum"
}

verify_thin_executable() {
    local executable="$1" expected_arch="$2" actual_arch minimum
    [[ -x "$executable" ]] || fail "executable not found: $executable"
    actual_arch="$(lipo -archs "$executable")"
    [[ "$actual_arch" == "$expected_arch" ]] \
        || fail "$executable has '$actual_arch', expected '$expected_arch'"
    minimum="$(minimum_os_for_arch "$executable" "$expected_arch")"
    version_equals "$minimum" "$MIN_MACOS" \
        || fail "$executable ($expected_arch) has minOS $minimum, expected $MIN_MACOS"
    pass "$expected_arch Release slice compiles with minOS $minimum"
}

verify_support_metadata() {
    local plist_min package_pattern project_count
    plist_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)"
    version_equals "$plist_min" "$MIN_MACOS" \
        || fail "Info.plist LSMinimumSystemVersion is $plist_min, expected $MIN_MACOS"

    package_pattern='platforms:[[:space:]]*\[\.macOS\(\.v14\)\]'
    grep -Eq "$package_pattern" Package.swift \
        || fail "Package.swift must declare .macOS(.v14)"

    project_count="$(grep -Ec 'macOS:[[:space:]]*"14\.0"|MACOSX_DEPLOYMENT_TARGET:[[:space:]]*"14\.0"' project.yml)"
    [[ "$project_count" -eq 2 ]] \
        || fail "project.yml must declare macOS 14.0 in both deployment-target settings"

    pass "deployment metadata agrees on macOS $MIN_MACOS"
}

verify_universal_app() {
    local app="$1" executable actual_archs expected_archs minimum macho_count=0
    [[ -d "$app" ]] || fail "app bundle not found: $app"
    executable="$app/Contents/MacOS/WriterFlow"
    [[ -x "$executable" ]] || fail "WriterFlow executable missing from $app"

    expected_archs="$(normalized_archs "${EXPECTED_ARCHS[*]}")"
    actual_archs="$(normalized_archs "$(lipo -archs "$executable")")"
    [[ "$actual_archs" == "$expected_archs" ]] \
        || fail "WriterFlow architectures are '$actual_archs', expected '$expected_archs'"

    for arch in "${EXPECTED_ARCHS[@]}"; do
        minimum="$(minimum_os_for_arch "$executable" "$arch")"
        version_equals "$minimum" "$MIN_MACOS" \
            || fail "WriterFlow ($arch) has minOS $minimum, expected $MIN_MACOS"
    done

    while IFS= read -r -d '' candidate; do
        if file -b "$candidate" | grep -q 'Mach-O'; then
            macho_count=$((macho_count + 1))
            actual_archs="$(normalized_archs "$(lipo -archs "$candidate")")"
            [[ "$actual_archs" == "$expected_archs" ]] \
                || fail "$candidate architectures are '$actual_archs', expected '$expected_archs'"
            for arch in "${EXPECTED_ARCHS[@]}"; do
                minimum="$(minimum_os_for_arch "$candidate" "$arch")"
                version_lte "$minimum" "$MIN_MACOS" \
                    || fail "$candidate ($arch) requires macOS $minimum, above $MIN_MACOS"
            done
        fi
    done < <(find "$app/Contents/MacOS" "$app/Contents/Frameworks" -type f -print0 2>/dev/null)

    [[ "$macho_count" -ge 2 ]] \
        || fail "expected the app executable and at least one bundled Mach-O framework"
    pass "universal app has arm64+x86_64 slices and macOS-compatible nested code"
}

verify_support_metadata

if [[ "$BUILD_RELEASE" -eq 1 ]]; then
    for arch in "${EXPECTED_ARCHS[@]}"; do
        triple="${arch}-apple-macosx${MIN_MACOS}"
        echo "▸ swift build -c release --triple $triple"
        swift build -c release --triple "$triple"
        bin_path="$(swift build -c release --triple "$triple" --show-bin-path)"
        verify_thin_executable "$bin_path/WriterFlow" "$arch"
    done
fi

if [[ -n "$APP_PATH" ]]; then
    verify_universal_app "$APP_PATH"
fi

