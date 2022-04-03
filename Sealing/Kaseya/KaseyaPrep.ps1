<#
.SYNOPSIS
    Preps Kaseya for Provisioning
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
    [string]$LogPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\KaseyaSealPrep.log",

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5 # number of days before logfile rollover occurs
)
#endregion

# ============================================================================
# Functions
# ============================================================================
#region Functions
function Write-Log {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = $LogPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoClobber
    )

    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
        
        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
        }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }

        else {
            # Nothing to see here yet.
        }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "dd-MM-yyyy HH:mm:ss" #this is in AU time

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

function RollOverlog {
    $LogFile = $LogPath
    $LogOld = Test-Path $LogFile -OlderThan (Get-Date).AddDays(-$LogRollover)
    $RolloverDate = (Get-Date -Format "dd-MM-yyyy")
    if ($LogOld) {
        Write-Log -Message "$LogFile is older than $LogRollover days, rolling over" -Level Info
        $NewName = [io.path]::GetFileNameWithoutExtension($LogFile)
        $NewName = $NewName + "_$RolloverDate.log"
        Rename-Item -Path $LogFile -NewName $NewName
        Write-Log -Message "Old logfile name is now $NewName" -Level Info
    }    
}
#endregion

# ============================================================================
# Variables
# ============================================================================
#region Variables
$RootPath = "HKLM:\SOFTWARE\WOW6432Node\Kaseya\Agent\"
$CustomerKey = (Get-ChildItem -Path $RootPath -Recurse).Name | Split-Path -Leaf
$FullPath = $RootPath + $CustomerKey

#endregion

# ============================================================================
# Execute
# ============================================================================
#Region Execute

# Handle Service Stop
Write-Log -Message "Attempting to stop and disable services" -Level Info
$Services = Get-Service -DisplayName "Kaseya Agent*"
foreach ($Service in $Services) {
    try {
        Set-Service -Name $Service.Name -StartupType Disabled -ErrorAction Stop
        Stop-Service -Name $Service.Name -ErrorAction Stop -Force
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Failed to stop service $($Service.Name)" -Level Warn
    }
}


# Handle registry settings
try {
    Remove-ItemProperty -Path $FullPath -Name "AgentGUID" -Verbose -ErrorAction Stop
    Remove-ItemProperty -Path $FullPath -Name "MachineID" -Verbose -ErrorAction Stop
    Remove-ItemProperty -Path $FullPath -Name "PValue" -Verbose -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    Write-Log -Message "Failed to update registry keys" -Level Warn
}
#endregion
