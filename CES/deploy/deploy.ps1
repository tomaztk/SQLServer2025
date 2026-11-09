#Requires -Version 7.0
# PowerShell 7+: Compress-Archive in Windows PowerShell 5.1 writes backslash paths that break Linux App Service.
<#
.SYNOPSIS
  Deploys the CES demo: Bicep infrastructure, SQL configuration on the VM (Run Command), web app code.

.EXAMPLE
  $env:CES_SIMULATOR_PASSWORD  = '...'
  $env:CES_MASTER_KEY_PASSWORD = '...'
  $env:CES_SQL_ADMIN_LOGIN     = 'sqladmin'
  $env:CES_SQL_ADMIN_PASSWORD  = '...'
  ./deploy/deploy.ps1 -ResourceGroup rg-ces-demo
#>
param(
    [string]$ResourceGroup = 'rg-ces-demo',
    [string]$Location = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $env:CES_SIMULATOR_PASSWORD) { throw 'Set $env:CES_SIMULATOR_PASSWORD' }
if (-not $env:CES_MASTER_KEY_PASSWORD) { throw 'Set $env:CES_MASTER_KEY_PASSWORD' }
az account show 1>$null 2>$null; if ($LASTEXITCODE -ne 0) { az login | Out-Null }

$paramFile = Join-Path $root 'infra/main.bicepparam'
if (-not $Location) {
    $text  = Get-Content $paramFile -Raw
    $vm    = [regex]::Match($text, "param vmName = '([^']+)'").Groups[1].Value
    $vmRg  = [regex]::Match($text, "param vmResourceGroup = '([^']+)'").Groups[1].Value
    $Location = az vm show -g $vmRg -n $vm --query location -o tsv
}
Write-Host "==> Resource group $ResourceGroup in $Location"
az group create -n $ResourceGroup -l $Location -o none

$existing = az webapp list -g $ResourceGroup --query "[?tags.workload=='sql-ces-demo'].name | [0]" -o tsv 2>$null
$adminToken = $null
if ($existing) { $adminToken = az webapp config appsettings list -g $ResourceGroup -n $existing --query "[?name=='ADMIN_TOKEN'].value | [0]" -o tsv }
if (-not $adminToken) { $adminToken = [guid]::NewGuid().ToString('N') }

if (-not $env:CES_DEVELOPER_OBJECT_ID) { $env:CES_DEVELOPER_OBJECT_ID = (az ad signed-in-user show --query id -o tsv 2>$null) }

Write-Host '==> Deploying infrastructure + configuring SQL Server (Run Command can take a few minutes)'
$out = az deployment group create -g $ResourceGroup -n "ces-demo-$(Get-Date -Format yyyyMMddHHmmss)" `
    -f (Join-Path $root 'infra/main.bicep') -p $paramFile -p dashboardAdminToken=$adminToken `
    --query properties.outputs -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Deployment failed' }

$webApp = $out.webAppName.value
Write-Host "==> Packaging and deploying the web app to $webApp"
$staging = Join-Path ([IO.Path]::GetTempPath()) "ces-app-$(Get-Random)"
New-Item -ItemType Directory $staging | Out-Null
Get-ChildItem (Join-Path $root 'app') -Force | Where-Object { $_.Name -notin @('node_modules', 'test', '.env') } |
    Copy-Item -Destination $staging -Recurse
$zip = "$staging.zip"
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip -Force
az webapp deploy -g $ResourceGroup -n $webApp --src-path $zip --type zip -o none

Write-Host ''
Write-Host 'Done.'
Write-Host "  Dashboard:        $($out.webAppUrl.value)"
Write-Host "  Admin token:      $adminToken"
Write-Host "  CES destination:  $($out.cesDestinationLocation.value)"
