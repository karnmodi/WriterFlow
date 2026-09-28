#!/usr/bin/env bash
# Install WriterFlow to a stable path so macOS permissions persist across rebuilds.
# Debug installs may sync local development configuration. Release installs preserve
# the hardened bundle signature and never copy repository credentials.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$CONFIG" == "release" ]]; then
    APP_NAME="WriterFlow"
    SUPPORT_NAME="WriterFlow"
else
    APP_NAME="writeflow_local"
    SUPPORT_NAME="writeflow_local"
fi
INSTALL_APP="${HOME}/Applications/${APP_NAME}.app"

cd "$ROOT"
"${ROOT}/scripts/bundle.sh" "${CONFIG}"

echo "▸ installing to ${INSTALL_APP}"
rm -rf "${INSTALL_APP}"
mkdir -p "${HOME}/Applications"
ditto "${ROOT}/build/${APP_NAME}.app" "${INSTALL_APP}"
# `ditto` preserves the signature bundle.sh already applied, so only verify it.
# Re-signing here used to mint a second, different identity for the installed
# copy — under ad-hoc signing that alone guaranteed a Keychain prompt, because
# the installed app was never the app that created the Keychain items.
codesign --verify --strict "${INSTALL_APP}"

echo "▸ installed ${INSTALL_APP}"
echo ""

SECRETS_DIR="${HOME}/Library/Application Support/${SUPPORT_NAME}"
if [[ "$CONFIG" != "release" && -f "${ROOT}/.env" ]]; then
    mkdir -p "${SECRETS_DIR}"
    # Azure BYO keys for debug builds. Loopback API URLs stay in repo `.env`
    # for `services/api`; they must not hijack Sign In unless the developer
    # opts in with WRITERFLOW_USE_LOCAL_API=1.
    grep -E '^(API_KEY_|TARGET_URI=|AZURE_OPENAI_DEPLOYMENT_|WRITERFLOW_USE_LOCAL_API=)' "${ROOT}/.env" \
        > "${SECRETS_DIR}/secrets.env" || true
    if [[ "${WRITERFLOW_USE_LOCAL_API:-}" == "1" ]] \
        || grep -Eq '^WRITERFLOW_USE_LOCAL_API=(1|true|yes)$' "${ROOT}/.env" 2>/dev/null; then
        grep -E '^WRITERFLOW_API_BASE_URL=' "${ROOT}/.env" >> "${SECRETS_DIR}/secrets.env" || true
    fi
    chmod 600 "${SECRETS_DIR}/secrets.env" 2>/dev/null || true
    echo "▸ synced API credentials to ${SECRETS_DIR}/secrets.env"
    if grep -q '^WRITERFLOW_API_BASE_URL=' "${SECRETS_DIR}/secrets.env" 2>/dev/null; then
        echo "▸ WriterFlow API override: $(grep '^WRITERFLOW_API_BASE_URL=' "${SECRETS_DIR}/secrets.env" | cut -d= -f2-)"
    else
        echo "▸ WriterFlow API: production (set WRITERFLOW_USE_LOCAL_API=1 to use localhost)"
    fi
fi

echo "Next steps (one-time):"
echo "  1. Quit any running ${APP_NAME} (menu → Quit ${APP_NAME}, or: make stop)"
echo "  2. Open: ${INSTALL_APP}"
echo "     — launches in the menu bar only (no Dashboard). Open Dashboard from the menu when needed."
echo "  3. If macOS asks for Keychain access, choose Always Allow (not Allow)."
echo "     After that, login launches should not prompt again under this signing identity."
echo "  4. In System Settings → Accessibility:"
echo "     - Remove any old ${APP_NAME} entries (- button)"
echo "     - Click + and add ${APP_NAME} from ~/Applications"
echo "     - Toggle ON, then quit and reopen ${APP_NAME}"
echo ""
