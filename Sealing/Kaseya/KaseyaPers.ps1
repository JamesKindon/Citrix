<#
.SYNOPSIS
    Personalises Kaseya for Provisioning
.DESCRIPTION
    https://techtalkpro.net/2017/06/02/how-to-install-the-kaseya-vsa-agent-on-a-non-persistent-machine/ 
.EXAMPLE
#>

# ============================================================================
# Parameters
# ============================================================================
#region Params
param (
    [Parameter(Mandatory = $false)]
    [string]$LogPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\KaseyaSealPers.log",

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5 # number of days before logfile rollover occurs
)
#endregion

# ============================================================================
# Functions
# ============================================================================
#region Functions
#endregion

# ============================================================================
# Variables
# ============================================================================
#region Variables
$GroupID = ".group.fun" # keep the "." - this could be an ADMX value in BISF

$IniLocation = "C:\users\James Kindon\Downloads\KaseyaD.ini" #- this could be an ADMX value in BISF  ## need to pull this location from the registry

#$RootPath = "HKLM:\SOFTWARE\WOW6432Node\Kaseya\Agent\"
#$CustomerKey = (Get-ChildItem -Path $RootPath -Recurse).Name | Split-Path -Leaf
#$IniLocation = $RootPath + $CustomerKey + "\" + "KaseyaD.ini"

$FinalID = $env:COMPUTERNAME + $GroupID
$Ini = Get-Content $IniLocation

#endregion

# ============================================================================
# Execute
# ============================================================================
#Region Execute

# Backup the INI file just in case
if (!(Test-Path -Path (($IniLocation) + "_backup"))) {
    Copy-Item -Path $IniLocation -Destination (($IniLocation) + "_backup")
}

# Alter the INI file
$ini = $ini -replace '^User_Name.+$', "User_Name                  $FinalID" #spacing is for consistency with source ini file
$ini = $ini -replace '^Password.+$', "Password                   NewKaseyaAgent-" #spacing is for consistency with source ini file
#$ini = $ini -replace '^Agent_Guid.+$', "Agent_Guid                 NewKaseyaAgent-" #spacing is for consistency with source ini file
#$ini = $ini -replace '^KServer_Bind_ID.+$', "KServer_Bind_ID            NewKaseyaAgent-" #spacing is for consistency with source ini file
$ini | Out-File $IniLocation -Force

# Handle Service Start
Write-Log -Message "Attempting to enable and start services" -Level Info
$Services = Get-Service -DisplayName "Kaseya Agent*"
if ($Null -ne $Services) {
    foreach ($Service in $Services) {
        try {
            Set-Service -Name $Service.Name -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $Service.Name -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
            Write-Log -Message "Failed to start service $($Service.Name)" -Level Warn
        }
    }
} else {
    Write-Log -Message "No services found" -Level Warn
}


#endregion