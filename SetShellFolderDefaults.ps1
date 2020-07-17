
<#
.SYNOPSIS
    Script to reset the shell folder keys associated with folder redirections. Idea is to avoid having to use GPO to force data back to default locations (avoid CSE processing)
.DESCRIPTION
    Resets the shell folder keys to their default locations (as of Windows 10 1909)
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER CommonTargets
    Individual common folders to reset - the usual suspects (AppData, Contacts, Desktop, Documents, Downloads, Links, Music, Pictures, Searches and Start Menu)
.PARAMETER ResetAll
    Reset all redirected folders to default
.EXAMPLE
    SetShellFolderDefaults.ps1 -ResetAll
    Will reset all shell folders to default locations
.EXAMPLE
    SetShellFolderDefaults.ps1 -CommonTargets Documents,Desktop,StartMenu,AppData
    Will reset Documents, Desktop, Start Menu and AppData to default locations
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\ResetShellFolders.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $False, ValueFromPipeline = $true, ParameterSetName = 'Selective')] [ValidateSet('AppData',
        'Contacts',
        'Desktop',
        'Documents',
        'Downloads',
        'Links',
        'Music',
        'Pictures',
        'Searches',
        'StartMenu')] [Array] $CommonTargets,

    [Parameter(Mandatory = $False, ValueFromPipeline = $true, ParameterSetName = 'All')] [Switch] $ResetAll
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

