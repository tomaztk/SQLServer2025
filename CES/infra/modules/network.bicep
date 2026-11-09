// Deployed into the resource group of the SQL VM's virtual network.
// Adds a subnet delegated to App Service so the web app reaches SQL Server on its private IP.
param vnetName string
param subnetName string
@description('Free address range inside the VNet, /28 or larger (a /27 is recommended for App Service).')
param subnetPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetPrefix
    delegations: [
      {
        name: 'appservice'
        properties: { serviceName: 'Microsoft.Web/serverFarms' }
      }
    ]
  }
}

output subnetId string = subnet.id
