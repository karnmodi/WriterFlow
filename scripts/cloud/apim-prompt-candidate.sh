#!/usr/bin/env bash
# Creates or removes an authenticated, temporary APIM path to one zero-traffic
# Container Apps revision. It never changes the production API or its traffic.
set -euo pipefail

WF_ACTION="${1:-setup}"
WF_REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WF_RESOURCE_GROUP="${WF_RESOURCE_GROUP:-rg_writerflow_prod}"
WF_APIM_NAME="${WF_APIM_NAME:-wfprod-apim-dev}"
WF_API_ID="${WF_API_ID:-writerflow-v2-prompt-candidate}"
WF_API_PATH="${WF_API_PATH:-v2-prompt-candidate}"
WF_API_BACKEND="${WF_API_BACKEND:-}"
WF_SUBSCRIPTION_ID="${WF_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

if [[ "$WF_ACTION" == "delete" ]]; then
  az apim api delete \
    --resource-group "$WF_RESOURCE_GROUP" \
    --service-name "$WF_APIM_NAME" \
    --api-id "$WF_API_ID" \
    --delete-revisions true \
    --yes \
    --only-show-errors \
    --output none
  exit 0
fi

if [[ "$WF_ACTION" != "setup" || -z "$WF_API_BACKEND" ]]; then
  echo "Usage: WF_API_BACKEND=https://revision-fqdn $0 setup|delete" >&2
  exit 2
fi

put_policy() {
  local scope=$1
  local file=$2
  local xml
  xml=$(python3 -c "import json; print(json.dumps(open('$file').read()))")
  az rest --method put \
    --uri "https://management.azure.com/subscriptions/$WF_SUBSCRIPTION_ID/resourceGroups/$WF_RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$WF_APIM_NAME/$scope/policies/policy?api-version=2023-03-01-preview" \
    --headers "Content-Type=application/json" \
    --body "{\"properties\":{\"format\":\"rawxml\",\"value\":$xml}}" \
    --output none
}

if az apim api show -g "$WF_RESOURCE_GROUP" --service-name "$WF_APIM_NAME" --api-id "$WF_API_ID" --output none 2>/dev/null; then
  az apim api update \
    -g "$WF_RESOURCE_GROUP" \
    -n "$WF_APIM_NAME" \
    --api-id "$WF_API_ID" \
    --path "$WF_API_PATH" \
    --service-url "$WF_API_BACKEND" \
    --protocols https \
    --subscription-required false \
    --only-show-errors \
    --output none
else
  az apim api create \
    -g "$WF_RESOURCE_GROUP" \
    -n "$WF_APIM_NAME" \
    --api-id "$WF_API_ID" \
    --display-name "WriterFlow prompt candidate" \
    --path "$WF_API_PATH" \
    --service-url "$WF_API_BACKEND" \
    --protocols https \
    --subscription-required false \
    --only-show-errors \
    --output none

  az apim api operation create -g "$WF_RESOURCE_GROUP" -n "$WF_APIM_NAME" --api-id "$WF_API_ID" \
    --operation-id device-authorize --display-name "Device authorize" --method POST --url-template /device/authorize --output none
  az apim api operation create -g "$WF_RESOURCE_GROUP" -n "$WF_APIM_NAME" --api-id "$WF_API_ID" \
    --operation-id device-token --display-name "Device token" --method POST --url-template /device/token --output none
  az apim api operation create -g "$WF_RESOURCE_GROUP" -n "$WF_APIM_NAME" --api-id "$WF_API_ID" \
    --operation-id token-refresh --display-name "Token refresh" --method POST --url-template /token/refresh --output none
  az apim api operation create -g "$WF_RESOURCE_GROUP" -n "$WF_APIM_NAME" --api-id "$WF_API_ID" \
    --operation-id inference-stream --display-name "Inference stream" --method POST --url-template /inference/stream --output none
  az apim api operation create -g "$WF_RESOURCE_GROUP" -n "$WF_APIM_NAME" --api-id "$WF_API_ID" \
    --operation-id device-revoke --display-name "Revoke device" --method DELETE --url-template '/devices/{id}' \
    --template-parameters name=id type=string required=true --output none
fi

put_policy "apis/$WF_API_ID" "$WF_REPO_ROOT/infra/apim/api-policy-dev.xml"
put_policy "apis/$WF_API_ID/operations/device-authorize" "$WF_REPO_ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/$WF_API_ID/operations/device-token" "$WF_REPO_ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/$WF_API_ID/operations/token-refresh" "$WF_REPO_ROOT/infra/apim/pairing-operations-policy-dev.xml"
put_policy "apis/$WF_API_ID/operations/inference-stream" "$WF_REPO_ROOT/infra/apim/inference-stream-operation-policy.xml"
