#!/usr/bin/env bash
# Configure wfprod-apim-dev with WriterFlow APIs (Developer tier).
# StandardV2 APIM is unavailable in UK South as of 2026-07-22; this script
# targets the live Developer instance instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RG="${RG:-rg_writerflow_prod}"
APIM="${APIM:-wfprod-apim-dev}"
API_BACKEND="${API_BACKEND:-https://wfprod-api-public.thankfulwater-e235f058.uksouth.azurecontainerapps.io}"
GATEWAY="${GATEWAY:-https://wfprod-apim-dev.azure-api.net}"
SUB="${SUB:-$(az account show --query id -o tsv)}"

put_policy() {
  local scope=$1
  local file=$2
  local xml
  xml=$(python3 -c "import json; print(json.dumps(open('$file').read()))")
  az rest --method put \
    --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/$scope/policies/policy?api-version=2023-03-01-preview" \
    --headers "Content-Type=application/json" \
    --body "{\"properties\":{\"format\":\"rawxml\",\"value\":$xml}}" >/dev/null
}

echo "▸ Named values"
az apim nv create -g "$RG" --service-name "$APIM" --named-value-id writerflow-jwks-uri \
  --display-name writerflow-jwks-uri --value "$GATEWAY/well-known/openid-configuration" 2>/dev/null || \
az apim nv update -g "$RG" --service-name "$APIM" --named-value-id writerflow-jwks-uri \
  --value "$GATEWAY/well-known/openid-configuration" >/dev/null
az apim nv create -g "$RG" --service-name "$APIM" --named-value-id writerflow-issuer \
  --display-name writerflow-issuer --value "https://apiwriterflow.aviusolutions.com" 2>/dev/null || true

echo "▸ Policies"
put_policy "apis/writerflow-v2" "$ROOT/infra/apim/api-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/device-authorize" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/device-token" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/token-refresh" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/device-approve" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/web-session-token" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/web-account-token" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/web-session-bridge" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/web-me" "$ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/writerflow-v2/operations/inference-stream" "$ROOT/infra/apim/inference-stream-operation-policy.xml"

echo "▸ Smoke"
curl -sf "$GATEWAY/health/healthz" >/dev/null
curl -sf "$GATEWAY/well-known/jwks.json" | python3 -c "import sys,json; json.load(sys.stdin)"
curl -sf "$GATEWAY/well-known/openid-configuration" | python3 -c "import sys,json; json.load(sys.stdin)"
echo "APIM WriterFlow surface OK at $GATEWAY"
