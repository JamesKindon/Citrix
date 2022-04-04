<#
.SYNOPSIS
    Preps Connectwise Connect for Provisioning
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
    [string]$LogPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\ConnectwiseSealPrep.log",

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
$RootPath = "HKLM:\SYSTEM\CurrentControlSet\Services\"
$Identifier = Get-ChildItem -Path $RootPath -Recurse -ErrorAction SilentlyContinue
$Identifier = ($Identifier | Where-Object {$_.Name -like "*ScreenConnect Client*" -and $_.Name -notlike "*EventLog*"}).Name
$CustomerKey = $Identifier | Split-Path -Leaf
$Fullpath = $RootPath + $CustomerKey
$InitialValue = (Get-ItemProperty -Path $Fullpath -Name "ImagePath").ImagePath
$NewValue = $InitialValue -replace "s=(.*?)&.*?",""
#endregion

# ============================================================================
# Execute
# ============================================================================
#Region Execute

StartIteration

# Handle Service Stop
Write-Log -Message "Attempting to stop and disable services" -Level Info
$Services = Get-Service -DisplayName "ScreenConnect Client*"
if ($null -ne $Services) {
    foreach ($Service in $Services) {
        try {
            Write-Log -Message "Actioning service $($Service.Name)" -Level Info
            Set-Service -Name $Service.Name -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name $Service.Name -ErrorAction Stop -Force
            Write-Log -Message "Success" -Level Info
        }
        catch {
            Write-Log -Message $_ -Level Warn
            Write-Log -Message "Failed to stop service $($Service.Name)" -Level Warn
        }
    }
} else {
    Write-Log -Message "No services found" -Level Warn
}

# Handle registry settings
try {
    Write-Log -message "Altering ImagePath value with $($NewValue)" -Level Info
    Set-ItemProperty -Path $FullPath -Name "ImagePath" -Value $NewValue -ErrorAction Stop
    Write-Log -Message "Success" -Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
    Write-Log -Message "Failed to update registry keys" -Level Warn
}

Write-Log -Message "Script Complete" -Level Info

StopIteration
Exit 0
#endregion