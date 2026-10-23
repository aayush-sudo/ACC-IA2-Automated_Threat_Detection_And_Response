#!/usr/bin/env bash
# Roll back atdr-playbook-contain on the protected VM:
#   1. re-attach the NSG recorded in the VM tag OriginalNsg to the VM's NIC
#   2. remove the quarantine tags (SecurityStatus, IncidentNumber, QuarantinedAt, OriginalNsg)
#      in ONE call to the ARM tags API (no full VM update)
#   3. optionally (--delete-snapshot) delete the forensic snapshot atdr-snap-<IncidentNumber>
# Usage: bash response/rollback.sh [--delete-snapshot] [--dry-run]
#   --dry-run  print what would be changed and change nothing
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"

DELETE_SNAPSHOT=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --delete-snapshot) DELETE_SNAPSHOT=true ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
run() { if $DRY_RUN; then echo "  DRY-RUN would run: $*" | sed -E 's#/subscriptions/[^ ]*/([^/ ]+)#…/\1#g'; else "$@"; fi; }

QUARANTINE_TAGS=(SecurityStatus IncidentNumber QuarantinedAt OriginalNsg)

# One read of the VM: id, NIC id and the quarantine tag values ('|'-separated).
IFS='|' read -r VM_ID NIC_ID ORIGINAL_NSG INCIDENT STATUS QUARANTINED_AT < <(
  az vm show -g "$RG" -n "$VM_NAME" -o tsv --query "join('|', [id, networkProfile.networkInterfaces[0].id, tags.OriginalNsg || '', tags.IncidentNumber || '', tags.SecurityStatus || '', tags.QuarantinedAt || ''])" \
    | tr -d '\r')
ORIGINAL_NSG_TAG="$ORIGINAL_NSG"
CURRENT_NSG="$(az network nic show --ids "$NIC_ID" --query networkSecurityGroup.id -o tsv | tr -d '\r')"
BACKEND_NSG_ID="$(az network nsg show -g "$RG" -n "$NSG_BACKEND" --query id -o tsv | tr -d '\r')"

$DRY_RUN && echo "[$(utc_now)] DRY RUN — no changes will be made"
echo "[$(utc_now)] VM $VM_NAME: SecurityStatus='$STATUS' IncidentNumber='$INCIDENT' QuarantinedAt='$QUARANTINED_AT'"
echo "[$(utc_now)] NIC NSG now:      ${CURRENT_NSG##*/}"
echo "[$(utc_now)] OriginalNsg tag:  ${ORIGINAL_NSG##*/}"

if [[ -z "$ORIGINAL_NSG" || "$ORIGINAL_NSG" == "unknown" ]]; then
  echo "No usable OriginalNsg tag; falling back to $NSG_BACKEND"
  ORIGINAL_NSG="$BACKEND_NSG_ID"
fi
if [[ "${ORIGINAL_NSG,,}" == *"/$NSG_ISOLATION" ]]; then
  echo "Refusing: OriginalNsg points at the isolation NSG; using $NSG_BACKEND instead"
  ORIGINAL_NSG="$BACKEND_NSG_ID"
fi

if [[ "${CURRENT_NSG,,}" == "${ORIGINAL_NSG,,}" ]]; then
  echo "[$(utc_now)] NIC already uses ${ORIGINAL_NSG##*/}; no NIC change needed"
else
  echo "[$(utc_now)] Re-attaching ${ORIGINAL_NSG##*/} to ${NIC_ID##*/}"
  run az network nic update --ids "$NIC_ID" --network-security-group "$ORIGINAL_NSG" -o none
fi

# Delete exactly the quarantine tags that are present, as key=value pairs, in a single call.
declare -A VALUES=([SecurityStatus]="$STATUS" [IncidentNumber]="$INCIDENT"
                   [QuarantinedAt]="$QUARANTINED_AT" [OriginalNsg]="$ORIGINAL_NSG_TAG")
DELETE_ARGS=()
for t in "${QUARANTINE_TAGS[@]}"; do
  [[ -n "${VALUES[$t]}" ]] && DELETE_ARGS+=("$t=${VALUES[$t]}")
done
if (( ${#DELETE_ARGS[@]} )); then
  echo "[$(utc_now)] Removing quarantine tags in one call: ${DELETE_ARGS[*]%%=*}"
  run az tag update --resource-id "$VM_ID" --operation Delete --tags "${DELETE_ARGS[@]}" -o none
else
  echo "[$(utc_now)] No quarantine tags present"
fi

if $DELETE_SNAPSHOT && [[ -n "$INCIDENT" ]]; then
  if az snapshot show -g "$RG" -n "atdr-snap-$INCIDENT" -o none 2>/dev/null; then
    echo "[$(utc_now)] Deleting snapshot atdr-snap-$INCIDENT"
    run az snapshot delete -g "$RG" -n "atdr-snap-$INCIDENT" -o none
  else
    echo "[$(utc_now)] Snapshot atdr-snap-$INCIDENT not found; nothing to delete"
  fi
fi

echo "[$(utc_now)] Verify"
echo "  NIC NSG:  $(az network nic show --ids "$NIC_ID" --query networkSecurityGroup.id -o tsv | tr -d '\r' | sed 's#.*/##')"
echo "  VM tags:  $(az vm show -g "$RG" -n "$VM_NAME" --query tags -o json | tr -d '\r\n ' )"
echo "  Snapshots in $RG: $(az snapshot list -g "$RG" --query '[].name' -o tsv | tr -d '\r' | tr '\n' ' ')"
