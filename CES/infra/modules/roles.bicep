// RBAC for the data plane. Everything uses Microsoft Entra ID; the only shared key in the
// solution is the Send-only SAS policy for SQL Server (and only when cesAuthMode = 'SAS').
param eventHubNamespaceName string
param eventHubName string
param storageAccountName string
param keyVaultName string

param webAppPrincipalId string
@description('Principal used by SQL Server for CES when cesAuthMode = ManagedIdentity. Empty = skip.')
param sqlPrincipalId string = ''
@description('Optional: your user object id, so you can run the app locally with az login.')
param developerPrincipalId string = ''

var roles = {
  eventHubsDataReceiver: 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'
  eventHubsDataSender: '2b629674-e913-4c01-ae53-ef4638d8f975'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource ns 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: eventHubNamespaceName
}
resource hub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' existing = {
  parent: ns
  name: eventHubName
}
resource st 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// ---- web app: read events, checkpoint, inject synthetic test events, read SQL password
resource webReceive 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hub.id, webAppPrincipalId, roles.eventHubsDataReceiver)
  scope: hub
  properties: {
    principalId: webAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataReceiver)
  }
}
resource webSend 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hub.id, webAppPrincipalId, roles.eventHubsDataSender)
  scope: hub
  properties: {
    principalId: webAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataSender)
  }
}
resource webBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, webAppPrincipalId, roles.storageBlobDataContributor)
  scope: st
  properties: {
    principalId: webAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}
resource webKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, webAppPrincipalId, roles.keyVaultSecretsUser)
  scope: kv
  properties: {
    principalId: webAppPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
  }
}

// ---- SQL Server (managed identity mode): send only, scoped to the single event hub
resource sqlSend 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sqlPrincipalId)) {
  name: guid(hub.id, sqlPrincipalId, roles.eventHubsDataSender)
  scope: hub
  properties: {
    principalId: sqlPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataSender)
  }
}

// ---- developer (local run)
resource devReceive 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(hub.id, developerPrincipalId, roles.eventHubsDataReceiver)
  scope: hub
  properties: {
    principalId: developerPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataReceiver)
  }
}
resource devSend 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(hub.id, developerPrincipalId, roles.eventHubsDataSender)
  scope: hub
  properties: {
    principalId: developerPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.eventHubsDataSender)
  }
}
resource devBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(st.id, developerPrincipalId, roles.storageBlobDataContributor)
  scope: st
  properties: {
    principalId: developerPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}
