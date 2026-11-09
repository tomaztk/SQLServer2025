@description('Linux App Service running the Node.js CES monitor + change simulator.')
param location string
param planName string
param webAppName string
@allowed(['B1', 'B2', 'S1', 'P0v3', 'P1v3'])
param skuName string = 'B1'
@description('Subnet (delegated to Microsoft.Web/serverFarms) in the SQL VM VNet. Empty = no VNet integration.')
param subnetId string = ''

param eventHubFqdn string
param eventHubName string
param consumerGroupName string
param checkpointBlobEndpoint string
param checkpointContainer string
param appInsightsConnectionString string

param sqlServerHost string
param sqlDatabaseName string
param sqlUser string
param sqlPasswordSecretUri string
param streamGroupName string
@secure()
param adminToken string
param tags object = {}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: { name: skuName }
  properties: { reserved: true }
}

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: webAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    virtualNetworkSubnetId: empty(subnetId) ? null : subnetId
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      alwaysOn: true // the Event Hubs consumer and the simulator run in the background
      webSocketsEnabled: false // the dashboard uses Server-Sent Events
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: '/healthz'
      vnetRouteAllEnabled: false // only private (RFC1918) traffic -> VNet; Event Hubs/Storage go out directly
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'EVENTHUB_FQDN', value: eventHubFqdn }
        { name: 'EVENTHUB_NAME', value: eventHubName }
        { name: 'EVENTHUB_CONSUMER_GROUP', value: consumerGroupName }
        { name: 'CHECKPOINT_BLOB_ENDPOINT', value: checkpointBlobEndpoint }
        { name: 'CHECKPOINT_CONTAINER', value: checkpointContainer }
        { name: 'SQL_SERVER', value: sqlServerHost }
        { name: 'SQL_DATABASE', value: sqlDatabaseName }
        { name: 'SQL_USER', value: sqlUser }
        { name: 'SQL_PASSWORD', value: '@Microsoft.KeyVault(SecretUri=${sqlPasswordSecretUri})' }
        { name: 'SQL_TRUST_SERVER_CERTIFICATE', value: 'true' }
        { name: 'CES_STREAM_GROUP', value: streamGroupName }
        { name: 'SIMULATOR_AUTOSTART', value: 'false' }
        { name: 'ADMIN_TOKEN', value: adminToken }
      ]
    }
  }
}

resource logs 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: site
  name: 'logs'
  properties: {
    applicationLogs: { fileSystem: { level: 'Information' } }
    httpLogs: { fileSystem: { enabled: true, retentionInDays: 3, retentionInMb: 35 } }
  }
}

output webAppName string = site.name
output principalId string = site.identity.principalId
output url string = 'https://${site.properties.defaultHostName}'
