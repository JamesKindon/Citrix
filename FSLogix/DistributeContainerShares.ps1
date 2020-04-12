<#
.SYNOPSIS
    Builds on the work of Ryan Revord (https://twitter.com/rsrevord) to order FSLogix Share locations by available space
.DESCRIPTION
    James Rankin posted Ryan's original code here: https://james-rankin.com/articles/spreading-users-over-multiple-file-shares-with-fslogix-profile-containers/
.PARAMETER ContainerShares
    List of Container shares to be tested and leveraged. Comma separated array via command, or hardcoded into script - either way
.PARAMETER DriveLetter
    Drive letter to be used for testing each share. Default is Z
.PARAMETER ProfileContainer
    Profile Container configuration enabled or disabled. True or False value. Default is True
.PARAMETER OfficeContainer
    Office Container configuration enabled or disabled. True or False value. Default is True
.PARAMETER LogPath
    Logpath output for all operations. Default is C:\FSLogixPathPlacementLogs\FSLogixPathLog.log
.PARAMETER DiskSpaceBuffer
    Mimimum available space available on the share to classify as healthy and available for placement. Default is 100GB
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.EXAMPLE
    .\DistributeContainerShares.ps1 -OfficeContainer True -ProfileContainer False -DiskSpaceBuffer 100 -ContainerShares \\Kindo-DC\VHDs,\\Kindo-DDC\VHDs2 -LogRollover 10
    Example above will process Office Container but not Profile Container settings, set a disk space buffer of 100GB, test two shares and rollover the log of its older than 10 days. 
.EXAMPLE
    .\DistributeContainerShares.ps1 -DiskSpaceBuffer 150 -ContainerShares \\Kindo-DC\VHDs,\\Kindo-DDC\VHDs2 -LogRollover 5 -DriveLetter X
    Example above will process both Office and Profile Container settings, set a disk space buffer of 150Gb, use the driver letter X and roll over log files older than 5 days
.NOTES
    12.04.2020 - James Kindon - Additions
        - Moved drive mappings to native powershell code - removed wscript components
        - Simplified math logic
        - Moved driver letter to variable: $DriveLetter
        - Added a Disk Buffer to ensure sufficient space on a share before adding to array: $DiskSpaceBuffer
        - Removed duplicate and redunant array objects
        - Renamed variables for easier understanding
        - Added full logging, output to $LogPath using Write-Log Function https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0
        - Added selective enablement for Profile and/or Office Container
        - Added full error handling for all mappings and registry key operations
        - Parameterised all components
        - Added LogFile rollover function
#>

# ============================================================================
# Parameters
# ============================================================================
#region Params
Param(
    # You may want to change this list below if you don't want to use parameters and simply accept defaults
    [Parameter(Mandatory = $false)]
    [Array]$ContainerShares = @(
        "\\Server1\FSLogix"
        "\\Server2\FSLogix",
        "\\Server3\FSLogix",
        "\\Stupid\Fakeshare"
    ),

    [Parameter(Mandatory = $false)]
    [string]$DriveLetter = "Z",

    [Parameter(Mandatory = $false)]
    [ValidateSet('True','False')]
    [string]$ProfileContainer = "True", #Enable configuration for Profile Containers. True or False

    [Parameter(Mandatory = $false)]
    [ValidateSet('True','False')]
    [string]$OfficeContainer = "True", #Enable configuration for Office Containers. True or False

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\FSLogixPathPlacementLogs\FSLogixPathLog.log", 

    [Parameter(Mandatory = $false)]
    [int]$DiskSpaceBuffer = 100, # minimum free space in Gb which to consider OK for share utilisation

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

function WriteDebugKey {
    param (
        [Parameter(Mandatory = $true)]
        $ContainerPath
    )
    Write-Log -Message "Creating Registry Debug Key with last known written values" -Level Info
    New-ItemProperty $ContainerPath -Name "scriptdebug" -Value $ShareResults -PropertyType "MultiString" -Force -ErrorAction SilentlyContinue | Out-Null
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
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.Seconds) seconds to complete." -Level Info
    }
}

function RollOverlog {
    $LogFile = $LogPath
    $LogOld = Test-Path $LogFile -OlderThan (Get-Date).AddDays(-$LogRollover)
    $RolloverDate = (Get-Date -Format "dd-MM-yyyy")
    if ($LogOld) {
        Write-Log -Message "$LogFile is older than $LogRollover days, rolling over" -Level Info
        $NewName = [io.path]::GetFileNameWithoutExtension($LogFile)
        $NewName = $NewName +"_$RolloverDate.log"
        Rename-Item -Path $LogFile -NewName $NewName
        Write-Log -Message "Old logfile name is now $NewName" -Level Info
    }    
}
#endregion

