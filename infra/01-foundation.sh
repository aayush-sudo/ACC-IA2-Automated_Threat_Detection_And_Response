#!/usr/bin/env bash
# Phase 1 — Foundation: resource group, network, NSGs, backend VM,
# Log Analytics workspace and Microsoft Sentinel. Safe to re-run (az create
# commands are idempotent for these resource types).
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "[$(utc_now)] Resource group $RG in $LOCATION"
az group create -n "$RG" -l "$LOCATION" --tags "${TAGS[@]}" -o none

# ---------------------------------------------------------------- NSGs
echo "[$(utc_now)] NSG $NSG_BACKEND (backend NIC): HTTP 80 only from the gateway subnet + Azure LB"
az network nsg create -g "$RG" -n "$NSG_BACKEND" -l "$LOCATION" --tags "${TAGS[@]}" -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_BACKEND" -n Allow-HTTP-from-AppGw \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$SNET_APPGW_CIDR" --destination-port-ranges 80 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_BACKEND" -n Allow-AzureLoadBalancer \
  --priority 110 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes AzureLoadBalancer --destination-port-ranges '*' -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_BACKEND" -n Deny-All-Other-Inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes '*' --destination-port-ranges '*' -o none

echo "[$(utc_now)] NSG $NSG_APPGW (gateway subnet): rules required by Application Gateway v2"
az network nsg create -g "$RG" -n "$NSG_APPGW" -l "$LOCATION" --tags "${TAGS[@]}" -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_APPGW" -n Allow-HTTP-from-Internet \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-port-ranges 80 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_APPGW" -n Allow-GatewayManager \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes GatewayManager --destination-port-ranges 65200-65535 -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_APPGW" -n Allow-AzureLoadBalancer \
  --priority 120 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes AzureLoadBalancer --destination-port-ranges '*' -o none

echo "[$(utc_now)] NSG $NSG_ISOLATION: deny everything both ways (attached only by the playbook)"
az network nsg create -g "$RG" -n "$NSG_ISOLATION" -l "$LOCATION" \
  --tags "${TAGS[@]}" Role=Isolation -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_ISOLATION" -n Deny-All-Inbound \
  --priority 100 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes '*' --destination-address-prefixes '*' --destination-port-ranges '*' -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG_ISOLATION" -n Deny-All-Outbound \
  --priority 100 --direction Outbound --access Deny --protocol '*' \
  --source-address-prefixes '*' --destination-address-prefixes '*' --destination-port-ranges '*' -o none

# ---------------------------------------------------------------- Network
echo "[$(utc_now)] VNet $VNET with $SNET_APPGW and $SNET_BACKEND"
az network vnet create -g "$RG" -n "$VNET" -l "$LOCATION" --address-prefixes "$VNET_CIDR" \
  --tags "${TAGS[@]}" -o none
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_APPGW" \
  --address-prefixes "$SNET_APPGW_CIDR" --network-security-group "$NSG_APPGW" -o none
# Default outbound access is kept on for the backend subnet so the VM can reach
# Ubuntu package mirrors (no public IP, no NAT gateway cost). It has no inbound effect.
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$SNET_BACKEND" \
  --address-prefixes "$SNET_BACKEND_CIDR" --default-outbound-access true -o none

# ---------------------------------------------------------------- VM
echo "[$(utc_now)] VM $VM_NAME ($VM_SIZE, $VM_IMAGE, no public IP, NIC NSG $NSG_BACKEND)"
if ! az vm show -g "$RG" -n "$VM_NAME" -o none 2>/dev/null; then
  az vm create -g "$RG" -n "$VM_NAME" -l "$LOCATION" \
    --image "$VM_IMAGE" --size "$VM_SIZE" \
    --vnet-name "$VNET" --subnet "$SNET_BACKEND" \
    --public-ip-address "" --nsg "$NSG_BACKEND" \
    --admin-username "$VM_ADMIN" --authentication-type ssh --ssh-key-values "$(cat "$VM_SSH_PUBKEY")" \
    --storage-sku StandardSSD_LRS --os-disk-size-gb 30 \
    --tags "${TAGS[@]}" Role=TestBackend -o none
fi
# az vm create tags the VM only; tag the NIC and OS disk too.
NIC_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query 'networkProfile.networkInterfaces[0].id' -o tsv | tr -d '\r')"
DISK_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query 'storageProfile.osDisk.managedDisk.id' -o tsv | tr -d '\r')"
az tag update --resource-id "$NIC_ID" --operation Merge --tags "${TAGS[@]}" -o none
az tag update --resource-id "$DISK_ID" --operation Merge --tags "${TAGS[@]}" -o none

# ---------------------------------------------------------------- Log Analytics + Sentinel
echo "[$(utc_now)] Log Analytics workspace $LAW (PerGB2018, 30 days, 1 GB/day cap)"
az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" \
  --sku PerGB2018 --retention-time 30 --quota 1 --tags "${TAGS[@]}" -o none

echo "[$(utc_now)] Enable Microsoft Sentinel on $LAW (onboardingStates/default)"
LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv | tr -d '\r')"
az rest --method put \
  --url "https://management.azure.com${LAW_ID}/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01" \
  --body '{"properties":{}}' -o none

echo "[$(utc_now)] Phase 1 foundation complete"
