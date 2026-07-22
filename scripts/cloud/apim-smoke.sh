#!/usr/bin/env bash
# Post-deploy APIM smoke + custom-domain checklist for WriterFlow v2 dev.
# Requires: az login, APIM deployed (wfprod-apim or bicep module output).
set -euo pipefail

APIM_NAME="${APIM_NAME:-wfprod-apim}"
RG="${AZURE_RESOURCE_GROUP:-rg_writerflow_prod}"
GATEWAY="${APIM_GATEWAY_URL:-}"

if [[ -z "$GATEWAY" ]]; then
  GATEWAY="$(az apim show -g "$RG" -n "$APIM_NAME" --query "gatewayUrl" -o tsv 2>/dev/null || true)"
fi

if [[ -z "$GATEWAY" ]]; then
  echo "APIM not found in $RG — deploy infra/bicep/modules/apim.bicep first."
  echo "UK South note: StandardV2 may fail with ApiServiceCreationDisabledForSubscription."
  exit 1
fi

echo "APIM gateway: $GATEWAY"
echo "Smoke: GET ${GATEWAY}v2/healthz (expect 401 without bearer — proves JWT gate is live)"
curl -sf -o /dev/null -w "HTTP %{http_code}\n" "${GATEWAY}v2/healthz" || true

echo ""
echo "Next manual steps for apiwriterflow.aviusolutions.com:"
echo "  1. APIM custom domain + managed cert"
echo "  2. Cloudflare CNAME apiwriterflow → APIM gateway hostname"
echo "  3. Verify GET https://apiwriterflow.aviusolutions.com/.well-known/jwks.json"
