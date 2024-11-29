<#
.SYNOPSIS
    In some scenarios, the WEM machine cache for CPM doesn't update previously applied settings, or update approriate changes - usually due to a conflict in delivery methods (might have been GPO for example)
.DESCRIPTION
    Resets the CPM portion of the WEM machine cache at boot to ensure all settings are up to date
    https://support.citrix.com/s/article/CTX219086-some-upm-or-wem-agent-parameters-may-not-be-applied-by-the-agent-after-switching-from-gpo-settings-to-workspace-environment-management-settings?language=en_US
.PARAMETER LogPath
    Logpath output for all operations. Defaults to C:\windows\system32\LogFiles\WEMMachineCacheRefresh.log
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.NOTES
 - You can deliver this via startup script for the machine
 - You can also sign this script, and then run it as a WEM scripted action using a machine startup trigger
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\windows\system32\LogFiles\WEMMachineCacheRefresh.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5 # number of days before logfile rollover occurs

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

#region Variables
# ============================================================================
# Variables
# ============================================================================
# Define the registry path and value name
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Norskale\Agent Host\UpmConfigurationSettings"
$valueName = "ServiceAssignedUPMConfigurationSettingsList_#0"
$backupFilePath = "C:\Windows\Temp\$($valueName)_backup.txt"
$wem_agent_host_service = "Citrix WEM Agent Host Service"

# Set Variables

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

try {
    # Check if the registry value exists
    $valueExists = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

    if ($null -ne $valueExists) {
        Write-Log -Message "WEM Machine Cache value exists for CPM: $registryPath\$valueName" -Level Info

        $valueData = (Get-ItemProperty -Path $registryPath -Name $valueName).$valueName

        # Write the value to a backup file
        Write-Log -Message "Backing up WEM Machine Cache value to file: $backupFilePath" -Level Info
        Set-Content -Path $backupFilePath -Value $valueData -ErrorAction Stop

    } else {
        Write-Log -Message "WEM Machine Cache value does not exist: $registryPath\$valueName" -Level Info
    }

    # Delete the original registry value
    Remove-ItemProperty -Path $registryPath -Name $valueName -ErrorAction Stop
    Write-Log -Message "WEM Machine Cache value deleted: $registryPath\$valueName" -Level Info

    #Handle Service restarts to trigger a sync
    Write-Log -Message "Restarting service: $wem_agent_host_service" -Level Info
    Stop-Service -Name $wem_agent_host_service -Force -ErrorAction Stop
    Start-Service -Name $wem_agent_host_service -ErrorAction Stop

    Start-Sleep -Seconds 5

    # Test if the original registry value has been created again
    $valueExists = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

    if (-not $valueExists) {
        Write-Log -Message "WEM Machine Cache value not created, restarting services again" -Level Info
        Stop-Service -Name $wem_agent_host_service -Force -ErrorAction Stop
        Start-Service -Name $wem_agent_host_service -ErrorAction Stop

        Start-Sleep -Seconds 10

        # Test again if the original registry value has been created
        $valueExists = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

        if ($null -eq $valueExists) {
            Write-Log -Message "WEM Machine Cache value still not created, restoring from backup file: $backupFilePath" -Level Info
            $backupValueData = Get-Content -Path $backupFilePath
            New-ItemProperty -Path $registryPath -Name $valueName -Value $backupValueData -PropertyType String -Force | Out-Null
            Write-Log -Message "WEM Machine Cache value restored from backup: $registryPath\$valueName" -Level Info

            # Restart the service
            Stop-Service -Name $wem_agent_host_service -Force -ErrorAction Stop
            Start-Service -Name $wem_agent_host_service -ErrorAction Stop
        } else {
            Write-Log -Message "WEM Machine Cache value created after service restart: $registryPath\$valueName" -Level Info
        }
    } else {
        Write-Log -Message "WEM Machine Cache value created: $registryPath\$valueName" -Level Info
    }
} catch {
    Write-Log -Message "An error occurred: $_" -Level Warn
}

StopIteration
Exit 0
#endregion


