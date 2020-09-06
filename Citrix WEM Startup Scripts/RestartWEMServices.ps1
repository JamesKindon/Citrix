<#
.SYNOPSIS
    - Stops and Starts WEM services and forces a cache refresh
    - Optionally offers a deletion of existing cache files - typically used with Cloud deployments 
    - If deletion is selected, the script backs up existing cache files and restores if no new cache files are pulled
.DESCRIPTION
    - Does not support an upgraded version of WEM (path changes from 1903 onwards). If you want to continue using legacy versions of WEM, use a legacy version of this script
      https://github.com/JamesKindon/Citrix/tree/master/Citrix%20WEM%20Startup%20Scripts/Legacy
    - Does not support old "norskale" pathed versions of WEM (pre 1903). You should perform a clean install of WEM, else use a legacy version of this script
      https://github.com/JamesKindon/Citrix/tree/master/Citrix%20WEM%20Startup%20Scripts/Legacy
    - Assumes a default installation location of WEM (will look for changed cache file locations)
.PARAMETER LogPath
    Logpath output for all operations. Defaults to c:\Logs\WEMCacheRefresh.log
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER DeleteWEMCache
    Specifies whether to delete the WEM Cache files. Typically only user for Cloud Deployments to address specific issues. Defaults to false
.EXAMPLE
    .\RestartWEMServices.ps1 -DeleteWEMCache True -LogPath c:\Logs\WEMCacheRefresh.log 
    Will stop services, backup cache files, delete existing cache files, and force a cache refresh. If no new cache files are received, the previously backed up cache files will be restored
.EXAMPLE
    .\RestartWEMServices.ps1 -LogPath c:\Logs\WEMCacheRefresh.log
    Will force a service restart and cache refresh. Logs to c:\Logs\WEMCacheRefresh.log
.NOTES
    06.09.2020 - rewritten existing scripts in an attempt to deal with ongoing cache issues
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\WEMCacheRefresh.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [ValidateSet($True, $False)]
    [string]$DeleteWEMCache = $False

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

