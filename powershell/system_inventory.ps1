# Collect information about the Windows operating system.
$operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem

# Organize the collected information into one structured object.
$inventory = [PSCustomObject]@{
    CollectedAt       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName      = $env:COMPUTERNAME
    CurrentUser       = "$env:USERDOMAIN\$env:USERNAME"
    OperatingSystem   = $operatingSystem.Caption
    OSVersion         = $operatingSystem.Version
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
}

# Determine the root folder of the Git project.
$projectRoot = Split-Path -Parent $PSScriptRoot

# Build the path for the output folder.
$outputDirectory = Join-Path -Path $projectRoot -ChildPath "output"

# Create the output folder only when it does not already exist.
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Build complete file paths for the JSON and CSV reports.
$jsonPath = Join-Path -Path $outputDirectory -ChildPath "system_inventory.json"
$csvPath = Join-Path -Path $outputDirectory -ChildPath "system_inventory.csv"

# Convert the inventory object to JSON and save it to a file.
$inventory |
    ConvertTo-Json |
    Set-Content -Path $jsonPath -Encoding utf8

# Export the inventory object to a CSV file.
$inventory |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

# Display the inventory information in the terminal.
$inventory | Format-List

# Display the locations of the saved reports.
Write-Host "JSON report saved to: $jsonPath"
Write-Host "CSV report saved to:  $csvPath"