# ============================================================================
# Variables
# ============================================================================
#region Variables
$FSLogixProfilePath = "HKLM:\software\FSLogix\Profiles"
$FSLogixODFCPath = "HKLM:\SOFTWARE\Policies\FSLogix\ODFC"
$FSLogixKeyName = "VHDLocations"
#endregion

# ============================================================================
# Execute
# ============================================================================
#Region Execute

Write-Log -Message "--------Starting Iteration--------" -Level Info
RollOverlog
Start-Stopwatch

Write-Log -Message "---Reading Variables---"
Write-Log -Message "List of defined container shares: $ContainerShares" -Level Info
Write-Log -Message "Drive letter set to: $DriveLetter" -Level Info
Write-Log -Message "Profile Container set to: $ProfileContainer" -Level Info
Write-Log -Message "Office Container set to: $OfficeContainer" -Level Info
Write-Log -Message "Logpath set to: $LogPath" -Level Info
Write-Log -Message "Disk space buffer set to: $DiskSpaceBuffer" -Level Info

Write-Log -Message "---Processing---"
# Map a drive to each share, get the space available, add to custom object and remove drive
$ShareResults = @()
Write-Log -Message "Removing existing $DriveLetter mapping if it exists" -Level Info
Remove-PSDrive $DriveLetter -Force -ErrorAction SilentlyContinue | Out-Null
foreach ($Share in $ContainerShares) {
    Write-Log -Message "Attempting to map drive to share: $Share" -Level Info
    try {
        [void] (New-PSDrive -Name $DriveLetter -PSProvider "FileSystem" -Root $Share -Persist -ErrorAction Stop)
        Write-Log -Message "Getting share space for $Share" -Level Info
        $Space = [math]::Round((Get-PSDrive -Name $DriveLetter).Free / 1GB)
        
        Write-Log -message "Available space for share: $Share is $Space GB" -Level Info
        if ($Space -le $DiskspaceBuffer) {
            Write-Log -Message "$Share has less space than the specified buffer ($DiskSpaceBuffer) GB so is not being considered for Container placement" -Level Warn
        }
        else {
            $ShareAvailableSpace = New-Object -TypeName psobject
            $ShareAvailableSpace | Add-Member -membertype "NoteProperty" -Name "Share" -value $Share
            $ShareAvailableSpace | Add-Member -membertype "NoteProperty" -Name "FreeSpace" -value $Space
            $ShareResults += $ShareAvailableSpace
        }
        
        Write-Log -Message "Removing mapped drive $DriveLetter for share: $Share" -Level Info
        Remove-PSDrive -Name $DriveLetter -Force
    }
    catch {
        Write-Log -Message "Failed to map drive to $Share, please check path" -Level Warn
        Write-Log -Message "Share: $Share will not be included in VHD Location list for FSLogix Containers" -Level Warn
    }
}

