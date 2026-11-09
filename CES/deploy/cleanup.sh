#!/usr/bin/env bash
# Removes the Azure side of the demo. Run sql/99_disable_ces.sql on the VM FIRST - otherwise CES
# keeps retrying against a deleted Event Hub and the CesDemo transaction log can't truncate.
#   ./deploy/cleanup.sh rg-ces-demo <vm-rg> <vm-name> <vnet-name> [subnet-name]
set -euo pipefail
RG="${1:?demo resource group}"; VM_RG="${2:?vm resource group}"; VM="${3:?vm name}"; VNET="${4:?vnet name}"
SUBNET="${5:-snet-ces-webapp}"

read -r -p "Did you run sql/99_disable_ces.sql on $VM? [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "Run it first."; exit 1; }

az vm run-command delete -g "$VM_RG" --vm-name "$VM" -n configure-sql-ces --yes -o none || true
az group delete -n "$RG" --yes                 # web app must be gone before the subnet can be removed
az network vnet subnet delete -g "$VM_RG" --vnet-name "$VNET" -n "$SUBNET" -o none || true
# Key Vault is soft-deleted (7 days). Purge it if you want to reuse the name:
#   az keyvault list-deleted --query "[?properties.tags.workload=='sql-ces-demo'].name" -o tsv | xargs -n1 az keyvault purge -n
echo "Removed."
