@description('Key Vault holding the simulator SQL password (consumed by the web app via a Key Vault reference).')
param location string
param keyVaultName string
@secure()
param simulatorSqlPassword string
param tags object = {}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlPwd 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'sql-simulator-password'
  properties: {
    value: simulatorSqlPassword
    contentType: 'text/plain'
  }
}

output keyVaultName string = kv.name
output keyVaultId string = kv.id
output sqlSecretReferenceUri string = sqlPwd.properties.secretUri
