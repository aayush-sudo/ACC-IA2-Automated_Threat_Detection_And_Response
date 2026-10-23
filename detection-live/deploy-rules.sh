#!/usr/bin/env bash
# Phase 5 — create/update (idempotent PUT) the two Sentinel analytics rules on atdr-law and the
# automation rule that runs atdr-playbook-contain on every incident they create.
# Rule IDs are fixed so re-running updates the same rules. Usage: bash detection-live/deploy-rules.sh
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"
HERE="$(dirname "$0")"

API="2024-03-01"
PLAYBOOK="atdr-playbook-contain"
RULE_BLOCKS_ID="61f2546c-043a-4cd5-912f-e3e354c6b45a"
RULE_RATE_ID="f28693aa-8349-4ff4-a6d1-77040f2faaf8"
AUTOMATION_ID="4f5cb1ad-17ee-441b-94e7-b3358131d28b"

SI="/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.OperationalInsights/workspaces/$LAW/providers/Microsoft.SecurityInsights"
VM_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv | tr -d '\r')"
PLAYBOOK_ID="$(az resource show -g "$RG" -n "$PLAYBOOK" --resource-type Microsoft.Logic/workflows --query id -o tsv | tr -d '\r')"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Body is built in Python so the en dash in the names is sent as a JSON \u escape (az would mangle it).
rule_body() {  # $1 query file, $2 display name, $3 severity, $4 description, $5 alert name format, $6 out
  QUERY="$(sed "s#__PROTECTED_VM_ID__#$VM_ID#" "$HERE/$1")" NAME="$2" SEV="$3" DESC="$4" FMT="$5" \
  python -c '
import json, os, sys
e = os.environ
json.dump({"kind": "Scheduled", "properties": {
    "displayName": e["NAME"], "description": e["DESC"], "severity": e["SEV"], "enabled": True,
    "query": e["QUERY"], "queryFrequency": "PT5M", "queryPeriod": "PT15M",
    "triggerOperator": "GreaterThan", "triggerThreshold": 0,
    # 15 min suppression = lookback, so the same burst cannot raise a second alert (and re-isolate the
    # VM) on the next two 5-minute runs after a rollback.
    "suppressionEnabled": True, "suppressionDuration": "PT15M",
    "tactics": ["Reconnaissance", "InitialAccess"], "techniques": ["T1595", "T1190"],
    "eventGroupingSettings": {"aggregationKind": "AlertPerResult"},
    "entityMappings": [
        {"entityType": "IP", "fieldMappings": [{"identifier": "Address", "columnName": "ClientIp"}]},
        {"entityType": "AzureResource", "fieldMappings": [{"identifier": "ResourceId", "columnName": "VmResourceId"}]}],
    "customDetails": {"BlockedTransactions": "blockedTransactions"},
    "alertDetailsOverride": {"alertDisplayNameFormat": e["FMT"]},
    "incidentConfiguration": {"createIncident": True, "groupingConfiguration": {
        "enabled": True, "reopenClosedIncident": False, "lookbackDuration": "PT1H",
        "matchingMethod": "Selected", "groupByEntities": ["IP"],
        "groupByAlertDetails": [], "groupByCustomDetails": []}}}}, open(sys.argv[1], "w"))
' "$(winpath "$6")"
}

put() {  # $1 ARM path, $2 body file
  az rest --method put --url "https://management.azure.com$1?api-version=$API" \
    --body @"$(winpath "$2")" --query "{name:name, displayName:properties.displayName}" -o tsv
}

echo "[$(utc_now)] Analytics rule: ATDR – Repeated WAF blocks from one client (High)"
rule_body waf-repeated-blocks.kql "ATDR – Repeated WAF blocks from one client" High \
  "Live version of sentinel-rules/queries/waf-repeated-blocks.kql: at least 5 distinct WAF-blocked transactions from one client IP in 15 minutes. The incident triggers atdr-playbook-contain, which isolates the protected backend VM." \
  "ATDR – Repeated WAF blocks from {{ClientIp}}" "$TMP/blocks.json"
put "$SI/alertRules/$RULE_BLOCKS_ID" "$TMP/blocks.json"

echo "[$(utc_now)] Analytics rule: ATDR – WAF rate limit triggered (Medium)"
rule_body waf-rate-limit.kql "ATDR – WAF rate limit triggered" Medium \
  "Live version of sentinel-rules/queries/waf-rate-limit.kql: at least 3 requests from one client IP blocked by WAF custom rule RateLimitDemo in 15 minutes. Medium: the playbook comments and notifies, no containment." \
  "ATDR – WAF rate limit triggered by {{ClientIp}}" "$TMP/rate.json"
put "$SI/alertRules/$RULE_RATE_ID" "$TMP/rate.json"

echo "[$(utc_now)] Automation rule: run $PLAYBOOK when either rule creates an incident"
RULE_IDS="$SI/alertRules/$RULE_BLOCKS_ID,$SI/alertRules/$RULE_RATE_ID" PLAYBOOK_ID="$PLAYBOOK_ID" TENANT_ID="$TENANT_ID" \
python -c '
import json, os, sys
e = os.environ
json.dump({"properties": {
    "displayName": "ATDR – Run containment playbook on ATDR incidents", "order": 1,
    "triggeringLogic": {"isEnabled": True, "triggersOn": "Incidents", "triggersWhen": "Created",
        "conditions": [{"conditionType": "Property", "conditionProperties": {
            "propertyName": "IncidentRelatedAnalyticRuleIds", "operator": "Contains",
            "propertyValues": e["RULE_IDS"].split(",")}}]},
    "actions": [{"order": 1, "actionType": "RunPlaybook", "actionConfiguration": {
        "logicAppResourceId": e["PLAYBOOK_ID"], "tenantId": e["TENANT_ID"]}}]}}, open(sys.argv[1], "w"))
' "$(winpath "$TMP/automation.json")"
put "$SI/automationRules/$AUTOMATION_ID" "$TMP/automation.json"

echo "[$(utc_now)] Done."