function StopWEMServices {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    Write-Log -Message "Stopping the WEM Agent Services" -Level Info
    try {
        Stop-Service -Name $WEMService -Force -ErrorAction Stop
        Write-Log -Message "$WEMService Stopped" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
    
    if (Get-Process -name $WEMProcess -ErrorAction SilentlyContinue) {
        Write-Log -Message "Killing WEM Process" -Level Info
        try {
            Stop-Process -Name $WEMProcess -Force -ErrorAction Stop 
            Write-Log -Message "$WEMProcess killed" -level Info
        }
        catch {
            Write-Log -Message $_ -level Warn
        } 
    }
}

function StartWEMServices {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    Write-Log -Message "Starting WEM Services" -Level Info
    try {
        Start-Service -Name $WEMService -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    Write-Log -Message "Starting NetLogon Service" -Level Info
    try {
        Start-Service -Name "Netlogon" -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
}

function RestartWEMServices {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    StopWEMServices -Computer $Env:COMPUTERNAME
    if ($DeleteWEMCache -eq $True) {
        Write-Log -Message "WEM cache deletion is set to True. Backing up and removing existing cache files" -Level Info
        DeleteWEMCache -Computer $Env:COMPUTERNAME
    }
    else {
        Write-Log -Message "WEM cache deletion is set to False. Not deleting cache files" -Level Info
    }
    StartWEMServices -Computer $Env:COMPUTERNAME
    Write-Log -Message "Sleeping for 20 seconds before refreshing cache" -Level Info
    Start-Sleep -Seconds 20
    RefreshWEMCache -Computer $Env:COMPUTERNAME
    if ($DeleteWEMCache -eq $True) {
        Write-Log -Message "Waiting 30 seconds to confirm cache files are created" -Level Info
        Start-Sleep -Seconds 30
        Write-Log -Message "Testing for WEM cache files" -Level Info
        if ($null -eq (Get-ChildItem -Path $CachePath)) {
            Write-Log -Message "Cannot find WEM cache files! Attempting Service Restart and refresh" -Level Warn
            StopWEMServices -Computer $Env:COMPUTERNAME
            StartWEMServices -Computer $Env:COMPUTERNAME
            Write-Log -Message "Waiting 20 seconds before cache refresh" -Level Info
            Start-Sleep 20
            RefreshWEMCache -Computer $Env:COMPUTERNAME
            Write-Log -Message "Waiting 30 seconds to confirm cache files are created" -Level Info
            Start-Sleep 30 
            if ($null -eq (Get-ChildItem -path $CachePath)) {
                Write-Log -Message "Cannot find Cache Files. Restoring from last backup" -level Warn
                RestoreWEMCache -Computer $Env:COMPUTERNAME
            }
        }
        else {
            Write-Log -Message "Cache files found!" -Level Info
        }
    }
}

function BackupWEMCache {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    $CacheBackupPath = (Split-Path $CachePath -Parent) + "\WEMCacheBackup"
    $null = if (!(Test-Path $CacheBackupPath)) { New-Item -Path $CacheBackupPath -Type Directory -Force }
    Write-Log -Message "Cache file backup path is $CacheBackupPath" -Level Info
    Write-Log -Message "Trying to get existing cache files" -Level Info
    try {
        $CacheFiles = Get-ChildItem -Path $CachePath -ErrorAction Stop
        Write-Log -Message "$(($CacheFiles | Measure-Object).Count) cache files retrieved" -level Info
    }
    catch {
        Write-Log -Message "Failed to retrieve cache files" -Level Info
    }
    foreach ($File in $CacheFiles) {
        try {
            Write-Log -Message "Attempting to backup $File to $CacheBackupPath"
            Copy-Item -Path $File.VersionInfo.FileName -Destination $CacheBackupPath -Force -ErrorAction Stop
            Write-Log -Message "$($File) backup is successful!" -Level Info
        }
        catch {
            Write-Log -Message "$_" -Level Warn
            Write-Log -Message "Cannot copy file $file to destination $CacheBackupPath" -Level Warn
        }
    }
}

function RestoreWEMCache {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    Write-Log -Message "Attempting to restore WEM cache files from backup" -Level Info
    StopWEMServices -Computer $Env:COMPUTERNAME
    $BackupFiles = Get-ChildItem -Path $CacheBackupPath
    foreach ($File in $BackupFiles) {
        try {
            Write-Log -Message "Restoring backup file $File"
            Copy-Item -path $File.VersionInfo.FileName -Destination $CachePath -Force -ErrorAction Stop
            Write-Log -Message "$($File) restore is Successful!" -Leve Info
        }
        catch {
            Write-Log -Message "Cannot restore cache file $File" -Level Warn
            Write-Log -Message $_ -Level Warn
        }
    }
    StartWEMServices -Computer $Env:COMPUTERNAME
    RefreshWEMCache -Computer $Env:COMPUTERNAME
}

function DeleteWEMCache {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    BackupWEMCache -Computer $Env:COMPUTERNAME
    $CacheFiles = Get-ChildItem -Path $CachePath
    foreach ($File in $CacheFiles) {
        try {
            Write-Log "Deleting file $($File.VersionInfo.FileName)"
            Remove-Item -Path $File.VersionInfo.FileName -Force -ErrorAction Stop
        }
        catch {
            Write-Log -Message "Failed to delete file $($File.VersionInfo.FileName)" -Level Warn
            Write-Log -Message $_ -Level Warn
        }
    }  
}

function RefreshWEMCache {
    param (
        [Parameter(Mandatory = $True)]
        [String]$Computer
    )
    Write-Log -Message "Refreshing WEM cache" -Level Info
    try {
        Start-Process $WEMAgentCacheUtility -ArgumentList "-refreshcache" -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
}
#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
# Set Variables

$WEMService = "Citrix WEM Agent Host Service"
$WEMProcess = "Citrix.Wem.Agent.Service"

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

if (Get-Service -Name $WEMService -ErrorAction SilentlyContinue) {
    Write-Log -Message "$WEMService Found" -Level Info
    $WEMConfigDetails = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Norskale\Agent Host\'
    $AlternateCacheLocation = $WEMConfigDetails.AgentCacheAlternateLocation
    $WEMAgentCacheUtility = Join-Path -Path $WEMConfigDetails.AgentLocation -ChildPath "AgentCacheUtility.exe"
    $CachePath = Join-Path -Path (Split-Path $WEMAgentCacheUtility -Parent) -ChildPath "Local Databases"

    if ($AlternateCacheLocation) {
        Write-Log -Message "WEM Cache is in a non standard location: $AlternateCacheLocation" -Level Info
        if (Test-Path $AlternateCacheLocation) {
            $CachePath = $AlternateCacheLocation
        }
        elseif (!(Test-Path $AlternateCacheLocation)) {
            Write-Log -Message "Cache Path is not accessible. Exiting Script" -Level Warn
            StopIteration
            Exit 1
        }
    }
    else {
        Write-Log -Message "WEM Cache is in the default location: $CachePath" -Level Info
    }

    Write-Log -Message "Setting WEM agent path to: $WEMAgentCacheUtility" -Level Info
    Write-Log -Message "Setting WEM cache path to $CachePath" -Level Info
    # Check for Clean Install
    if (Test-Path -Path $WEMAgentCacheUtility -ErrorAction SilentlyContinue) {
        Write-Log -Message "This is a clean install of WEM" -Level Info
        RestartWEMServices -Computer $Env:COMPUTERNAME
    }
    else {
        Write-Log -Message "This appears to be an upgraded instance of WEM and is not supported by this script `n please perform a clean install of WEM" -Level Warn
        StopIteration
        Exit 1
    }
}
else {
    Write-Log -Message "$($WEMService) not found" -Level Info
    Write-Log -Message "This doesn't appear to be a server with WEM installed" -Level Warn
} 

StopIteration
Exit 0
#endregion