# If no shares available, don't touch anything and exit
if (!($ShareResults)) {
    Write-Log -Message "There are no available shares for Container placement. No changes made. Exiting script" -Level Warn
    Stop-Stopwatch
    Write-Log -Message "--------Finished Iteration--------" -Level Info
    Exit 1
}
else {
    Write-Log -Message "There are share updates to be written. Proceeding" -Level Info

    # Output the Share Order base on FreeSpace 
    $OrderedShares = @()
    $SortedResults = $ShareResults | Sort-Object -Descending FreeSpace | Select-Object share
    foreach ($Item in $SortedResults) {
        $OrderedShares += $Item.Share.ToString()
    }
    Write-Log -Message "Ordered share value based on free space for FSLogix Containers is: $OrderedShares" -Level Info

    if ($ProfileContainer -eq "True") {
        Write-Log -Message "Profile Container configuration enabled" -Level Info
        # Create Profile Container Keys
        try {
            $ProfileKeyInitialValue = (Get-Item -path $FSLogixProfilePath -ErrorAction Stop).GetValue($FSLogixKeyName)
    
            if ($null -ne $ProfileKeyInitialValue) {
                Write-Log -Message "Current value for $FSLogixProfilePath\$FSLogixKeyName is: $ProfileKeyInitialValue" -Level Info
                Write-Log -Message "Removing current value" -Level Info
                try {
                    Remove-ItemProperty -path $FSLogixProfilePath -Name $FSLogixKeyName -Force -ErrorAction Stop
                    Write-Log -Message "Writing new Share values for $FSLogixKeyName as: $OrderedShares" -Level Info
                    New-ItemProperty $FSLogixProfilePath -Name $FSLogixKeyName -Value $OrderedShares -PropertyType "MultiString" -Force | Out-Null
                    WriteDebugKey -ContainerPath $FSLogixProfilePath
                }
                catch {
                    Write-Log -Message "Failed to delete $FSLogixProfilePath\$FSLogixKeyName. Not progressing any further" -Level Warn
                    Break
                }
            }
            else {
                Write-Log -Message "No existing value found for $FSLogixProfilePath\$FSLogixKeyName" -Level Info
            }
        }
        catch {
            Write-Log -Message "Failed to get key: $FSLogixProfilePath. Attempting to create" -level Warn
            Write-Log -Message "Succesfully created key and value: $FSLogixProfilePath\$FSLogixKeyName" -Level Info
            Write-Log -Message "Writing new share values for ODFC $FSLogixKeyName as: $OrderedShares" -Level Info
            try {
                New-Item -path $FSLogixProfilePath -Force -ErrorAction Stop | Out-Null
                New-ItemProperty $FSLogixProfilePath -Name $FSLogixKeyName -Value $OrderedShares -PropertyType "MultiString" -Force | Out-Null
                WriteDebugKey -ContainerPath $FSLogixProfilePath 
            }
            catch {
                Write-Log -Message "Failed to create Key: $FSLogixProfilePath. Exiting" -Level Warn
                Stop-Stopwatch
                Write-Log -Message "--------Finished Iteration--------" -Level Info
                Exit 1
            }
        }
    }
    else {
        Write-Log -Message "Profile Container configuration not enabled" -Level Info
    }

    if ($OfficeContainer -eq "True") {
        Write-Log -Message "Office Container configuration enabled" -Level Info
        # Create ODFC Container Keys
        try {
            $ODFCKeyInitialValue = (Get-Item -path $FSLogixODFCPath -ErrorAction Stop).GetValue($FSLogixKeyName)
            if ($null -ne $ODFCKeyInitialValue) {
                Write-Log -Message "Current value for $FSLogixODFCPath\$FSLogixKeyName is: $ODFCKeyInitialValue" -Level Info
                Write-Log -Message "Removing current value" -Level Info
                try {
                    Remove-ItemProperty -path $FSLogixODFCPath -Name $FSLogixKeyName -Force -ErrorAction Stop
                    Write-Log -Message "Writing new share values for Profiles $FSLogixKeyName as: $OrderedShares" -Level Info
                    New-ItemProperty $FSLogixODFCPath -Name $FSLogixKeyName -Value $OrderedShares -PropertyType "MultiString" -Force | Out-Null
                    WriteDebugKey -ContainerPath $FSLogixODFCPath
                }
                catch {
                    Write-Log -Message "Failed to delete $FSLogixODFCPath\$FSLogixKeyName. Not progressing any further" -Level Warn
                    Break
                }
            }
            else {
                Write-Log -Message "No existing value found for $FSLogixODFCPath\$FSLogixKeyName" -Level Info
            }
        }
        catch {
            Write-Log -Message "Failed to get key: $FSLogixODFCPath. Attempting to Create" -Level Warn
            Write-Log -Message "Succesfully created key and value: $FSLogixODFCPath\$FSLogixKeyName" -Level Info
            Write-Log -Message "Writing new share values for ODFC $FSLogixKeyName as: $OrderedShares" -Level Info
            try {
                New-Item -path $FSLogixODFCPath -Force -ErrorAction Stop | Out-Null
                New-ItemProperty $FSLogixODFCPath -Name $FSLogixKeyName -Value $OrderedShares -PropertyType "MultiString" -Force | Out-Null
                WriteDebugKey -ContainerPath $FSLogixODFCPath
            }
            catch {
                Write-Log -Message "Failed to create Key: $FSLogixODFCPath. Exiting" -level Warn
                Stop-Stopwatch
                Write-Log -Message "--------Finished Iteration--------" -Level Info
                Exit 1
            }
        }
    }
    else {
        Write-Log -Message "Office Container configuration not enabled" -Level Info
    }

    Stop-Stopwatch
    Write-Log -Message "--------Finished Iteration--------" -Level Info
    exit 0
}
#endregion

