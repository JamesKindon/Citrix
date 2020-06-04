
<#
.SYNOPSIS
    Quick script to list and export container sizes from a share
.DESCRIPTION
    Used to quickly assess state and size of containers with option export to CSV for analysis and trending
.PARAMETER ContainerPath
    Specify the root path for container assessment. can be local directory e:\Containers\ or share \\Server\Share
.PARAMETER Type
    Specify the type of Container to look for. Profile, Office, All. Default is All
.PARAMETER ExportCSV
    Choose to export data to CSV. Export file will be unique per run 
.PARAMETER CSVPath
    Specify a path for the CSV export. Default will be the location you querying based on the $ContainerPath variable
.PARAMETER LogPath
    Logpath output for all operations. Default will be the location you querying based on the $ContainerPath variable
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER SortBy
    Choose how to sort results. GB. MB or KB. Default is GB
.EXAMPLE
    .\GetContainerSizes.ps1 -ContainerPath \\Server\Share
    Gets all containers in the \\Server\Share Directory, sorts by Gb, and outputs logfile to the \\Server\Share Directory
.EXAMPLE
    .\GetContainerSizes.ps1 -ContainerPath \\Server\Share -Type Profile -exportcsv -CSVPath c:\temp\bob\stuff.csv -LogPath c:\temp\bob\stuff.log -SortBy MB -LogRollover 2
    Gets only profile containers in the \\Server\Share Directory, Exports to CSV with a custom path of c:\temp\bob\stuff.csv, outputs log file to c:\temp\bob\stuff.log, sorts in MB and rolls over log files older than 2 days
.EXAMPLE
    .\GetContainerSizes.ps1 -ContainerPath \\Server\Share -Type Office -exportcsv -SortBy MB
    Gets only Office containers in the \\Server\Share Directory, exports CSV to \\Server\Share directory, sorted by MB
.NOTES

#>

# ============================================================================
# Parameters
# ============================================================================
#region Params
param (
    [Parameter(Mandatory = $True, ValueFromPipeline = $true)] 
    [string]$ContainerPath,

    [Parameter(Mandatory = $False, ValueFromPipeline = $true)] [ValidateSet('Profile',
        'Office',
        'All')] [String] $Type = "All",

    [Parameter(Mandatory = $False, ValueFromPipeline = $true)] 
    [switch]$exportcsv,

    [Parameter(Mandatory = $False, ValueFromPipeline = $true)] 
    [string]$CSVPath = $ContainerPath + "\ContainerSizes_" + (Get-Date -Format "dd-MM-yyyy-h-m-s") + ".csv",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$ContainerPath\ContainerSizesLog.log",

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $False, ValueFromPipeline = $true)] [ValidateSet('GB',
        'MB',
        'KB')] [String] $SortBy = "GB"
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
        $NewName = $NewName + "_$RolloverDate.log"
        Rename-Item -Path $LogFile -NewName $NewName
        Write-Log -Message "Old logfile name is now $NewName" -Level Info
    }    
}

function GetContainerSize {
    
    Write-Log -Message "---Processing---" -Level Info
    Write-Log -Message "Getting $Type Containers Sizes in folder $ContainerPath"
    try {
        $Files = Get-ChildItem -Path $ContainerPath -Filter $Filter -Recurse -File -ErrorAction Stop
        $ContainerCount = ($Files | Measure-Object).Count
        Write-Log "Processing $($ContainerCount) Containers" -Level Info    
    }
    catch {
        Write-Log -Message "Failed to get file list. Please check path and permissions" -Level Warn
        Exit 1
    }

    $FilesAndSizes = @()
    foreach ($File in $Files) {
        $obj = New-Object -TypeName PSObject
        $obj | Add-Member -MemberType NoteProperty -Name Name -Value $file.Name
        $obj | Add-Member -MemberType NoteProperty -Name Path -Value $file.VersionInfo.FileName
        $obj | Add-Member -MemberType NoteProperty -Name SizeKB -Value ([math]::round($File.length / 1KB, 2))
        $obj | Add-Member -MemberType NoteProperty -Name SizeMB -Value ([math]::round($File.length / 1MB, 2))
        $obj | Add-Member -MemberType NoteProperty -Name SizeGB -Value ([math]::round($File.length / 1GB, 2))
        $FilesAndSizes += $obj
    }
    
    if ($Exportcsv.IsPresent) {
        if (!(Test-Path $CSVPath)) {
            Write-Log -Message "Creating $CSVPath" -Level Info
            try {
                New-Item -Path $CSVPath -Type File -force -ErrorAction Stop | Out-Null
                Write-Log -Message "Created $CSVPath" -Level Info
            }
            catch {
                Write-Log -Message "Failed to create $CSVPath. Exiting" -Level Warn
                Exit 1
            }
        }
        $FilesAndSizes | Export-CSV -NoTypeInformation -Path $CSVPath #Add Date here for tracking
        Write-Log -Message "CSV Output is $CSVPath" -Level Info
    }

    Write-Log "Sorting results by $SortBy" -Level Info
    if ($SortBy -eq "GB") {
        $FilesAndSizes | Select-Object Name, SizeKB, SizeMB, SizeGb | Sort-Object SizeGb
    }
    if ($SortBy -eq "MB") {
        $FilesAndSizes | Select-Object Name, SizeKB, SizeMB, SizeGb | Sort-Object SizeMB
    }
    if ($SortBy -eq "KB") {
        $FilesAndSizes | Select-Object Name, SizeKB, SizeMB, SizeGb | Sort-Object SizeKB
    }
    elseif ($null -eq $sortBy) {
        $FilesAndSizes | Select-Object Name, SizeKB, SizeMB, SizeGb
    }
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
Write-Log -Message "--------Starting Iteration--------" -Level Info

Start-Stopwatch

if ($Type -eq "Profile") {
    $Filter = "*Profile*.vhd*"
}
if ($Type -eq "Office") {
    $Filter = "*ODFC*.vhd*"
}
if ($Type -eq "All") {
    $Filter = "*.vhd*"
}

RollOverlog

GetContainerSize

Stop-Stopwatch
#endregion