function SetShellFolderDefaults {
    param (
        $Target
    )

    Write-Log -Message "========Processing $Target========" -Level Info
    $DefaultValue = $DefaultPaths.$Target
    Write-Log -Message "Default value for $Target should be $DefaultValue" -Level Info
    #User Shell Folders
    try {
        $UserShellFolderValue = Get-ItemPropertyValue -Path $UserShellKey -Name $Target -ErrorAction Stop
        Write-Log -Message "Current User Shell Folder Value for $Target is $UserShellFolderValue" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
    #Shell Folders (Legacy)
    try {
        $LegacyShellValue = Get-ItemPropertyValue -Path $ShellKey -Name $Target -ErrorAction Stop
        Write-Log -Message "Current Legacy User Shell value for $Target is $LegacyShellValue" -Level Info
    }
    catch {
        Write-Log -Message $_ -level Warn
    }
    #Fix Values
    #User Shell Folders
    if ($null -ne $UserShellFolderValue) {
        if ($UserShellFolderValue -eq $DefaultValue) {
            Write-Log -Message "User Shell Folder values for $Target match. Nothing to action" -level Info
        }
        else {
            Write-Log -Message "User Shell Folder values for $Target do not match" -level Warn
            Write-Log -Message "Attempting to set User Shell Folder value for $Target to default value: $DefaultValue" -Level Info
            try {
                Set-ItemProperty -Path $UserShellKey -Name $Target -Value $DefaultValue -ErrorAction Stop -WhatIf #Fix This!
                Write-Log -Message "Successfully wrote new value: $DefaultValue for key: $UserShellKey" -Level Info
            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }    
    }
    #Shell Folders (Legacy)
    if ($null -ne $LegacyShellValue) {
        if ($LegacyShellValue -eq $DefaultValue) {
            Write-Log -Message "Legacy Shell Folder values for $Target match. Nothing to action" -Level Info
        }
        else {
            Write-Log -Message "Legacy Shell Folder values for $Target do not match" -Level Warn
            Write-Log -Message "Attempting to set Legacy Shell Folder for $Target to default value: $DefaultValue" -Level Info
            try {
                Set-ItemProperty -Path $ShellKey -Name $Target -Value $DefaultValue -ErrorAction Stop -WhatIf #Fix This!
                Write-Log -Message "Successfully wrote new value: $DefaultValue for key: $ShellKey" -Level Info
            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }    
    }
    Write-Log -Message "========Finished Processing $Target========" -Level Info
}
#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
$UserShellKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' #This is active
$ShellKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' #This is legacy and for backwards compatibility only

[hashtable]$DefaultPaths = @{
    "{00BCFC5A-ED94-4E48-96A1-3F6217F21990}" = "%UserProfile%\AppData\Local\Microsoft\Windows\RoamingTiles"
    "{0DDD015D-B06C-45D5-8C4C-F59713854639}" = "%UserProfile%\Pictures"
    "{1B3EA5DC-B587-4786-B4EF-BD1DC332AEAE}" = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Libraries"
    "{374DE290-123F-4565-9164-39C4925E467B}" = "%UserProfile%\Downloads"
    "{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}" = "%UserProfile%\Saved Games"
    "{56784854-C6CB-462B-8169-88E350ACB882}" = "%UserProfile%\Contacts"
    "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}" = "%UserProfile%\Searches"
    "{A520A1A4-1780-4FF6-BD18-167343C5AF16}" = "%UserProfile%\AppData\LocalLow"
    "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}" = "%UserProfile%\Links"
    "{F42EE2D3-909F-4907-8871-4C22FC0BF756}" = "%UserProfile%\Documents"
    "Administrative Tools"                   = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Administrative Tools"
    "AppData"                                = "%UserProfile%\AppData\Roaming"
    "Cache"                                  = "%UserProfile%\AppData\Local\Microsoft\Windows\INetCache"
    "CD Burning"                             = "%UserProfile%\AppData\Local\Microsoft\Windows\Burn\Burn"
    "Cookies"                                = "%UserProfile%\AppData\Local\Microsoft\Windows\INetCookies"
    "Desktop"                                = "%UserProfile%\Desktop"
    "Favorites"                              = "%UserProfile%\Favorites"
    "Fonts"                                  = "C:\Windows\Fonts"
    "History"                                = "%UserProfile%\AppData\Local\Microsoft\Windows\History"
    "Local AppData"                          = "%UserProfile%\AppData\Local"
    "My Music"                               = "%UserProfile%\Music"
    "My Pictures"                            = "%UserProfile%\Pictures"
    "My Video"                               = "%UserProfile%\Videos"
    "NetHood"                                = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Network Shortcuts"
    "Personal"                               = "%UserProfile%\Documents"
    "PrintHood"                              = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Printer Shortcuts"
    "Programs"                               = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
    "Recent"                                 = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Recent"
    "SendTo"                                 = "%UserProfile%\AppData\Roaming\Microsoft\Windows\SendTo"
    "Start Menu"                             = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Start Menu"
    "Startup"                                = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    "Templates"                              = "%UserProfile%\AppData\Roaming\Microsoft\Windows\Templates"
}
#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

foreach ($Target in ($CommonTargets | Sort-Object -Unique)) {
    switch ($Target) {
        'AppData' {
            SetShellFolderDefaults -Target "AppData"
        } 'Contacts' {
            SetShellFolderDefaults -Target "{56784854-C6CB-462B-8169-88E350ACB882}"
        } 'Desktop' {
            SetShellFolderDefaults -Target "Desktop"
        } 'Documents' {
            SetShellFolderDefaults -Target "Personal"
            SetShellFolderDefaults -Target "{F42EE2D3-909F-4907-8871-4C22FC0BF756}"
        } 'Downloads' {
            SetShellFolderDefaults -Target "{374DE290-123F-4565-9164-39C4925E467B}"
        } 'Links' {
            SetShellFolderDefaults -Target "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}"
        } 'Music' {
            SetShellFolderDefaults -Target "My Music"
        } 'Pictures' {
            SetShellFolderDefaults -Target "My Pictures"
            SetShellFolderDefaults -Target "{0DDD015D-B06C-45D5-8C4C-F59713854639}"
        } 'Searches' {
            SetShellFolderDefaults -Target "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}"
        } 'StartMenu' {
            SetShellFolderDefaults -Target "Start Menu"
        }
    }
}

if ($ResetAll.IsPresent) {
    SetShellFolderDefaults -Target "Administrative Tools"
    SetShellFolderDefaults -Target "AppData"
    SetShellFolderDefaults -Target "Cache"
    SetShellFolderDefaults -Target "CD Burning"
    SetShellFolderDefaults -Target "Cookies"
    SetShellFolderDefaults -Target "Desktop"
    SetShellFolderDefaults -Target "Favorites"
    SetShellFolderDefaults -Target "Fonts"
    SetShellFolderDefaults -Target "History"
    SetShellFolderDefaults -Target "Local AppData"
    SetShellFolderDefaults -Target "My Music"
    SetShellFolderDefaults -Target "My Pictures"
    SetShellFolderDefaults -Target "My Video"
    SetShellFolderDefaults -Target "NetHood"
    SetShellFolderDefaults -Target "Personal"
    SetShellFolderDefaults -Target "PrintHood"
    SetShellFolderDefaults -Target "Programs"
    SetShellFolderDefaults -Target "Recent"
    SetShellFolderDefaults -Target "SendTo"
    SetShellFolderDefaults -Target "Start Menu"
    SetShellFolderDefaults -Target "Startup"
    SetShellFolderDefaults -Target "Templates"
    SetShellFolderDefaults -Target "{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}"
    SetShellFolderDefaults -Target "{A520A1A4-1780-4FF6-BD18-167343C5AF16}"
    SetShellFolderDefaults -Target "{56784854-C6CB-462B-8169-88E350ACB882}"
    SetShellFolderDefaults -Target "{F42EE2D3-909F-4907-8871-4C22FC0BF756}"
    SetShellFolderDefaults -Target "{374DE290-123F-4565-9164-39C4925E467B}"
    SetShellFolderDefaults -Target "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}"
    SetShellFolderDefaults -Target "{0DDD015D-B06C-45D5-8C4C-F59713854639}"
    SetShellFolderDefaults -Target "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}"
}

StopIteration
#endregion