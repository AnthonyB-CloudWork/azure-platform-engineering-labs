param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Target = "learn.microsoft.com",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 443
)

# Collect active network adapters that have an IPv4 address.
$activeAdapters = Get-NetIPConfiguration | Where-Object {
    $_.NetAdapter.Status -eq "Up" -and $_.IPv4Address
}

# Convert the network adapter information into structured objects.
$adapterInventory = foreach ($adapter in $activeAdapters) {

    # Retrieve the IPv4 DNS servers assigned to this adapter.
    $dnsServers = Get-DnsClientServerAddress `
        -InterfaceIndex $adapter.InterfaceIndex `
        -AddressFamily IPv4

    [PSCustomObject]@{
        InterfaceAlias = $adapter.InterfaceAlias
        IPv4Address    = $adapter.IPv4Address.IPAddress -join ", "
        PrefixLength   = $adapter.IPv4Address.PrefixLength -join ", "
        DefaultGateway = if ($adapter.IPv4DefaultGateway) {
            $adapter.IPv4DefaultGateway.NextHop
        }
        else {
            "None"
        }
        DnsServers     = $dnsServers.ServerAddresses -join ", "
    }
}

# Test whether DNS can resolve Microsoft's Learn website.
$dnsResolutionSucceeded = $false

try {
    Resolve-DnsName `
        -Name $Target `
        -Type A `
        -ErrorAction Stop |
        Out-Null

    $dnsResolutionSucceeded = $true
}
catch {
    $dnsResolutionSucceeded = $false
}

# Test whether an HTTPS connection can reach port 443.
$tcpConnectionSucceeded = Test-NetConnection `
    -ComputerName $Target `
    -Port $Port `
    -InformationLevel Quiet

# Organize the connectivity test results.
$connectivityTests = [PSCustomObject]@{
    DnsTarget              = $Target
    DnsResolutionSucceeded = $dnsResolutionSucceeded
    TcpTarget              = "${Target}:$Port"
    TcpConnectionSucceeded = $tcpConnectionSucceeded
}

# Combine the adapter and connectivity information into one report.
$networkReport = [PSCustomObject]@{
    CollectedAt       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName      = $env:COMPUTERNAME
    ActiveAdapters    = $adapterInventory
    ConnectivityTests = $connectivityTests
}

# Determine the root folder of the Git project.
$projectRoot = Split-Path -Parent $PSScriptRoot

# Build the path to the existing output folder.
$outputDirectory = Join-Path -Path $projectRoot -ChildPath "output"

# Create the output folder when it does not already exist.
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Build the complete JSON report path.
$jsonPath = Join-Path `
    -Path $outputDirectory `
    -ChildPath "network_diagnostics.json"

# Save the nested report as JSON.
$networkReport |
    ConvertTo-Json -Depth 5 |
    Set-Content -Path $jsonPath -Encoding utf8

# Display readable results in the terminal.
Write-Host "`nActive network adapters:"
$adapterInventory | Format-Table -AutoSize

Write-Host "`nConnectivity tests:"
$connectivityTests | Format-List

Write-Host "JSON report saved to: $jsonPath"