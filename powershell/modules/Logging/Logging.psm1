# Write a timestamped entry to a log file and the terminal.
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"

    Add-Content `
        -LiteralPath $LogPath `
        -Value $logEntry `
        -Encoding utf8

    Write-Host $logEntry
}

# Make the Write-Log function available outside this module.
Export-ModuleMember -Function Write-Log