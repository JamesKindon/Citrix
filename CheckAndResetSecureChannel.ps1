
<#
.SYNOPSIS
    Checks the status of the secure channel status between a computer and the domain, fixes if broken
.DESCRIPTION
    Designed to be run as a startup script in persistent VDI environments
    Make sure the Script is either executed by local policy or scheduled task with the files stored on the base image (if trust relationships are broken, then you won't be able to execute the script from anywhere else)
    Encrypted password must be created on the machine itself and cannot be transferred to another machine https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/convertto-securestring
    Requires:
        # Service Account with local admin permissions on local machines
        # Credential file created and stored next to the script containing encrypted creds for the service account used to execute the reset
            # $credential = Get-Credential
            # $credential.Password | ConvertFrom-SecureString | Set-Content c:\scripts\encrypted_password.txt)
        # Assigned appropriate permissions on the OU for computer account reset (example uses full permissions on the OU)
        # Scheduled task should execute with a local admin account
        # Schedule Task: powershell.exe / -ExecutionPolicy Bypass -File c:\Scripts\CheckAndResetSecureChannel
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\SecureChannelCheck.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [string]$username = "KINDO\x_svc_acctreset",

    [Parameter(Mandatory = $false)]
    [string]$PWFile = "c:\Scripts\encrypted_password.txt"

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

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

if (!(Test-ComputerSecureChannel)) {
    Write-Log -Message "Secure Channel is broken on the local computer: $($env:ComputerName). Attempting to Reset" -Level Info
    try {
        $Encrypted = Get-Content $PWFile | ConvertTo-SecureString
        $Credential = New-Object System.Management.Automation.PsCredential ($username, $Encrypted)
        Test-ComputerSecureChannel -Repair -Credential $Credential -ErrorAction Stop
        Write-Log -Message "Success" -Level Info
    }
    catch {
        Write-Log -Message "Failed to reset machine account" -Level Warn
        Write-Log -Message $_ -Level Warn
    }
} 
else {
    Write-Log -Message "The secure channel between the local computer: $($env:ComputerName) and the domain is in good condition" -Level Info
}

StopIteration
Exit 0
#endregion


