#!/usr/bin/env bash
# Shared settings for all ATDR infra scripts. Source this file; do not run it.
# Contains no secrets: subscription/tenant IDs are read from `az account show`
# at runtime and are never written to the repository.

# Git Bash on Windows rewrites "/subscriptions/..." into a Windows path; stop it.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

LOCATION="centralindia"
RG="rg-atdr"
TAGS=(Project=ATDR)

VNET="atdr-vnet"
VNET_CIDR="10.10.0.0/16"
SNET_APPGW="snet-appgw"
SNET_APPGW_CIDR="10.10.1.0/24"
SNET_BACKEND="snet-backend"
SNET_BACKEND_CIDR="10.10.2.0/24"

NSG_BACKEND="atdr-nsg-backend"
NSG_APPGW="atdr-nsg-appgw"
NSG_ISOLATION="atdr-nsg-isolation"

VM_NAME="atdr-vm-backend"
VM_SIZE="Standard_B2ats_v2"   # Standard_B1s is not offered in centralindia (see evidence/00)
VM_IMAGE="Ubuntu2404"
VM_ADMIN="azureuser"
# Public key only (required by Azure for Linux VMs). Access is via az vm run-command;
# no SSH port is open. Create with: ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/atdr_vm
VM_SSH_PUBKEY="${VM_SSH_PUBKEY:-$HOME/.ssh/atdr_vm.pub}"

LAW="atdr-law"

SUB_ID="$(az account show --query id -o tsv | tr -d '\r')"
TENANT_ID="$(az account show --query tenantId -o tsv | tr -d '\r')"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$REPO_ROOT/evidence"

# sanitize: replace subscription ID, tenant ID and any e-mail address / guest UPN
# before anything is written to evidence/.
sanitize() {
  sed -E \
    -e "s/${SUB_ID}/<sub-id>/gI" \
    -e "s/${TENANT_ID}/<tenant-id>/gI" \
    -e 's/[A-Za-z0-9._%+-]+#EXT#@[A-Za-z0-9.-]+/<guest-upn>/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g'
}

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# winpath: path usable by the Windows az CLI (Git Bash) or unchanged elsewhere.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
