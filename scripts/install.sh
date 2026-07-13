#!/usr/bin/env bash
# Install WriterFlow to a stable path so macOS permissions persist across rebuilds.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_APP="${HOME}/Applications/WriterFlow.app"

cd "$ROOT"
"${ROOT}/scripts/bundle.sh" "${CONFIG}"

echo "▸ installing to ${INSTALL_APP}"
rm -rf "${INSTALL_APP}"
mkdir -p "${HOME}/Applications"
ditto "${ROOT}/build/WriterFlow.app" "${INSTALL_APP}"
codesign --force --deep --sign - --timestamp=none "${INSTALL_APP}" >/dev/null 2>&1 || true

echo "▸ installed ${INSTALL_APP}"
echo ""

SECRETS_DIR="${HOME}/Library/Application Support/WriterFlow"
if [[ -f "${ROOT}/.env" ]]; then
    mkdir -p "${SECRETS_DIR}"
    grep -E '^(API_KEY_|TARGET_URI=|AZURE_OPENAI_DEPLOYMENT_)' "${ROOT}/.env" > "${SECRETS_DIR}/secrets.env" || true
    chmod 600 "${SECRETS_DIR}/secrets.env" 2>/dev/null || true
    echo "▸ synced API credentials to ${SECRETS_DIR}/secrets.env"
fi

echo "Next steps (one-time):"
echo "  1. Quit any running WriterFlow (Dock → Quit, or: make stop)"
echo "  2. Open: ${INSTALL_APP}"
echo "  3. In System Settings → Accessibility:"
echo "     - Remove any old WriterFlow entries (- button)"
echo "     - Click + and add WriterFlow from ~/Applications"
echo "     - Toggle ON, then quit and reopen WriterFlow"
echo ""
