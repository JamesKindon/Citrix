<# 
    .SYNOPSIS
        Customise a Windows Server image for use as an RDS/XenApp VM in Azure.
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [System.String] $Log = "$env:SystemRoot\Logs\AzureArmCustomDeploy.log",

    [Parameter(Mandatory = $False)]
    [System.String] $Target = "$env:SystemDrive\Apps"
)

#region Functions
Function Set-RegionalSettings {
    # Regional settings - set to en-AU / Australia
    Import-Module International
    Set-WinHomeLocation -GeoId 12
    Set-WinSystemLocale -SystemLocale en-AU
    Set-WinUserLanguageList -LanguageList en-AU -Force
    Set-TimeZone -Id "AUS Eastern Standard Time" -Verbose
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/enAU-Language.xml"
    Invoke-WebRequest -Uri $url -OutFile "$Target\$(Split-Path $url -Leaf)"
    & $env:SystemRoot\System32\control.exe "intl.cpl,,/f:`"$Target\enAU-Language.xml`""
}

Function Set-Roles {
    Switch -Regex ((Get-WmiObject Win32_OperatingSystem).Caption) {
        "Microsoft Windows Server*" {
            # Add / Remove roles (requires reboot at end of deployment)
            Disable-WindowsOptionalFeature -Online -FeatureName "Printing-XPSServices-Features", "WindowsMediaPlayer" -NoRestart -WarningAction SilentlyContinue
            Uninstall-WindowsFeature -Name BitLocker, EnhancedStorage, PowerShell-ISE
            Add-WindowsFeature -Name RDS-RD-Server, Server-Media-Foundation, 'Search-Service', NET-Framework-Core

            # Configure services
            Set-Service Audiosrv -StartupType Automatic
            Set-Service WSearch -StartupType Automatic
        }
        "Microsoft Windows 10*" {
        }
    }
}
#endregion

#region Script logic
# Start logging
Write-Host "Running: $($MyInvocation.MyCommand)."
Start-Transcript -Path $Log -Append

# If local path for script doesn't exist, create it
If (!(Test-Path $Target)) { New-Item -Path $Target -ItemType Directory -Force -ErrorAction SilentlyContinue }

# Run tasks
Set-RegionalSettings
Set-Roles

# Stop Logging
Stop-Transcript
Write-Host "Complete: $($MyInvocation.MyCommand)."
#endregion