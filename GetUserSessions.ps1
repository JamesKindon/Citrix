
<#
.SYNOPSIS
    Script to hunt for sessions based on StoreFront launch points
.DESCRIPTION
    Used to assist in identifying which storefront servers (and often thus, Gateways) users are connecting from
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER Controllers
    Specify Controllers to target
.PARAMETER StoreFrontServers
    Optionalfilter array to query specific StoreFront Servers (LaunchedViaHostName). Wilcards are accepted, Eg, *Kindo-SF*
.PARAMETER DeliveryGroups
    Optional filter array to query specific Delivery Groups
.PARAMETER UserFilter
    Optional filter array to query specific usernames DOMAIN\User
.PARAMETER ReportFolder
    Output folder for the CSV reports to land in. Defaults to C:\Temp
.PARAMETER OutputToConsole
    Optionally outputs report to console in table format
.Example
    .\GetConnectionsByStoreFront.ps1 -Controllers "JKDC01","BigBobDC02" -ReportFolder "c:\temp"
    Queries Controllers "JKDC01" and "BigBobDC02" for all sessions. Searches all Delivery Groups and outputs data to c:\temp\
.Example
    .\GetConnectionsByStoreFront.ps1 -Controllers "JKDC01","BigBobDC02" -StoreFrontServers "*JK-SF*","*OLDSF*" -ReportFolder "c:\temp"
    Queries Controllers "JKDC01" and "BigBobDC02" for sessions launched via StoreFront Servers matching any name including "JK-SF" or "OLDSF". Searches all Delivery Groups and outputs data to c:\temp\
.Example
    .\GetConnectionsByStoreFront.ps1 -Controllers "JKDC01","BigBobDC02" -StoreFrontServers "*JK-SF*","*OLDSF*" -ReportFolder "c:\temp" -DeliveryGroups "DG1","Silly DG3"
    Queries Controllers "JKDC01" and "BigBobDC02" for sessions launched via StoreFront Servers matching any name including "JK-SF" or "OLDSF". Searches Delivery Groups "DG1" and "Silly DG3" and outputs data to c:\temp\
.Example
    .\GetConnectionsByStoreFront.ps1 -Controllers "JKDC01","BigBobDC02" -StoreFrontServers "*JK-SF*","*OLDSF*" -ReportFolder "c:\temp" -DeliveryGroups "DG1","Silly DG3" -OutputToConsole
    Queries Controllers "JKDC01" and "BigBobDC02" for sessions launched via StoreFront Servers matching any name including "JK-SF" or "OLDSF". Searches Delivery Groups "DG1" and "Silly DG3", outputs data to c:\temp\ and outputs report to console
.Example
    .\GetConnectionsByStoreFront.ps1 -Controllers "JKDC01","BigBobDC02" -StoreFrontServers "*JK-SF*","*OLDSF*" -ReportFolder "c:\temp" -DeliveryGroups "DG1","Silly DG3" -UserFilter "DOMAIN\KindonJ" -OutputToConsole
    Queries Controllers "JKDC01" and "BigBobDC02" for sessions launched via StoreFront Servers matching any name including "JK-SF" or "OLDSF". Searches Delivery Groups "DG1" and "Silly DG3", Filters to only the DOMAIN\KindonJ user, outputs data to c:\temp\ and outputs report to console

#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\GetCVADSessions.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $True)]
    [Array]$Controllers = @(),

    [Parameter(Mandatory = $False)]
    [Array]$StoreFrontServers = @(),

    [Parameter(Mandatory = $False)]
    [Array]$DeliveryGroups = @(),

    [Parameter(Mandatory = $False)]
    [Array]$UserFilter = @(),

    [Parameter(Mandatory = $False)]
    [string]$ReportFolder = "c:\Temp",
    
    [Parameter(Mandatory = $False)]
    [Switch]$OutputToConsole

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

