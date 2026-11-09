using 'main.bicep'

// ---- your existing SQL Server 2025 VM ------------------------------------------
param vmName = 'vm-sql2025'                 // <-- change
param vmResourceGroup = 'rg-sql2025'        // <-- change
param sqlServerHost = '10.0.0.4'            // <-- private IP of the VM
param vnetName = 'vnet-sql2025'             // <-- VNet of the VM
param vnetResourceGroup = 'rg-sql2025'
param appSubnetPrefix = '10.0.250.0/27'     // <-- an unused range in that VNet

// ---- CES --------------------------------------------------------------------------
param cesAuthMode = 'SAS'                   // or 'ManagedIdentity' (SQL Server 2025 CU3+)
param partitionKeyScheme = 'Table'

// ---- SQL logins / secrets (read from environment variables, never commit them) ---
param sqlAdminLogin = readEnvironmentVariable('CES_SQL_ADMIN_LOGIN', '')
param sqlAdminPassword = readEnvironmentVariable('CES_SQL_ADMIN_PASSWORD', '')
param simulatorSqlPassword = readEnvironmentVariable('CES_SIMULATOR_PASSWORD')
param masterKeyPassword = readEnvironmentVariable('CES_MASTER_KEY_PASSWORD')

// ---- optional -----------------------------------------------------------------------
param developerPrincipalId = readEnvironmentVariable('CES_DEVELOPER_OBJECT_ID', '')
