@description('Location for the Event Hubs namespace.')
param location string
param namespaceName string
param eventHubName string
@description('Kafka endpoint (used by CES on SQL Server 2025) requires Standard or higher.')
@allowed(['Standard', 'Premium'])
param sku string = 'Standard'
param capacity int = 1
@minValue(1)
@maxValue(32)
param partitionCount int = 4
@minValue(1)
@maxValue(7)
param retentionDays int = 1
param consumerGroupName string = 'dashboard'
param senderPolicyName string = 'ces-sender'
param logAnalyticsId string = ''
param tags object = {}

resource ns 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
    capacity: capacity
  }
  properties: {
    // CES over AMQP did not work with TLS 1.3; pin 1.2. Kafka is fine with it too.
    minimumTlsVersion: '1.2'
    // CES can only publish to public endpoints (private endpoints are not supported yet).
    publicNetworkAccess: 'Enabled'
    // SAS (shared access policy) must stay enabled for CesAuthMode = SAS.
    disableLocalAuth: false
    zoneRedundant: false
  }
}

resource hub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ns
  name: eventHubName
  properties: {
    partitionCount: partitionCount
    messageRetentionInDays: retentionDays
  }
}

resource cg 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: hub
  name: consumerGroupName
  properties: {
    userMetadata: 'CES demo dashboard'
  }
}

// Least privilege: Send-only policy scoped to this one event hub (used by SQL Server when CesAuthMode = SAS).
resource sendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: hub
  name: senderPolicyName
  properties: {
    rights: ['Send']
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsId)) {
  name: 'to-log-analytics'
  scope: ns
  properties: {
    workspaceId: logAnalyticsId
    metrics: [{ category: 'AllMetrics', enabled: true }]
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
  }
}

output namespaceName string = ns.name
output namespaceId string = ns.id
output fullyQualifiedNamespace string = '${ns.name}.servicebus.windows.net'
output eventHubName string = hub.name
output eventHubId string = hub.id
output consumerGroupName string = cg.name
output senderPolicyName string = sendRule.name
