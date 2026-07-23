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

# Display the inventory information as a readable list.
$inventory | Format-List