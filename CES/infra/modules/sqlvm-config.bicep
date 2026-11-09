// Deployed into the resource group of the existing SQL Server 2025 VM.
// A managed Run Command executes infra/scripts/Configure-SqlCes.ps1 on the VM, which runs
// sql/01_create_demo_database.sql and sql/02_enable_ces.sql against the local instance.
param location string
param vmName string

param eventHubResourceGroup string
param eventHubNamespaceName string
param eventHubName string
param senderPolicyName string

@allowed(['SAS', 'ManagedIdentity'])
param cesAuthMode string = 'SAS'
param databaseName string
param streamGroupName string
param partitionKeyScheme string
param tables string
param simulatorLogin string

@description('SQL login with sysadmin rights used by the run command. Empty = Windows auth as SYSTEM (only works if NT AUTHORITY\\SYSTEM is sysadmin).')
param sqlAdminLogin string
@secure()
param sqlAdminPassword string
@secure()
param simulatorSqlPassword string
@secure()
param masterKeyPassword string

@description('Changes on every deployment so the run command re-executes (managed run commands only run when their definition changes).')
param deploymentStamp string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource sendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' existing = {
  name: '${eventHubNamespaceName}/${eventHubName}/${senderPolicyName}'
  scope: resourceGroup(eventHubResourceGroup)
}

var script = replace(
  replace(
    loadTextContent('../scripts/Configure-SqlCes.ps1'),
    '#__SQL_01__#',
    loadTextContent('../../sql/01_create_demo_database.sql')
  ),
  '#__SQL_02__#',
  loadTextContent('../../sql/02_enable_ces.sql')
)

resource configureCes 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  parent: vm
  name: 'configure-sql-ces'
  location: location
  properties: {
    source: { script: script }
    asyncExecution: false
    timeoutInSeconds: 1800
    treatFailureAsDeploymentFailure: true
    parameters: [
      { name: 'SqlInstance', value: 'localhost' }
      { name: 'SqlAdminLogin', value: sqlAdminLogin }
      { name: 'DatabaseName', value: databaseName }
      { name: 'EventHubNamespace', value: eventHubNamespaceName }
      { name: 'EventHubName', value: eventHubName }
      { name: 'CesAuthMode', value: cesAuthMode }
      { name: 'SasPolicyName', value: senderPolicyName }
      { name: 'SimulatorLogin', value: simulatorLogin }
      { name: 'StreamGroupName', value: streamGroupName }
      { name: 'PartitionKeyScheme', value: partitionKeyScheme }
      { name: 'Tables', value: tables }
      { name: 'RecreateStreamGroup', value: '1' }
      { name: 'OpenFirewall', value: 'true' }
      { name: 'DeploymentStamp', value: deploymentStamp }
    ]
    protectedParameters: [
      { name: 'SqlAdminPassword', value: sqlAdminPassword }
      { name: 'SasKey', value: cesAuthMode == 'SAS' ? sendRule.listKeys().primaryKey : 'not-used' }
      { name: 'SimulatorPassword', value: simulatorSqlPassword }
      { name: 'MasterKeyPassword', value: masterKeyPassword }
    ]
  }
}

output runCommandName string = configureCes.name
