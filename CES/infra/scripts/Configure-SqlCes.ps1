<#
.SYNOPSIS
  Configures the SQL Server 2025 instance on this VM for Change Event Streaming.
  Executed by the Bicep managed run command (infra/modules/sqlvm-config.bicep),
  but you can also run it by hand in an elevated PowerShell on the VM.

  Bicep injects the contents of sql/01_create_demo_database.sql and
  sql/02_enable_ces.sql into the two here-strings below at deploy time.
#>
param(
    [string]$SqlInstance        = 'localhost',
    [string]$SqlAdminLogin      = '',          # empty => Windows integrated auth
    [string]$SqlAdminPassword   = '',
    [string]$DatabaseName       = 'CesDemo',
    [string]$EventHubNamespace  = '',
    [string]$EventHubName       = 'sql-changes',
    [string]$CesAuthMode        = 'SAS',       # SAS | ManagedIdentity
    [string]$SasPolicyName      = 'ces-sender',
    [string]$SasKey             = '',
    [string]$MasterKeyPassword  = '',
    [string]$SimulatorLogin     = 'ces_simulator',
    [string]$SimulatorPassword  = '',
    [string]$StreamGroupName    = 'CesDemoGroup',
    [string]$PartitionKeyScheme = 'Table',
    [string]$MaxMessageSizeKb   = '256',
    [string]$Tables             = 'dbo.Customers,dbo.Products,dbo.Orders,dbo.OrderLines',
    [string]$RecreateStreamGroup = '1',
    [string]$OpenFirewall       = 'true',
    [string]$DeploymentStamp    = ''           # changes every deployment => run command re-runs
)

$ErrorActionPreference = 'Stop'
Write-Output "=== CES configuration started $(Get-Date -Format o) (stamp: $DeploymentStamp) ==="

# ---------------------------------------------------------------- SQL text
$sql01 = @'
#__SQL_01__#
'@

$sql02 = @'
#__SQL_02__#
'@

# ---------------------------------------------------------------- helpers
function New-SqlConnection {
    $cs = "Server=$SqlInstance;Database=master;Encrypt=True;TrustServerCertificate=True;Connect Timeout=30;Application Name=CesDemoSetup;"
    if ([string]::IsNullOrWhiteSpace($SqlAdminLogin)) { $cs += 'Integrated Security=SSPI;' }
    else { $cs += "User ID=$SqlAdminLogin;Password=$SqlAdminPassword;" }
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    # PRINT / RAISERROR(<11) messages; event handlers can't write to the pipeline, so use the console
    $conn.add_InfoMessage({ param($s, $e) foreach ($m in $e.Errors) { [Console]::Out.WriteLine("  [sql] " + $m.Message) } })
    $conn.Open()
    return $conn
}

function Expand-SqlCmdVariables([string]$text, [hashtable]$vars) {
    # drop ':setvar' default lines, then substitute $(Name) tokens; values are quote-escaped
    $text = ($text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*:setvar\s' }) -join "`n"
    $result = [regex]::Replace($text, '\$\((\w+)\)', {
        param($m)
        $name = $m.Groups[1].Value
        if ($vars.ContainsKey($name)) { return ([string]$vars[$name]).Replace("'", "''") }
        throw "SQLCMD variable `$($name) has no value"
    })
    return $result
}

function Invoke-SqlScript([System.Data.SqlClient.SqlConnection]$conn, [string]$name, [string]$text) {
    Write-Output "--- running $name"
    $batches = [regex]::Split($text, '(?im)^\s*GO\s*;?\s*$') | Where-Object { $_.Trim() -ne '' }
    $i = 0
    foreach ($b in $batches) {
        $i++
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $b
        $cmd.CommandTimeout = 600
        try { [void]$cmd.ExecuteNonQuery() }
        catch {
            $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            throw "$name batch $i failed: $msg`n$b"
        }
    }
}

# ---------------------------------------------------------------- checks
if ([string]::IsNullOrWhiteSpace($EventHubNamespace)) { throw 'EventHubNamespace is required' }
if ($CesAuthMode -eq 'SAS' -and [string]::IsNullOrWhiteSpace($SasKey)) { throw 'SasKey is required when CesAuthMode = SAS' }

$ehHost = "$EventHubNamespace.servicebus.windows.net"
try {
    $probe = Test-NetConnection -ComputerName $ehHost -Port 9093 -WarningAction SilentlyContinue
    Write-Output "Outbound to ${ehHost}:9093 (Kafka) reachable: $($probe.TcpTestSucceeded)"
    if (-not $probe.TcpTestSucceeded) { Write-Warning 'CES cannot deliver unless outbound TCP 9093 to Event Hubs is allowed (NSG / firewall / UDR).' }
} catch { Write-Warning "Connectivity probe failed: $_" }

if ($OpenFirewall -eq 'true') {
    if (-not (Get-NetFirewallRule -DisplayName 'SQL Server 1433 (CES demo)' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'SQL Server 1433 (CES demo)' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -Profile Any | Out-Null
        Write-Output 'Windows Firewall: opened TCP 1433 (web app reaches SQL over VNet integration)'
    }
}

$conn = New-SqlConnection
try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS int), CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(20)), @@VERSION"
    $r = $cmd.ExecuteReader(); [void]$r.Read()
    $major = $r.GetInt32(0); $cu = if ($r.IsDBNull(1)) { 'RTM' } else { $r.GetString(1) }; $ver = $r.GetString(2); $r.Close()
    Write-Output "SQL Server: major $major, update level $cu"
    Write-Output ($ver -split "`n")[0]
    if ($major -lt 17) { throw "SQL Server 2025 (17.x) is required for CES, found major version $major" }
    if ($CesAuthMode -eq 'ManagedIdentity') {
        $cuNum = 0; if ($cu -match 'CU(\d+)') { $cuNum = [int]$Matches[1] }
        if ($cuNum -lt 3) { Write-Warning "Managed identity for CES needs SQL Server 2025 CU3+; found $cu. Use CesAuthMode=SAS or patch first." }
    }

    $vars = @{
        DatabaseName = $DatabaseName; SimulatorLogin = $SimulatorLogin; SimulatorPassword = $SimulatorPassword
        EventHubNamespace = $EventHubNamespace; EventHubName = $EventHubName; CesAuthMode = $CesAuthMode
        SasPolicyName = $SasPolicyName; SasKey = $SasKey; MasterKeyPassword = $MasterKeyPassword
        CredentialName = 'CesEventHubCredential'; StreamGroupName = $StreamGroupName
        PartitionKeyScheme = $PartitionKeyScheme; MaxMessageSizeKb = $MaxMessageSizeKb
        Tables = $Tables; RecreateStreamGroup = $RecreateStreamGroup
    }
    Invoke-SqlScript $conn '01_create_demo_database.sql' (Expand-SqlCmdVariables $sql01 $vars)
    Invoke-SqlScript $conn '02_enable_ces.sql'           (Expand-SqlCmdVariables $sql02 $vars)
}
finally { $conn.Close() }

Write-Output "=== CES configuration finished $(Get-Date -Format o) ==="
