#!/usr/bin/env bash
# Roll back atdr-playbook-contain on the protected VM:
#   1. re-attach the NSG recorded in the VM tag OriginalNsg to the VM's NIC
#   2. remove the quarantine tags (SecurityStatus, IncidentNumber, QuarantinedAt, OriginalNsg)
#   3. optionally (--delete-snapshot) delete the forensic snapshot atdr-snap-<IncidentNumber>
# Usage: bash response/rollback.sh [--delete-snapshot]
set -euo pipefail
source "$(dirname "$0")/../infra/common.sh"

DELETE_SNAPSHOT=false
[[ "${1:-}" == "--delete-snapshot" ]] && DELETE_SNAPSHOT=true

VM_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv | tr -d '\r')"
tag() { az vm show -g "$RG" -n "$VM_NAME" --query "tags.$1" -o tsv | tr -d '\r'; }
ORIGINAL_NSG="$(tag OriginalNsg)"
INCIDENT="$(tag IncidentNumber)"
NIC_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query 'networkProfile.networkInterfaces[0].id' -o tsv | tr -d '\r')"
CURRENT_NSG="$(az network nic show --ids "$NIC_ID" --query networkSecurityGroup.id -o tsv | tr -d '\r')"

echo "[$(utc_now)] VM $VM_NAME: SecurityStatus='$(tag SecurityStatus)' IncidentNumber='$INCIDENT'"
echo "[$(utc_now)] NIC NSG now:      ${CURRENT_NSG##*/}"
echo "[$(utc_now)] OriginalNsg tag:  ${ORIGINAL_NSG##*/}"

if [[ -z "$ORIGINAL_NSG" || "$ORIGINAL_NSG" == "unknown" ]]; then
  echo "No usable OriginalNsg tag; falling back to $NSG_BACKEND"
  ORIGINAL_NSG="$(az network nsg show -g "$RG" -n "$NSG_BACKEND" --query id -o tsv | tr -d '\r')"
fi
if [[ "${ORIGINAL_NSG,,}" == *"/$NSG_ISOLATION" ]]; then
  echo "Refusing: OriginalNsg points at the isolation NSG; using $NSG_BACKEND instead"
  ORIGINAL_NSG="$(az network nsg show -g "$RG" -n "$NSG_BACKEND" --query id -o tsv | tr -d '\r')"
fi

echo "[$(utc_now)] Re-attaching ${ORIGINAL_NSG##*/} to ${NIC_ID##*/}"
az network nic update --ids "$NIC_ID" --network-security-group "$ORIGINAL_NSG" -o none

echo "[$(utc_now)] Removing quarantine tags"
for t in SecurityStatus IncidentNumber QuarantinedAt OriginalNsg; do
  if [[ -n "$(tag "$t")" ]]; then
    az vm update -g "$RG" -n "$VM_NAME" --remove "tags.$t" -o none
  fi
done

if $DELETE_SNAPSHOT && [[ -n "$INCIDENT" ]]; then
  echo "[$(utc_now)] Deleting snapshot atdr-snap-$INCIDENT"
  az snapshot delete -g "$RG" -n "atdr-snap-$INCIDENT" -o none
fi

echo "[$(utc_now)] Verify"
echo "  NIC NSG:  $(az network nic show --ids "$NIC_ID" --query networkSecurityGroup.id -o tsv | tr -d '\r' | sed 's#.*/##')"
echo "  VM tags:  $(az vm show -g "$RG" -n "$VM_NAME" --query tags -o json | tr -d '\r\n ' )"
echo "  Snapshots in $RG: $(az snapshot list -g "$RG" --query '[].name' -o tsv | tr -d '\r' | tr '\n' ' ')"
