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

$RootPath = "HKLM:\SOFTWARE\WOW6432Node\Kaseya\Agent\"
$CustomerKey = (Get-ChildItem -Path $RootPath -Recurse).Name | Split-Path -Leaf # Find Customer ID
$InstallPath = (Get-ItemProperty -Path ($RootPath + $CustomerKey)).Path # Find custom install location for INI
$IniLocation = $InstallPath + "\" + "KaseyaD.ini"

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
$ini = $ini -replace '^(User_Name\s+).*$' , "`$1$FinalID"
$ini = $ini -replace '^(Password\s+).*$' , "`$1NewKaseyaAgent-"
#$ini = $ini -replace '^(Agent_Guid\s+).*$' , "`$1TBD-"
#$ini = $ini -replace '^(KServer_Bind_ID\s+).*$' , "`$1TBD-"
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