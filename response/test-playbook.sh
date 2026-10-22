#!/usr/bin/env bash
# Phase 3 test: create a manual Sentinel incident and run atdr-playbook-contain on it
# (same as "Run playbook" on the incident page), wait for the Logic App run and
# print its result, every action's status, and the resulting VM/NIC/snapshot state.
# Usage: bash response/test-playbook.sh <High|Medium|Low> ["title"] [--manual]
#   --manual       only create the incident, then wait (up to 30 min) for someone to
#                  click "Run playbook" on the incident page in the portal.
#   INCIDENT_GUID  env var: reuse this existing incident instead of creating one.
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"

SEVERITY="${1:?severity: High|Medium|Low}"
TITLE="${2:-ATDR TEST – manual ($SEVERITY)}"
MANUAL=false; [[ "${3:-}" == "--manual" ]] && MANUAL=true
WORKFLOW="atdr-playbook-contain"
SCOPE="/subscriptions/$SUB_ID/resourceGroups/$RG"
LAW_ID="$SCOPE/providers/Microsoft.OperationalInsights/workspaces/$LAW"
WF_ID="$SCOPE/providers/Microsoft.Logic/workflows/$WORKFLOW"
ARM="https://management.azure.com"

REUSE=false; [[ -n "${INCIDENT_GUID:-}" ]] && REUSE=true
INCIDENT_GUID="${INCIDENT_GUID:-$(python -c 'import uuid;print(uuid.uuid4())' | tr -d '\r')}"
INCIDENT_ID="$LAW_ID/providers/Microsoft.SecurityInsights/incidents/$INCIDENT_GUID"
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT

if $REUSE; then
  NUMBER="$(az rest --method get --url "$ARM$INCIDENT_ID?api-version=2024-03-01" \
    --query properties.incidentNumber -o tsv | tr -d '\r')"
  echo "[$(utc_now)] Reusing incident #$NUMBER"
else
  # json.dumps escapes non-ASCII (e.g. the en dash) so the Windows az CLI cannot mis-decode it.
  TITLE="$TITLE" SEVERITY="$SEVERITY" python -c 'import json,os,sys; json.dump({"properties":{"title":os.environ["TITLE"],"severity":os.environ["SEVERITY"],"status":"New","description":"Manual test incident for the ATDR containment playbook (no real attack)."}}, open(sys.argv[1],"w"))' "$(winpath "$BODY")"
  echo "[$(utc_now)] Creating incident: $TITLE (severity $SEVERITY)"
  NUMBER="$(az rest --method put --url "$ARM$INCIDENT_ID?api-version=2024-03-01" --body @"$(winpath "$BODY")" \
    --query properties.incidentNumber -o tsv | tr -d '\r')"
  echo "[$(utc_now)] Incident #$NUMBER created (id $INCIDENT_GUID)"
fi

T_RUN="$(utc_now)"
POLLS=60
if $MANUAL; then
  POLLS=180
  echo "[$T_RUN] READY: open Sentinel → Incidents → #$NUMBER → Actions → Run playbook → atdr-playbook-contain"
else
  echo "[$T_RUN] Running playbook on incident #$NUMBER (incidents/runPlaybook)"
  printf '{"logicAppsResourceId":"%s","tenantId":"%s"}' "$WF_ID" "$TENANT_ID" > "$BODY"
  az rest --method post --url "$ARM$INCIDENT_ID/runPlaybook?api-version=2025-07-01-preview" \
    --body @"$(winpath "$BODY")" -o none
fi

echo "[$(utc_now)] Waiting for the Logic App run"
RUN=""
for _ in $(seq 1 "$POLLS"); do
  # Runs are listed newest first. JMESPath cannot order-compare strings, so compare in bash.
  # join() returns one line; a plain list would print one value per line with -o tsv.
  LATEST="$(az rest --method get --url "$ARM$WF_ID/runs?api-version=2016-06-01&\$top=1" \
    --query "join(' ', [value[0].name, value[0].properties.startTime, value[0].properties.status])" -o tsv 2>/dev/null | tr -d '\r' || true)"
  read -r CAND START STATUS <<< "$LATEST" || true
  if [[ -n "${START:-}" && "$START" > "$T_RUN" ]]; then
    RUN="$CAND"
    [[ "$STATUS" != "Running" && "$STATUS" != "Waiting" ]] && break
  fi
  sleep 10
done
[[ -n "$RUN" ]] || { echo "[$(utc_now)] No run started — check Sentinel → Incident → Run playbook in the portal"; exit 1; }

echo "[$(utc_now)] Run $RUN finished"
az rest --method get --url "$ARM$WF_ID/runs/$RUN?api-version=2016-06-01" \
  --query "{run:name,status:properties.status,start:properties.startTime,end:properties.endTime,error:properties.error}" -o json
echo "== Actions (start order)"
az rest --method get --url "$ARM$WF_ID/runs/$RUN/actions?api-version=2016-06-01" \
  --query "sort_by(value,&to_string(properties.startTime))[].{action:name,status:properties.status,code:properties.code,end:properties.endTime}" -o table
echo "== Incident #$NUMBER comments"
az rest --method get --url "$ARM$INCIDENT_ID/comments?api-version=2024-03-01" \
  --query "value[].properties.message" -o tsv | sed 's/<br>/\n   /g; s/<[^>]*>//g'
echo "== State after run"
NIC_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query 'networkProfile.networkInterfaces[0].id' -o tsv | tr -d '\r')"
echo "  NIC NSG:   $(az network nic show --ids "$NIC_ID" --query networkSecurityGroup.id -o tsv | tr -d '\r' | sed 's#.*/##')"
echo "  VM tags:   $(az vm show -g "$RG" -n "$VM_NAME" --query tags -o json | tr -d '\r\n ')"
echo "  Snapshots: $(az snapshot list -g "$RG" --query '[].{n:name,state:provisioningState,incremental:incremental}' -o json | tr -d '\r\n ')"
echo "INCIDENT_NUMBER=$NUMBER RUN_ID=$RUN"
