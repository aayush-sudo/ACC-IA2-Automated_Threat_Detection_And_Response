#!/usr/bin/env bash
# Phase 3 — deploy atdr-playbook-contain + its Sentinel API connection, then grant
# least-privilege roles (scoped to rg-atdr only).
#
# The Discord webhook URL is read from the environment and passed to ARM as a
# securestring through a temporary parameters file that is deleted afterwards:
#   NOTIFY_WEBHOOK_URL='https://discord.com/api/webhooks/...' bash response/deploy-playbook.sh
# Use --placeholder to deploy before a webhook exists (notifications will fail).
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"

WORKFLOW="atdr-playbook-contain"
CONNECTION="atdr-conn-sentinel"
SENTINEL_APP_ID="98785600-1bb7-4fb9-b9fa-19afe2c8a360"   # "Azure Security Insights" first-party app

if [[ "${1:-}" == "--placeholder" ]]; then
  NOTIFY_WEBHOOK_URL="https://example.invalid/atdr-webhook-not-configured"
fi
: "${NOTIFY_WEBHOOK_URL:?Set NOTIFY_WEBHOOK_URL (Discord webhook) or pass --placeholder}"
export NOTIFY_WEBHOOK_URL

VM_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv | tr -d '\r')"
ISO_NSG_ID="$(az network nsg show -g "$RG" -n "$NSG_ISOLATION" --query id -o tsv | tr -d '\r')"
SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG"

PARAMS="$(mktemp)"
trap 'rm -f "$PARAMS"' EXIT
chmod 600 "$PARAMS"
python - "$(winpath "$PARAMS")" "$VM_ID" "$ISO_NSG_ID" <<'PY'
import json, os, sys
path, vm, nsg = sys.argv[1:4]
json.dump({"protectedVmId": {"value": vm}, "isolationNsgId": {"value": nsg},
           "notifyTo": {"value": os.environ["NOTIFY_WEBHOOK_URL"]}}, open(path, "w"))
PY

echo "[$(utc_now)] Deploying $WORKFLOW and $CONNECTION"
PRINCIPAL_ID="$(az deployment group create -g "$RG" -n "atdr-playbook-$(date -u +%Y%m%d%H%M%S)" \
  --template-file "$(winpath "$REPO_ROOT/response/playbook-contain.template.json")" \
  --parameters @"$(winpath "$PARAMS")" \
  --query properties.outputs.principalId.value -o tsv | tr -d '\r')"
rm -f "$PARAMS"
echo "[$(utc_now)] Managed identity principal: $PRINCIPAL_ID"

grant() {  # grant <principalId> <principalType> <role>
  if [[ -z "$(az role assignment list --assignee "$1" --role "$3" --scope "$SCOPE" --query '[0].id' -o tsv)" ]]; then
    az role assignment create --assignee-object-id "$1" --assignee-principal-type "$2" \
      --role "$3" --scope "$SCOPE" -o none
  fi
  echo "  $3 -> $2 on $RG"
}
echo "[$(utc_now)] Least-privilege roles for the playbook identity"
for role in "Microsoft Sentinel Responder" "Network Contributor" "Virtual Machine Contributor" "Disk Snapshot Contributor"; do
  grant "$PRINCIPAL_ID" ServicePrincipal "$role"
done

echo "[$(utc_now)] Allow Microsoft Sentinel automation rules to run playbooks in $RG"
SENTINEL_SP="$(az ad sp show --id "$SENTINEL_APP_ID" --query id -o tsv | tr -d '\r')"
grant "$SENTINEL_SP" ServicePrincipal "Microsoft Sentinel Automation Contributor"

echo "[$(utc_now)] Exporting the deployed workflow definition (no parameter values) to response/"
az rest --method get \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.Logic/workflows/$WORKFLOW?api-version=2019-05-01" \
  --query "properties.definition" -o json | sanitize > "$REPO_ROOT/response/playbook-contain.workflow-definition.json"
echo "[$(utc_now)] Done"
