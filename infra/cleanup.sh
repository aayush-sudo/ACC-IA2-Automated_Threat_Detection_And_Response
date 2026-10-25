#!/usr/bin/env bash
# Cleanup in two steps.
#
#   bash infra/cleanup.sh
#       STEP 1 (run right after the final recording): switch the automation rule off and delete the
#       paid part, the Application Gateway atdr-appgw and its public IP (~US$0.50/h). Keeps the VNet,
#       VM, workspace/Sentinel, playbook, rules and the free WAF policy, so infra/04-appgw-create.sh
#       can bring the gateway back for a re-test.
#
#   bash infra/cleanup.sh --delete-resource-group
#       STEP 2 (only after the project is marked and Anthony has agreed): delete the WHOLE resource
#       group rg-atdr: VM, disk, workspace with all logs and incidents, Sentinel, playbook, roles.
#       Irreversible. Asks you to type the resource group name; it never runs non-interactively.
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [[ "${1:-}" != "--delete-resource-group" ]]; then
  echo "[$(utc_now)] STEP 1: automation rule off, then delete gateway + public IP"
  bash "$REPO_ROOT/detection-live/automation-rule.sh" off || echo "(automation rule not found; continuing)"
  bash "$REPO_ROOT/infra/04-appgw-delete.sh"
  echo "[$(utc_now)] Remaining resources in $RG:"
  az resource list -g "$RG" --query "[].{name:name, type:type}" -o table
  echo "STEP 2 (delete everything) is separate: bash infra/cleanup.sh --delete-resource-group"
  exit 0
fi

echo "STEP 2: this deletes resource group '$RG' and EVERYTHING in it:"
az resource list -g "$RG" --query "[].name" -o tsv | sed 's/^/  - /'
if [[ ! -t 0 ]]; then
  echo "Refusing: step 2 must be run by a person in an interactive terminal." >&2
  exit 1
fi
read -r -p "Type the resource group name ($RG) to confirm: " answer
[[ "$answer" == "$RG" ]] || { echo "Not confirmed; nothing deleted."; exit 1; }
echo "[$(utc_now)] Deleting $RG (takes several minutes)"
az group delete -n "$RG" --yes
echo "[$(utc_now)] Deleted. Check remaining: az group exists -n $RG -> $(az group exists -n "$RG")"
echo "Not removed by this script: the two guest teammate accounts in the tenant (Entra ID -> Users) and"
echo "the budget alerts set in Cost Management. Remove them in the portal if they are no longer needed."
