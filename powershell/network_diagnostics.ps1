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

# Set initial DNS test values.
$dnsResolutionSucceeded = $false
$dnsError = $null

# Attempt to resolve the supplied hostname.
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
    $dnsError = $_.Exception.Message
}

# Set initial TCP test values.
$tcpConnectionSucceeded = $false
$tcpError = $null

# Run the TCP test only when DNS resolution succeeds.
if ($dnsResolutionSucceeded) {
    try {
        $tcpConnectionSucceeded = Test-NetConnection `
            -ComputerName $Target `
            -Port $Port `
            -InformationLevel Quiet `
            -WarningAction SilentlyContinue

        if (-not $tcpConnectionSucceeded) {
            $tcpError = "TCP connection to ${Target}:$Port failed."
        }
    }
    catch {
        $tcpConnectionSucceeded = $false
        $tcpError = $_.Exception.Message
    }
}
else {
    $tcpError = "TCP test skipped because DNS resolution failed."
}

# Determine the overall status and script exit code.
$overallStatus = "Success"
$exitCode = 0

if (-not $dnsResolutionSucceeded) {
    $overallStatus = "DnsFailure"
    $exitCode = 1
}
elseif (-not $tcpConnectionSucceeded) {
    $overallStatus = "TcpFailure"
    $exitCode = 2
}

# Organize the connectivity test results.
$connectivityTests = [PSCustomObject]@{
    DnsTarget              = $Target
    DnsResolutionSucceeded = $dnsResolutionSucceeded
    DnsError               = $dnsError
    TcpTarget              = "${Target}:$Port"
    TcpConnectionSucceeded = $tcpConnectionSucceeded
    TcpError               = $tcpError
    OverallStatus          = $overallStatus
    ExitCode               = $exitCode
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

# Build the path to the output folder.
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
Write-Host "Script completed with exit code: $exitCode"

# Return the result code to PowerShell or an automation system.
exit $exitCode