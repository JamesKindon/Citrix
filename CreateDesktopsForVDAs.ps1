<#
.SYNOPSIS
    Creates a Tag per VDA and Creates a dedicated desktop to launch only against that Tag
.DESCRIPTION
    Creates a Tag per VDA and Creates a dedicated desktop to launch only against that Tag. 
    Original Script by Martin Zugec. Original detail: https://www.citrix.com/blogs/2017/04/17/how-to-assign-desktops-to-specific-servers-in-xenapp-7/
    Updated by James Kindon
.PARAMETER DesktopGroupName
    Desktop Group name to target. Defaults to * all multi-session Desktop Grooups
.PARAMETER UserGroups
    Array of User Groups to assign the desktop too
.PARAMETER TagPrefix
    Tag Prefix. Defaults to ServerTag_. End result will be for example: ServerTag_Server01
.PARAMETER DesktopSuffix
    Suffix for the name of the desktop. Handy if you already have desktops with the server name in use. Defaults to _Admin. End result will be for example: ServerTag_Server01_Admin
.PARAMETER RemoveBrokerTags
    Removes all Tags that this script may have created - good for testing and wiping 
.PARAMETER RemoveDesktops
    Removes all published desktops that this script may have created - good for testing and wiping 
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.EXAMPLE
    .\CreateDesktopsForVDAs.ps1 -Usergroups "KINDO\Group1"
    Creates a Desktop for each multi session VDA in all Desktop Groups. Creates and Assigns a Tag in the default format of ServerTag_ServerName. Creates a Desktop with the forma of "ServerName_Admin". Assigns to "KINDO\Group1"
.EXAMPLE
    .\CreateDesktopsForVDAs.ps1 -Usergroups "KINDO\Group1" -DesktopGroupName "DG1"
     Creates a Desktop for each multi session VDA in the DG1 Desktop Group. Creates and Assigns a Tag in the default format of "ServerTag_ServerName". Creates a Desktop with the forma of "ServerName_Admin". Assigns to "KINDO\Group1"
.EXAMPLE
    .\CreateDesktopsForVDAs.ps1 -Usergroups "KINDO\Group1" -TagPrefix "Bob_" -DesktopSuffix "_Burt"
    Creates a Desktop for each multi session VDA in all Desktop Groups. Creates and Assigns a Tag in the format of "Bob_ServerName". Creates a Desktop with the format of "ServerName_Burt" Assigns to "KINDO\Group1"
.EXAMPLE
    .\CreateDesktopsForVDAs.ps1 -RemoveBrokerTags -TagPrefix "Bob_" -RemoveDesktops -DesktopSuffix "_Burt"
    Removes all desktops with the desktop name "ServerName_Burt". Removes all tags with the Tag Names "Bob_ServerName"
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\DesktopPerServer.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [string]$DesktopGroupName = "*", # Desktop Groups - Defaults to all

    [Parameter(Mandatory = $True)]
    [Array]$UserGroups = "",  # User Groups to assign tags - Typically an Admin Group

    [Parameter(Mandatory = $false)]
    [string]$TagPrefix = "ServerTag_", # Prefix for the Tag name

    [Parameter(Mandatory = $false)]
    [string]$DesktopSuffix = "_Admin", # Suffix for the Desktop

    [Parameter(Mandatory = $false)]
    [switch]$RemoveBrokerTags,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveDesktops

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

