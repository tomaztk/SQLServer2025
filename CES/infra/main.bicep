// =====================================================================================
//  SQL Server 2025 Change Event Streaming (CES) demo - complete infrastructure
//
//  Deploy into a NEW (or empty) resource group, e.g. rg-ces-demo. The existing SQL VM
//  and its VNet can live in another resource group in the same subscription.
//
//    Existing SQL Server 2025 VM ──(Kafka, TLS, 9093)──▶ Event Hubs (Standard) ──▶ Web app
//          ▲  managed Run Command configures DB + CES          checkpoints ─▶ Storage
//          └──── web app simulator writes DML over VNet integration (1433) ───┘
// =====================================================================================
targetScope = 'resourceGroup'

// ---------------------------------------------------------------- general
@description('Region for the new resources. Use the SQL VM region to avoid cross-region traffic (and data residency surprises).')
param location string = resourceGroup().location

@description('Short prefix for resource names (lowercase letters/digits).')
@maxLength(10)
param namePrefix string = 'cesdemo'

param tags object = {
  workload: 'sql-ces-demo'
  'managed-by': 'bicep'
}

// ---------------------------------------------------------------- existing SQL VM
@description('Name of the existing Azure VM running SQL Server 2025 on Windows.')
param vmName string

@description('Resource group of the existing SQL VM.')
param vmResourceGroup string = resourceGroup().name

@description('Host name or private IP the web app uses to reach SQL Server (e.g. 10.0.0.4).')
param sqlServerHost string

// ---------------------------------------------------------------- networking for the web app
@description('Integrate the web app into the SQL VM VNet so the simulator reaches SQL on its private IP.')
param enableVnetIntegration bool = true
@description('VNet of the SQL VM.')
param vnetName string = ''
param vnetResourceGroup string = vmResourceGroup
param appSubnetName string = 'snet-ces-webapp'
@description('Unused address range inside the VNet for the App Service integration subnet.')
param appSubnetPrefix string = '10.0.250.0/27'

// ---------------------------------------------------------------- CES configuration
@allowed(['SAS', 'ManagedIdentity'])
@description('SAS = Send-only shared access policy (works on every SQL Server 2025 build). ManagedIdentity = Entra auth (SQL Server 2025 CU3+ with Entra configured on the SQL VM).')
param cesAuthMode string = 'SAS'

@description('Principal id SQL Server uses for Entra auth (managed identity mode). Empty = the VM system-assigned identity.')
param sqlManagedIdentityPrincipalId string = ''

param databaseName string = 'CesDemo'
param streamGroupName string = 'CesDemoGroup'
@allowed(['None', 'StreamGroup', 'Table'])
param partitionKeyScheme string = 'Table'
param streamedTables string = 'dbo.Customers,dbo.Products,dbo.Orders,dbo.OrderLines'

@description('Run the SQL configuration on the VM via a managed Run Command. Set false to run the sql/*.sql scripts by hand.')
param configureSqlViaRunCommand bool = true

@description('sysadmin SQL login used by the Run Command (SQL auth must be enabled). Empty = Windows auth as SYSTEM.')
param sqlAdminLogin string = ''
@secure()
param sqlAdminPassword string = ''

param simulatorSqlLogin string = 'ces_simulator'
@secure()
@description('Password for the low-privilege SQL login used by the web app.')
param simulatorSqlPassword string
@secure()
@description('Password protecting the database master key (required for the CES credential).')
param masterKeyPassword string

// ---------------------------------------------------------------- sizing
@minValue(1)
@maxValue(32)
param eventHubPartitionCount int = 4
@allowed(['B1', 'B2', 'S1', 'P0v3', 'P1v3'])
param appServiceSku string = 'B1'

@secure()
@description('Token required by the dashboard for actions that write (simulator, synthetic events). The deploy scripts keep it stable across deployments.')
param dashboardAdminToken string = newGuid()

@description('Optional: your Entra object id, to run the web app locally against the same Event Hub.')
param developerPrincipalId string = ''

@description('Do not set. Forces the Run Command to re-run on every deployment.')
param deploymentStamp string = utcNow()

// ---------------------------------------------------------------- names
var suffix = take(uniqueString(subscription().id, resourceGroup().id, namePrefix), 6)
var names = {
  eventHubNamespace: 'evhns-${namePrefix}-${suffix}'
  eventHub: 'sql-changes'
  consumerGroup: 'dashboard'
  storage: take('st${namePrefix}${suffix}', 24)
  keyVault: take('kv-${namePrefix}-${suffix}', 24)
  logAnalytics: 'log-${namePrefix}-${suffix}'
  appInsights: 'appi-${namePrefix}-${suffix}'
  plan: 'asp-${namePrefix}-${suffix}'
  webApp: 'app-${namePrefix}-${suffix}'
}

