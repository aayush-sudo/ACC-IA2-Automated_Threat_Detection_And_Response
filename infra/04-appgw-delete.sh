#!/usr/bin/env bash
# Delete the PAID part only: Application Gateway atdr-appgw and its public IP.
# Keeps the VNet, NSGs, VM, workspace/Sentinel, playbook and the (free) WAF policy,
# so infra/04-appgw-create.sh recreates the gateway identically.
# Note: a recreated public IP will very likely get a NEW address.
set -euo pipefail
source "$(dirname "$0")/common.sh"

APPGW="atdr-appgw"
PIP="atdr-pip-appgw"
LOG_FILE="${APPGW_TIMES_FILE:-$EVIDENCE_DIR/04-appgw-lifecycle.log}"

T_START="$(utc_now)"
if az network application-gateway show -g "$RG" -n "$APPGW" -o none 2>/dev/null; then
  echo "[$T_START] Deleting Application Gateway $APPGW (its diagnostic setting goes with it) — ~5 min"
  az network application-gateway delete -g "$RG" -n "$APPGW"
else
  echo "[$T_START] $APPGW does not exist"
fi
if az network public-ip show -g "$RG" -n "$PIP" -o none 2>/dev/null; then
  echo "[$(utc_now)] Deleting public IP $PIP"
  az network public-ip delete -g "$RG" -n "$PIP"
fi
T_DONE="$(utc_now)"
echo "DELETE started=$T_START done=$T_DONE" >> "$LOG_FILE"

echo "[$T_DONE] Remaining paid gateway resources in $RG:"
az resource list -g "$RG" --query "[?type=='Microsoft.Network/applicationGateways' || type=='Microsoft.Network/publicIPAddresses'].name" -o tsv
echo "[$T_DONE] (empty list above = gateway billing has stopped)"