function CreateTag {
    try {
        Write-Log -Message "Creating Tag: $m_TagName" -Level Info
        $null = New-BrokerTag -Name $m_TagName -Description "Tag used to restrict resources to machine $($m_VDA.MachineName)" -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
}

function AssignTagToMachine {

    if ((Get-BrokerMachine -MachineName $m_VDA.MachineName).Tags -match "$m_TagName") {
        Write-Log -Message "Tag: $($m_TagName) already assigned to machine" -Level Info
    }
    else {
        try {
            Write-Log -Message "Assigning Tag: $($m_TagName) to Machine: $($m_VDA.MachineName)" -Level Info
            Add-BrokerTag -Name (Get-BrokerTag -Name $m_TagName).Name -Machine $m_VDA.MachineName -ErrorAction Stop    
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }    
    }
}

function CreateDesktop {
    # Create new entitlement policy rule
    if (Get-BrokerEntitlementPolicyRule -Name "$($m_SimpleMachineName)$($DesktopSuffix)" -ErrorAction SilentlyContinue) {
        Write-Log -Message "Desktop: $($m_SimpleMachineName)$($DesktopSuffix) already exists" -Level Info
    }
    else {
        try {
            Write-Log -Message "Creating Desktop: $($m_SimpleMachineName)$($DesktopSuffix) and restricting to Tag: $m_TagName" -Level Info
            $null = New-BrokerEntitlementPolicyRule "$($m_SimpleMachineName)$($DesktopSuffix)" -DesktopGroupUid $m_VDA.DesktopGroupUid -IncludedUsers $UserGroups -PublishedName $m_SimpleMachineName -RestrictToTag $m_TagName -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }    
    }
}

function RemoveBrokerTags {
    $Hosts = Get-BrokerMachine -SessionSupport MultiSession -DesktopGroupName $DesktopGroupName
    foreach ($Machine in $Hosts) {
        $m_SimpleMachineName = $($Machine.MachineName.Split('\')[1])
        $m_TagName = "$($TagPrefix)$($m_SimpleMachineName)"
        if ($m_TagName -in $Machine.Tags ) {
            Write-Log -Message "Machine: $($Machine.MachineName) with Tag: $($m_TagName) found. Removing" -Level Info
            Remove-BrokerTag -Name $m_TagName -Machine $Machine.MachineName
        }
        else {
            Write-Log -Message "Machine: $($Machine.MachineName) does not have a Tag to remove" -Level Info
        }
    }
}

function RemoveDesktops {
    $Hosts = Get-BrokerMachine -SessionSupport MultiSession -DesktopGroupName $DesktopGroupName
    foreach ($Machine in $Hosts) {
        [String]$m_SimpleMachineName = $($Machine.MachineName.Split('\')[1])
        $DesktopPolicy = Get-BrokerEntitlementPolicyRule -Name "$($m_SimpleMachineName)$($DesktopSuffix)" -ErrorAction SilentlyContinue
        if ($DesktopPolicy) {
            try {
                Write-Log -Message "Desktop: $($DesktopPolicy.Name) found. Removing" -Level Info
                Remove-BrokerEntitlementPolicyRule $DesktopPolicy.Name -ErrorAction Stop
            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }
    }    
}

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

Add-PSSnapin Citrix*

if ($RemoveBrokerTags.IsPresent) {
    RemoveBrokerTags
}

if ($RemoveDesktops.IsPresent) {
    RemoveDesktops
}

if ($RemoveBrokerTags.IsPresent -or $RemoveDesktops.IsPresent) {
    StopIteration
    Exit 0
}

$Hosts = Get-BrokerMachine -SessionSupport MultiSession -DesktopGroupName $DesktopGroupName
$Count = 1
Write-Log -Message "Processing $($Hosts.Count) Multi-Session hosts" -Level Info
ForEach ($m_VDA in $(Get-BrokerMachine -SessionSupport MultiSession -DesktopGroupName $DesktopGroupName)) {
    Write-Log "Processing Host $($Count) of $($Hosts.Count)"
    [String]$m_SimpleMachineName = $($m_VDA.MachineName.Split('\')[1])
    [String]$m_TagName = "$($TagPrefix)$($m_SimpleMachineName)"
        
    # Tag Creation Logic
        if (Get-BrokerTag -Name $m_TagName -ErrorAction SilentlyContinue) {
            Write-Log -Message "Tag: $($m_TagName) Exists" -Level Info
            AssignTagToMachine
        }
        else {
            CreateTag
        }
    
        # Tag Assignment Logic
        If ($m_VDA.Tags -notcontains $m_TagName) { 
            AssignTagToMachine 
        }
        
        # Desktop Creation Logic
        CreateDesktop

        $Count ++
}       

StopIteration
Exit 0
#endregion

