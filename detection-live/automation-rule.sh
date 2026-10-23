#!/usr/bin/env bash
# One-line switch for the ATDR automation rule (incident -> atdr-playbook-contain).
# Keep it OFF between sessions, so an internet scanner cannot isolate the VM while nobody is watching;
# tests/e2e_run.sh turns it on at the start of a run and off again at the end.
# Usage: bash detection-live/automation-rule.sh on|off|status
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"
source "$(dirname "$0")/rule-ids.sh"
URL="https://management.azure.com$SI/automationRules/$AUTOMATION_ID?api-version=2024-03-01"

case "${1:-status}" in
  on) WANT=true ;;
  off) WANT=false ;;
  status) WANT="" ;;
  *) echo "usage: automation-rule.sh on|off|status" >&2; exit 2 ;;
esac

if [[ -n "$WANT" ]]; then
  TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
  # GET -> flip isEnabled -> PUT. az output on Windows may be cp1252; Python re-encodes the en dash as –.
  az rest --method get --url "$URL" -o json | WANT="$WANT" python -c '
import json, os, sys
raw = sys.stdin.buffer.read()
try: rule = json.loads(raw.decode("utf-8"))
except UnicodeDecodeError: rule = json.loads(raw.decode("cp1252"))
p = rule["properties"]
for k in ("createdBy", "lastModifiedBy", "createdTimeUtc", "lastModifiedTimeUtc"): p.pop(k, None)
p["triggeringLogic"]["isEnabled"] = os.environ["WANT"] == "true"
json.dump({"properties": p}, open(sys.argv[1], "w"))
' "$(winpath "$TMP")"
  az rest --method put --url "$URL" --body @"$(winpath "$TMP")" -o none
fi
STATE="$(az rest --method get --url "$URL" --query "properties.triggeringLogic.isEnabled" -o tsv | tr -d '\r')"
echo "[$(utc_now)] ATDR automation rule enabled=$STATE"
