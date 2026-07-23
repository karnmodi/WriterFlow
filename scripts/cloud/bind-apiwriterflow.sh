#!/usr/bin/env bash
# Finish apiwriterflow.aviusolutions.com on wfprod-apim-edge (polls Cloudflare DNS).
set -euo pipefail

RG="${RG:-rg_writerflow_prod}"
APP="${APP:-wfprod-apim-edge}"
ENV="${ENV:-wfprod-web-cae}"
HOST="${APIWRITERFLOW_HOST:-apiwriterflow.aviusolutions.com}"

VERIFICATION_ID="$(az containerapp show -g "$RG" -n "$APP" --query properties.customDomainVerificationId -o tsv)"
EDGE_FQDN="$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)"

cat <<EOF
Add these Cloudflare DNS records (DNS only / grey cloud for CNAME during cert issue):

| Type | Name | Value |
|------|------|-------|
| TXT  | asuid.apiwriterflow | ${VERIFICATION_ID} |
| CNAME | apiwriterflow | ${EDGE_FQDN} |

Optional later: orange-cloud proxy ON once Azure managed cert is bound.
EOF

echo "Polling for asuid TXT..."
for i in $(seq 1 60); do
  TXT="$(dig +short "asuid.${HOST}" TXT 2>/dev/null | tr -d '"')"
  if [[ "$TXT" == "$VERIFICATION_ID" ]]; then
    echo "Ownership TXT verified (attempt $i)"
    break
  fi
  echo "  waiting ($i/60)..."
  sleep 10
done

az containerapp hostname add -g "$RG" -n "$APP" --hostname "$HOST" 2>&1 || true

az containerapp hostname bind -g "$RG" -n "$APP" \
  --hostname "$HOST" --environment "$ENV" --validation-method CNAME 2>&1 || \
az containerapp hostname bind -g "$RG" -n "$APP" \
  --hostname "$HOST" --environment "$ENV" --validation-method TXT 2>&1 || true

if curl -sf --max-time 15 "https://${HOST}/well-known/jwks.json" >/dev/null; then
  echo "Custom domain live: https://${HOST}"
  curl -sf "https://${HOST}/health/healthz" && echo " health OK"
  exit 0
fi

echo "Custom domain not reachable yet — add DNS records above."
exit 1
