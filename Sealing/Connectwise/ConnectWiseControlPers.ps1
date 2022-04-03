<#
.SYNOPSIS
    Personalises Connectwise Connect for Provisioning
.DESCRIPTION
    https://docs.connectwise.com/ConnectWise_Control_Documentation/Get_started/Knowledge_base/Image_a_machine_with_an_installed_agent
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
#endregion

# ============================================================================
# Execute
# ============================================================================
#Region Execute

# Handle Service Start
Write-Log -Message "Attempting to enable and start services" -Level Info
$Services = Get-Service -DisplayName "ScreenConnect Client*"
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

#endregion