function ImportModule {
    param (
        [Parameter(Mandatory = $True)]
        [String]$ModuleName
    )
    Write-Log -Message "Importing $ModuleName Module" -Level Info
    try {
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to Import $ModuleName Module. Exiting" -Level Warn
        StopIteration
        Exit 1
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
# Set Variables

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

$AllUsers = @()

foreach ($Controller in $Controllers) {
    Write-Log -Message "Controller $($Controller): Processing sessions" -Level Info
    if ($StoreFrontServers.Count -eq "0") {
        Write-Log -Message "Controller $($Controller): No StoreFront StoreFront filtering specified. Including all StoreFront Servers" -Level Info
        $Sessions = Get-BrokerSession -AdminAddress $Controller -MaxRecordCount 100000
        $SessionCount = ($Sessions | Measure-Object).Count
        Write-Log -Message "Controller $($Controller): Found $($SessionCount) sessions" -Level Info
        $AllUsers += $Sessions
    }
    else {
        Write-Log -Message "Controller $($Controller): StoreFront Server filtering enabled" -Level info
        foreach ($StoreFront in $StoreFrontServers) {
            Write-Log -Message "Controller $($Controller): Processing sessions launched via StoreFront Server (Pattern Match): $($StoreFront)"
            try {
                if ($DeliveryGroups.Count -eq "0") {
                    Write-Log -Message "Controller $($Controller): No Delivery Group filtering specified. Searching all Delivery Groups" -Level Info
                    $Sessions = Get-BrokerSession -AdminAddress $Controller -MaxRecordCount 100000 | Where-Object {$_.LaunchedViaHostName -like "*$StoreFront*"}
                }
                else {
                    Write-Log -Message "Controller $($Controller): Delivery Group filtering enabled" -Level info
                    foreach ($DG in $DeliveryGroups) {
                        Write-Log -Message "Controller $($Controller): Searching Delivery Group: $($DG)" -Level Info
                    }
                    $Sessions = Get-BrokerSession -AdminAddress $Controller -MaxRecordCount 100000 | Where-Object {$_.LaunchedViaHostName -like "*$StoreFront*" -and $_.DesktopGroupName -in $DeliveryGroups}
                }
                $SessionCount = ($Sessions | Measure-Object).Count
                Write-Log -Message "Controller $($Controller): Found $($SessionCount) sessions launched via StoreFront Server (Pattern Match): $($StoreFront)" -Level Info
                $AllUsers += $Sessions
            }
            catch {
                Write-Log -Message $_ -Level Warn
                Break
            }
        }
    }
}

#Filter Users
if ($UserFilter.count -ne 0) {
    $AllUsers = $AllUsers | Where-Object {$_.UserName -in $UserFilter}
}

# Create report for output
$Report = @()

foreach ($User in $AllUsers) {
    try {
    $UserDetails = New-Object PSObject

    $ADUser = Get-ADUser -Filter "UserPrincipalName -eq '$($User.UserUPN)'" -Properties * -ErrorAction Stop

    $UserDetails = New-Object PSObject -Property @{
        FirstName = $ADUser.GivenName
        LastName = $ADUser.Surname
        Email = $ADUser.mail
        Username = $User.UserName
        MachineName = Split-Path $user.MachineName -leaf
        LaunchedViaHostName = $user.LaunchedViaHostName
        Controller = $User.ControllerDNSName
        DesktopGroupName = $User.DesktopGroupName
        SessionState = $User.SessionState
    }

    $report += $UserDetails
    }
    Catch {
        Write-Log -Message "$_" -Level Warn
    }
}

$Count = ($AllUsers | Measure-Object).Count
Write-Log -Message "There are $($Count) connections matching the search criteria" -Level Info
$Date = Get-Date -Format hh-mm_dd-MM-yyyy

$Outfile = $ReportFolder + "\CVAD_Connections_$Date.csv"
$report | Select-Object FirstName,LastName,UserName,Email,DesktopGroupName,MachineName,SessionState,LaunchedViaHostName | Export-Csv -NoTypeInformation $Outfile
Write-Log -Message "Report is located at $Outfile" -Level Info
if ($OutputToConsole.IsPresent) {
    $report | Select-Object FirstName,LastName,UserName,Email,DesktopGroupName,MachineName,SessionState,LaunchedViaHostName | Format-Table
}

StopIteration
Exit 0
#endregion
