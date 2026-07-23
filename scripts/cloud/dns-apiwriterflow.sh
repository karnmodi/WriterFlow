#!/usr/bin/env bash
# Create Cloudflare DNS for apiwriterflow.aviusolutions.com → APIM gateway.
# Proxied CNAME lets Cloudflare terminate TLS; APIM sees its default hostname.
#
# Requires: CLOUDFLARE_API_TOKEN with Zone.DNS edit on aviusolutions.com
# Optional: CLOUDFLARE_ZONE_ID (auto-resolved if unset)
set -euo pipefail

ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-aviusolutions.com}"
RECORD_NAME="${APIWRITERFLOW_HOST:-apiwriterflow}"
APIM_HOST="${APIM_GATEWAY_HOST:-wfprod-apim-dev.azure-api.net}"
TOKEN="${CLOUDFLARE_API_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  cat <<EOF
CLOUDFLARE_API_TOKEN is not set.

Manual Cloudflare step (orange-cloud proxy ON):
  Type: CNAME
  Name: ${RECORD_NAME}
  Target: ${APIM_HOST}
  Proxy: Proxied

Then verify:
  curl -sf "https://${RECORD_NAME}.${ZONE_NAME}/well-known/jwks.json"
EOF
  exit 1
fi

if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  CLOUDFLARE_ZONE_ID="$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'])")"
fi

FQDN="${RECORD_NAME}.${ZONE_NAME}"
payload="$(python3 <<PY
import json
print(json.dumps({
  "type": "CNAME",
  "name": "${RECORD_NAME}",
  "content": "${APIM_HOST}",
  "proxied": True,
  "ttl": 1
}))
PY
)"

existing="$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${FQDN}" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id'] if r else '')")"

if [[ -n "$existing" ]]; then
  curl -sf -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${existing}" \
    --data "$payload" >/dev/null
  echo "Updated DNS ${FQDN} → ${APIM_HOST} (proxied)"
else
  curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
    --data "$payload" >/dev/null
  echo "Created DNS ${FQDN} → ${APIM_HOST} (proxied)"
fi

echo "Waiting for DNS..."
for _ in $(seq 1 30); do
  if curl -sf --max-time 10 "https://${FQDN}/well-known/jwks.json" >/dev/null; then
    echo "JWKS OK at https://${FQDN}/well-known/jwks.json"
    curl -sf "https://${FQDN}/health/healthz" && echo " health OK"
    exit 0
  fi
  sleep 5
done
echo "DNS record created but HTTPS smoke timed out — check Cloudflare SSL mode (Full)."
exit 1
