@description('Storage account for Event Hubs consumer checkpoints (EventHubConsumerClient + BlobCheckpointStore).')
param location string
param storageAccountName string
param containerName string = 'checkpoints'
param tags object = {}

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Entra ID (managed identity) only
    supportsHttpsTrafficOnly: true
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: st
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: containerName
}

output storageAccountName string = st.name
output storageAccountId string = st.id
output blobEndpoint string = st.properties.primaryEndpoints.blob
output containerName string = container.name
