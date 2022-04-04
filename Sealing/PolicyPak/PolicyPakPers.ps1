<#
.SYNOPSIS
    Personalises PolicPak (assumes Loose mode matching)
.DESCRIPTION
    https://kb.policypak.com/kb/article/883-how-to-install-the-policypak-cloud-client-for-use-in-an-azure-virtual-desktop-image/
    https://kb.policypak.com/kb/article/1102-why-do-i-see-duplicate-computer-entries-in-policypak-cloud-or-what-is-loose-strict-and-advanced-registration/
.EXAMPLE
.NOTES
    Service ordering appears to be critical for licence checkout
#>

# ============================================================================
# Parameters
# ============================================================================
#region Params
param (
    [Parameter(Mandatory = $false)]
    [string]$LogPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\PolicyPakSealPers.log",

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

function Start-Stopwatch {
    Write-Log -Message "Starting Timer" -Level Info
    $Global:StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
}

function Stop-Stopwatch {
    Write-Log -Message "Stopping Timer" -Level Info
    $StopWatch.Stop()
    if ($StopWatch.Elapsed.TotalSeconds -le 1) {
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.TotalMilliseconds) ms to complete." -Level Info
    }
    else {
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.TotalSeconds) seconds to complete." -Level Info
    }
}

function StartIteration {
    Write-Log -Message "--------Starting Iteration--------" -Level Info
    RollOverlog
    Start-Stopwatch
}

function StopIteration {
    Stop-Stopwatch
    Write-Log -Message "--------Finished Iteration--------" -Level Info
}

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

StartIteration

# Handle Service Start
Write-Log -Message "Attempting to enable services" -Level Info
$Services = Get-Service -DisplayName "PolicyPak*"
if ($Null -ne $Services) {
    foreach ($Service in $Services) {
        try {
            Write-Log -Message "Actioning service $($Service.Name)" -Level Info
            Set-Service -Name $Service.Name -StartupType Automatic -ErrorAction Stop
            Write-Log -Message "Success" -Level Info
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
} else {
    Write-Log -Message "No services found" -Level Warn
}

# Start Services in correct order for licence checkout
Write-Log -Message "Attempting to start PolicyPak Services in the correct order" -Level Info
try {
    Restart-Service -Name "PPExtensionSvc64" -Force -ErrorAction Stop
    Restart-Service -Name "PPWatcherSvc32" -Force -ErrorAction Stop
    Restart-Service -Name "PPWatcherSvc64" -Force -ErrorAction Stop
    Start-Service -Name "PPCloudSvc" -ErrorAction Stop
    Write-Log -Message "Success" -Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
}

# Force a policypak update
Write-Log -Message "Forcing a PolicyPak Update" -Level Info
ppupdate /force

Write-Log -Message "Script Complete" -Level Info

StopIteration
Exit 0
#endregion
