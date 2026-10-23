#!/usr/bin/env bash
# Phase 4 — create the PAID part: public IP + Application Gateway WAF_v2 (~US$0.50/h in
# centralindia while it exists), attach atdr-wafpolicy, health probe on /health and
# diagnostics to atdr-law. Re-create after infra/04-appgw-delete.sh with the same
# command; everything else (VNet, NSGs, VM, WAF policy) is left untouched.
# Prerequisites: 01-foundation.sh, 02-deploy-webapp.sh, 04a-waf-policy.sh.
set -euo pipefail
source "$(dirname "$0")/common.sh"

APPGW="atdr-appgw"
PIP="atdr-pip-appgw"
POLICY="atdr-wafpolicy"
PROBE="atdr-probe-health"
DIAG="atdr-diag-appgw"
LOG_FILE="${APPGW_TIMES_FILE:-$EVIDENCE_DIR/04-appgw-lifecycle.log}"

BACKEND_IP="$(az vm show -g "$RG" -n "$VM_NAME" -d --query privateIps -o tsv | tr -d '\r')"
POLICY_ID="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv | tr -d '\r')"
LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv | tr -d '\r')"

T_START="$(utc_now)"
echo "[$T_START] Public IP $PIP (Standard, static)"
az network public-ip create -g "$RG" -n "$PIP" -l "$LOCATION" --sku Standard \
  --allocation-method Static --version IPv4 --tags "${TAGS[@]}" -o none

echo "[$(utc_now)] Application Gateway $APPGW (WAF_v2, autoscale 0-2, backend $BACKEND_IP:80) — takes ~5-10 min"
az network application-gateway create -g "$RG" -n "$APPGW" -l "$LOCATION" \
  --sku WAF_v2 --min-capacity 0 --max-capacity 2 \
  --vnet-name "$VNET" --subnet "$SNET_APPGW" --public-ip-address "$PIP" \
  --frontend-port 80 --servers "$BACKEND_IP" \
  --http-settings-port 80 --http-settings-protocol Http \
  --routing-rule-type Basic --priority 100 \
  --waf-policy "$POLICY_ID" --tags "${TAGS[@]}" -o none
T_CREATED="$(utc_now)"
echo "[$T_CREATED] Gateway provisioned"

echo "[$(utc_now)] Health probe $PROBE: GET /health every 30 s"
az network application-gateway probe create -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http --host "$BACKEND_IP" --path /health --interval 30 --timeout 30 \
  --threshold 3 --match-status-codes 200 -o none
az network application-gateway http-settings update -g "$RG" --gateway-name "$APPGW" \
  -n appGatewayBackendHttpSettings --probe "$PROBE" -o none

echo "[$(utc_now)] Diagnostic setting $DIAG -> $LAW (resource-specific: AGWAccessLogs, AGWFirewallLogs)"
APPGW_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query id -o tsv | tr -d '\r')"
az monitor diagnostic-settings create -n "$DIAG" --resource "$APPGW_ID" --workspace "$LAW_ID" \
  --export-to-resource-specific true \
  --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true},{"category":"ApplicationGatewayFirewallLog","enabled":true}]' \
  -o none
T_DONE="$(utc_now)"

PUBLIC_IP="$(az network public-ip show -g "$RG" -n "$PIP" --query ipAddress -o tsv | tr -d '\r')"
{
  echo "CREATE started=$T_START gateway_provisioned=$T_CREATED configuration_done=$T_DONE"
} >> "$LOG_FILE"
echo "[$T_DONE] Done. Gateway URL: http://$PUBLIC_IP/  (billing runs until infra/04-appgw-delete.sh)"
