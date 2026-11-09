#!/usr/bin/env bash
# Deploys the whole CES demo: infrastructure (Bicep), SQL configuration on the VM (Run Command)
# and the web app code. Re-runnable.
#
#   export CES_SIMULATOR_PASSWORD='...'      # low-privilege SQL login used by the web app
#   export CES_MASTER_KEY_PASSWORD='...'     # database master key password
#   export CES_SQL_ADMIN_LOGIN='sqladmin'    # sysadmin SQL login for the Run Command (optional, see README)
#   export CES_SQL_ADMIN_PASSWORD='...'
#   ./deploy/deploy.sh [resource-group] [location]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="${1:-rg-ces-demo}"
LOCATION="${2:-}"

: "${CES_SIMULATOR_PASSWORD:?set CES_SIMULATOR_PASSWORD}"
: "${CES_MASTER_KEY_PASSWORD:?set CES_MASTER_KEY_PASSWORD}"

command -v az >/dev/null || { echo "Azure CLI (az) is required"; exit 1; }
az account show >/dev/null || az login >/dev/null

if [[ -z "$LOCATION" ]]; then
  # default to the SQL VM's region (read from the parameter file)
  VM_NAME=$(sed -n "s/^param vmName = '\(.*\)'.*/\1/p" "$ROOT/infra/main.bicepparam")
  VM_RG=$(sed -n "s/^param vmResourceGroup = '\(.*\)'.*/\1/p" "$ROOT/infra/main.bicepparam")
  LOCATION=$(az vm show -g "$VM_RG" -n "$VM_NAME" --query location -o tsv)
fi
echo "==> Resource group $RG in $LOCATION"
az group create -n "$RG" -l "$LOCATION" -o none

# Keep the dashboard admin token stable across deployments.
EXISTING_APP=$(az webapp list -g "$RG" --query "[?tags.workload=='sql-ces-demo'].name | [0]" -o tsv 2>/dev/null || true)
ADMIN_TOKEN=""
if [[ -n "$EXISTING_APP" ]]; then
  ADMIN_TOKEN=$(az webapp config appsettings list -g "$RG" -n "$EXISTING_APP" --query "[?name=='ADMIN_TOKEN'].value | [0]" -o tsv || true)
fi
ADMIN_TOKEN="${ADMIN_TOKEN:-$(openssl rand -hex 16)}"

if [[ -z "${CES_DEVELOPER_OBJECT_ID:-}" ]]; then
  export CES_DEVELOPER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
fi

echo "==> Deploying infrastructure + configuring SQL Server (Run Command can take a few minutes)"
az deployment group create \
  -g "$RG" -n "ces-demo-$(date +%Y%m%d%H%M%S)" \
  -f "$ROOT/infra/main.bicep" -p "$ROOT/infra/main.bicepparam" \
  -p dashboardAdminToken="$ADMIN_TOKEN" \
  --query properties.outputs -o json > /tmp/ces-outputs.json

WEBAPP=$(python3 -c "import json;print(json.load(open('/tmp/ces-outputs.json'))['webAppName']['value'])")
URL=$(python3 -c "import json;print(json.load(open('/tmp/ces-outputs.json'))['webAppUrl']['value'])")
DEST=$(python3 -c "import json;print(json.load(open('/tmp/ces-outputs.json'))['cesDestinationLocation']['value'])")

echo "==> Packaging and deploying the web app to $WEBAPP"
PKG="$(mktemp -d)/app.zip"
(cd "$ROOT/app" && zip -qr "$PKG" . -x 'node_modules/*' 'test/*' '.env' '.env.*')
az webapp deploy -g "$RG" -n "$WEBAPP" --src-path "$PKG" --type zip -o none

echo
echo "Done."
echo "  Dashboard:        $URL"
echo "  Admin token:      $ADMIN_TOKEN   (paste into the dashboard's 'Admin token' box)"
echo "  CES destination:  $DEST"
echo "  Run-command log:  az vm run-command show -g <vm-rg> --vm-name <vm> -n configure-sql-ces --expand instanceView --query instanceView.output -o tsv"
