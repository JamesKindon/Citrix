<#
.SYNOPSIS
    Checks the Citrix Broker Desktop Service is started after the predefined sleep time
.DESCRIPTION
    Written to address the off chance that the BIS-F process does not complete and the Broker Desktop Service is not started
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER SleepDuration
    Number of seconds to sleep. The Default is 600
.NOTES
    17.10.2020 - James Kindon Initial Release
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Windows\Temp\BrokerServiceStartMonitor.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [int]$SleepDuration = 600 # number of seconds to sleep

)
#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================
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
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

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

function StartIteration {
    Write-Log -Message "--------Starting Iteration--------" -Level Info
    RollOverlog
    Start-Stopwatch
}

function StopIteration {
    Stop-Stopwatch
    Write-Log -Message "--------Finished Iteration--------" -Level Info
}

function StartService {
    try {
        Write-Log -Message "Attempting to start Service $ServiceName" -Level Info
        $null = Start-Service -Name $ServiceName -ErrorAction Stop
        Write-Log -Message "Started Service $ServiceName" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Failed to Start Service $ServiceName" -level Warn
        StopIteration
        Exit 1
    }
}

function SetServiceStart {
    try {
        Write-Log -Message "Attempting to Set Service Startup to Automatic for $ServiceName" -Level Info
        $null = Set-Service -ServiceName $ServiceName -StartupType Automatic -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Failed to set service $ServiceName startup type to Automatic" -Level Warn
        StopIteration
        Exit 1
    }
}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
$ServiceName = "BrokerAgent"
#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

Write-Log -Message "Starting Script and sleeping for $SleepDuration seconds" -Level Info
Start-Sleep -Seconds $SleepDuration
Write-Log -Message "Starting Service Check for $ServiceName" -Level Info

try {
    $ServiceDetails = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($ServiceDetails.Status -eq "Running") {
        Write-Log -Message "$ServiceName is running. Nothing to action"
        StopIteration
        Exit 0
    }
    elseif ($ServiceDetails.Status -ne "Running") {
        Write-Log -Message "$ServiceName is $($ServiceDetails.Status). Checking Startup Type"
        if ($ServiceDetails.StartType -ne "Automatic") {
            Write-Log -Message "$ServiceName Startup type is set to $($ServiceDetails.StartType). Startup type must be set to Automatic." -Level Warn
            SetServiceStart -ServiceName $ServiceName -StartupType "Automatic"
        }

        StartService -ServiceName $ServiceName
    }
}
catch {
    Write-Log -Message "Failed to get service details for $ServiceName" -Level Warn
    StopIteration
    Exit 1
}

StopIteration
Exit 0
#endregion
