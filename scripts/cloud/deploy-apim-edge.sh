#!/usr/bin/env bash
# Public edge proxy: apiwriterflow.aviusolutions.com → APIM default gateway (TLS via ACA managed cert).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RG="${RG:-rg_writerflow_prod}"
ACR="${ACR:-wfprodacr}"
APP="${APP:-wfprod-apim-edge}"
ENV="${ENV:-wfprod-web-cae}"
IMAGE="${ACR}.azurecr.io/writerflow-apim-edge:latest"
HOST="${APIWRITERFLOW_HOST:-apiwriterflow.aviusolutions.com}"
APIM_GATEWAY_HOST="${APIM_GATEWAY_HOST:-wfprod-apim-dev.azure-api.net}"

az acr login -n "$ACR" >/dev/null
docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/scripts/cloud/apim-edge"
docker push "$IMAGE"

if ! az containerapp show -g "$RG" -n "$APP" >/dev/null 2>&1; then
  az containerapp create -g "$RG" -n "$APP" --environment "$ENV" \
    --image "$IMAGE" --target-port 8080 --ingress external \
    --cpu 0.25 --memory 0.5Gi --min-replicas 1 --max-replicas 2 \
    --env-vars "APIM_GATEWAY_HOST=$APIM_GATEWAY_HOST" \
    --registry-server "${ACR}.azurecr.io" >/dev/null
else
  az containerapp update -g "$RG" -n "$APP" --image "$IMAGE" \
    --set-env-vars "APIM_GATEWAY_HOST=$APIM_GATEWAY_HOST" >/dev/null
fi

echo "Binding $HOST (add Cloudflare DNS records when prompted)..."
az containerapp hostname bind -g "$RG" -n "$APP" \
  --hostname "$HOST" --environment "$ENV" --validation-method CNAME 2>&1 || true

FQDN="$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)"
echo "Edge proxy FQDN: https://$FQDN"
echo "After DNS + cert: curl -sf https://${HOST}/well-known/jwks.json"
