param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Target = "learn.microsoft.com",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 443
)

# Build the path to the reusable logging module.
$loggingModulePath = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "modules\Logging\Logging.psm1"

# Load the logging function.
Import-Module `
    -Name $loggingModulePath `
    -Force `
    -ErrorAction Stop

# Determine the root folder of the Git project.
$projectRoot = Split-Path -Parent $PSScriptRoot

# Build the path to the output folder.
$outputDirectory = Join-Path -Path $projectRoot -ChildPath "output"

# Create the output folder when it does not already exist.
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Build the paths for the JSON report and operational log.
$jsonPath = Join-Path `
    -Path $outputDirectory `
    -ChildPath "network_diagnostics.json"

$logPath = Join-Path `
    -Path $outputDirectory `
    -ChildPath "network_diagnostics.log"

Write-Log `
    -Message "Starting network diagnostics for ${Target}:$Port." `
    -Level "INFO" `
    -LogPath $logPath

# Collect active network adapters that have an IPv4 address.
$activeAdapters = @(
    Get-NetIPConfiguration | Where-Object {
        $_.NetAdapter.Status -eq "Up" -and $_.IPv4Address
    }
)

Write-Log `
    -Message "Detected $($activeAdapters.Count) active IPv4 network adapter(s)." `
    -Level "INFO" `
    -LogPath $logPath

# Convert the network adapter information into structured objects.
$adapterInventory = @(
    foreach ($adapter in $activeAdapters) {

        # Retrieve the IPv4 DNS servers assigned to this adapter.
        $dnsServers = Get-DnsClientServerAddress `
            -InterfaceIndex $adapter.InterfaceIndex `
            -AddressFamily IPv4

        [PSCustomObject]@{
            InterfaceAlias = $adapter.InterfaceAlias
            IPv4Address    = $adapter.IPv4Address.IPAddress -join ", "
            PrefixLength   = $adapter.IPv4Address.PrefixLength -join ", "
            DefaultGateway = if ($adapter.IPv4DefaultGateway) {
                $adapter.IPv4DefaultGateway.NextHop -join ", "
            }
            else {
                "None"
            }
            DnsServers     = $dnsServers.ServerAddresses -join ", "
        }
    }
)

# Set initial DNS test values.
$dnsResolutionSucceeded = $false
$dnsError = $null

Write-Log `
    -Message "Attempting DNS resolution for $Target." `
    -Level "INFO" `
    -LogPath $logPath

# Attempt to resolve the supplied hostname.
try {
    Resolve-DnsName `
        -Name $Target `
        -Type A `
        -ErrorAction Stop |
        Out-Null

    $dnsResolutionSucceeded = $true

    Write-Log `
        -Message "DNS resolution succeeded for $Target." `
        -Level "SUCCESS" `
        -LogPath $logPath
}
catch {
    $dnsResolutionSucceeded = $false
    $dnsError = $_.Exception.Message

    Write-Log `
        -Message "DNS resolution failed for $Target. Error: $dnsError" `
        -Level "ERROR" `
        -LogPath $logPath
}

# Set initial TCP test values.
$tcpConnectionSucceeded = $false
$tcpError = $null

# Run the TCP test only when DNS resolution succeeds.
if ($dnsResolutionSucceeded) {
    Write-Log `
        -Message "Testing TCP connectivity to ${Target}:$Port." `
        -Level "INFO" `
        -LogPath $logPath

    try {
        $tcpConnectionSucceeded = Test-NetConnection `
            -ComputerName $Target `
            -Port $Port `
            -InformationLevel Quiet `
            -WarningAction SilentlyContinue

        if ($tcpConnectionSucceeded) {
            Write-Log `
                -Message "TCP connection to ${Target}:$Port succeeded." `
                -Level "SUCCESS" `
                -LogPath $logPath
        }
        else {
            $tcpError = "TCP connection to ${Target}:$Port failed."

            Write-Log `
                -Message $tcpError `
                -Level "ERROR" `
                -LogPath $logPath
        }
    }
    catch {
        $tcpConnectionSucceeded = $false
        $tcpError = $_.Exception.Message

        Write-Log `
            -Message "TCP test produced an error: $tcpError" `
            -Level "ERROR" `
            -LogPath $logPath
    }
}
else {
    $tcpError = "TCP test skipped because DNS resolution failed."

    Write-Log `
        -Message $tcpError `
        -Level "WARNING" `
        -LogPath $logPath
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

# Save the nested report as JSON.
$networkReport |
    ConvertTo-Json -Depth 5 |
    Set-Content -Path $jsonPath -Encoding utf8

Write-Log `
    -Message "JSON report saved to $jsonPath." `
    -Level "SUCCESS" `
    -LogPath $logPath

# Display readable results in the terminal.
Write-Host "`nActive network adapters:"
$adapterInventory | Format-Table -AutoSize

Write-Host "`nConnectivity tests:"
$connectivityTests | Format-List

Write-Host "JSON report saved to: $jsonPath"
Write-Host "Operational log saved to: $logPath"

if ($exitCode -eq 0) {
    Write-Log `
        -Message "Network diagnostics completed successfully with exit code 0." `
        -Level "SUCCESS" `
        -LogPath $logPath
}
else {
    Write-Log `
        -Message "Network diagnostics completed with status $overallStatus and exit code $exitCode." `
        -Level "ERROR" `
        -LogPath $logPath
}

# Return the result code to PowerShell or an automation system.
exit $exitCode