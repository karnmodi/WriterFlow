#!/usr/bin/env bash
# Stage 5.1 Accept smoke through APIM (+ optional custom domain).
set -euo pipefail

APIM_NAME="${APIM_NAME:-${NAME_PREFIX:-wfprod}-apim}"
RG="${AZURE_RESOURCE_GROUP:-rg_writerflow_prod}"
GATEWAY="${APIM_GATEWAY_URL:-}"
CUSTOM="${APIWRITERFLOW_URL:-https://apiwriterflow.aviusolutions.com}"

if [[ -z "$GATEWAY" ]]; then
  GATEWAY="$(az apim show -g "$RG" -n "$APIM_NAME" --query "gatewayUrl" -o tsv 2>/dev/null || true)"
fi
GATEWAY="${GATEWAY%/}/"

echo "▸ APIM gateway: $GATEWAY"
curl -sf "${GATEWAY}health/healthz" >/dev/null && echo "  health/healthz 200"
curl -sf "${GATEWAY}health/readyz" >/dev/null && echo "  health/readyz 200"
curl -sf "${GATEWAY}well-known/jwks.json" | python3 -c "import sys,json; assert len(json.load(sys.stdin)['keys'])>=1"
echo "  jwks OK"
curl -sf "${GATEWAY}well-known/openid-configuration" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['issuer']"
echo "  openid-configuration OK"

# JWT gate: /v2/me without bearer should not be 200
code="$(curl -s -o /dev/null -w '%{http_code}' "${GATEWAY}v2/me")"
[[ "$code" != "200" ]] && echo "  /v2/me rejects unauthenticated ($code)"

# The low-cost beta origin is internet-routable, but every /v2 route must reject
# callers that do not carry APIM's Key Vault-backed origin credential.
API_APP_NAME="${API_APP_NAME:-${NAME_PREFIX:-wfprod}-api}"
if ! az containerapp show -g "$RG" -n "$API_APP_NAME" >/dev/null 2>&1; then
  API_APP_NAME="${NAME_PREFIX:-wfprod}-api-public"
fi
origin_fqdn="$(az containerapp show -g "$RG" -n "$API_APP_NAME" --query properties.configuration.ingress.fqdn -o tsv)"
origin_code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
  -X POST -H 'Content-Type: application/json' -d '{}' "https://${origin_fqdn}/v2/device/authorize")"
if [[ "$origin_code" != "403" ]]; then
  echo "ERROR: direct API origin returned $origin_code instead of 403" >&2
  exit 1
fi
echo "  direct API origin rejects gateway bypass (403)"

pg_tls="$(az postgres flexible-server parameter show -g "$RG" -s "${NAME_PREFIX:-wfprod}-pg" -n require_secure_transport --query value -o tsv)"
[[ "$pg_tls" == "on" ]] || {
  echo "ERROR: PostgreSQL require_secure_transport is $pg_tls" >&2
  exit 1
}
echo "  PostgreSQL requires TLS"

aoai_local_auth="$(az cognitiveservices account show -g "$RG" -n "${NAME_PREFIX:-wfprod}-openai" --query properties.disableLocalAuth -o tsv)"
[[ "$aoai_local_auth" == "true" ]] || {
  echo "ERROR: Azure OpenAI reusable key authentication is enabled" >&2
  exit 1
}
echo "  Azure OpenAI accepts managed identity, not reusable keys"

kv_rbac="$(az keyvault show -g "$RG" -n "${NAME_PREFIX:-wfprod}-kv" --query properties.enableRbacAuthorization -o tsv)"
[[ "$kv_rbac" == "true" ]] || {
  echo "ERROR: Key Vault RBAC authorization is disabled" >&2
  exit 1
}
echo "  Key Vault RBAC enabled"

if curl -sf --max-time 10 "${CUSTOM}/well-known/jwks.json" >/dev/null 2>&1; then
  echo "▸ Custom domain ${CUSTOM} OK"
else
  echo "▸ Custom domain not live yet — run scripts/cloud/bind-apiwriterflow.sh after Cloudflare DNS"
fi

echo "Stage 5.1 APIM smoke passed"