resource sqlVm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
  scope: resourceGroup(vmResourceGroup)
}

var sqlPrincipalId = cesAuthMode == 'ManagedIdentity'
  ? (empty(sqlManagedIdentityPrincipalId) ? (sqlVm.?identity.?principalId ?? '') : sqlManagedIdentityPrincipalId)
  : ''

// ---------------------------------------------------------------- modules
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    tags: tags
  }
}

module eventHubs 'modules/eventhubs.bicep' = {
  name: 'eventhubs'
  params: {
    location: location
    namespaceName: names.eventHubNamespace
    eventHubName: names.eventHub
    consumerGroupName: names.consumerGroup
    partitionCount: eventHubPartitionCount
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    storageAccountName: names.storage
    tags: tags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    keyVaultName: names.keyVault
    simulatorSqlPassword: simulatorSqlPassword
    tags: tags
  }
}

module network 'modules/network.bicep' = if (enableVnetIntegration) {
  name: 'network'
  scope: resourceGroup(vnetResourceGroup)
  params: {
    vnetName: vnetName
    subnetName: appSubnetName
    subnetPrefix: appSubnetPrefix
  }
}

module webApp 'modules/webapp.bicep' = {
  name: 'webapp'
  params: {
    location: location
    planName: names.plan
    webAppName: names.webApp
    skuName: appServiceSku
    subnetId: enableVnetIntegration ? network!.outputs.subnetId : ''
    eventHubFqdn: eventHubs.outputs.fullyQualifiedNamespace
    eventHubName: eventHubs.outputs.eventHubName
    consumerGroupName: eventHubs.outputs.consumerGroupName
    checkpointBlobEndpoint: storage.outputs.blobEndpoint
    checkpointContainer: storage.outputs.containerName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    sqlServerHost: sqlServerHost
    sqlDatabaseName: databaseName
    sqlUser: simulatorSqlLogin
    sqlPasswordSecretUri: keyVault.outputs.sqlSecretReferenceUri
    streamGroupName: streamGroupName
    adminToken: dashboardAdminToken
    tags: tags
  }
}

module roles 'modules/roles.bicep' = {
  name: 'roles'
  params: {
    eventHubNamespaceName: eventHubs.outputs.namespaceName
    eventHubName: eventHubs.outputs.eventHubName
    storageAccountName: storage.outputs.storageAccountName
    keyVaultName: keyVault.outputs.keyVaultName
    webAppPrincipalId: webApp.outputs.principalId
    sqlPrincipalId: sqlPrincipalId
    developerPrincipalId: developerPrincipalId
  }
}

module sqlConfig 'modules/sqlvm-config.bicep' = if (configureSqlViaRunCommand) {
  name: 'sqlvm-config'
  scope: resourceGroup(vmResourceGroup)
  dependsOn: [roles] // managed identity mode: Data Sender must exist before the stream group is created
  params: {
    location: sqlVm.location
    vmName: vmName
    eventHubResourceGroup: resourceGroup().name
    eventHubNamespaceName: eventHubs.outputs.namespaceName
    eventHubName: eventHubs.outputs.eventHubName
    senderPolicyName: eventHubs.outputs.senderPolicyName
    cesAuthMode: cesAuthMode
    databaseName: databaseName
    streamGroupName: streamGroupName
    partitionKeyScheme: partitionKeyScheme
    tables: streamedTables
    simulatorLogin: simulatorSqlLogin
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    simulatorSqlPassword: simulatorSqlPassword
    masterKeyPassword: masterKeyPassword
    deploymentStamp: deploymentStamp
  }
}

// ---------------------------------------------------------------- outputs
output webAppName string = webApp.outputs.webAppName
output webAppUrl string = webApp.outputs.url
output eventHubNamespace string = eventHubs.outputs.namespaceName
output eventHubName string = eventHubs.outputs.eventHubName
output cesDestinationLocation string = '${eventHubs.outputs.fullyQualifiedNamespace}:9093/${eventHubs.outputs.eventHubName}'
output storageAccountName string = storage.outputs.storageAccountName
output keyVaultName string = keyVault.outputs.keyVaultName
output sqlPrincipalIdUsed string = sqlPrincipalId
