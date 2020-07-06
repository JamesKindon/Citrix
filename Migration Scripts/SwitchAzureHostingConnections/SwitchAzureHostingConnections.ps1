<#
.SYNOPSIS
    Switches Hypervisor connection objects in Azure to support ASR based failovers for dedicated/Persistent virtual machines
.DESCRIPTION
    Automates the migration of VM workloads to a new hosting connection for manually provisioned catalogs. 
    Cannot be used with MCS. For MCS provisioned dedicated machines, migrate to a manual catalog first.
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER JSON
    Will consume a JSON import for configuration
.PARAMETER JSONInputPath
    Specifies the JSON input file
.PARAMETER CatalogName
    Specifies the Catalog Name which contains the Target VMs to failover
.PARAMETER HostingConnectionSource
    Specifies the Source Hosting Connection of the VMs
.PARAMETER HostingConnectionTarget
    Specifies the Target Hosting connection for the VMs
.PARAMETER ResourceGroupTarget
    Specifies the Target Resource Group for the VMs. Used as part of the HostedMachine ID
.PARAMETER ZoneSource
    Specifies the Source Zone for the Catalog
.PARAMETER ZoneTarget
    Specifies the Target Zone for the Catalog
.EXAMPLE
    .\SwitchAzureHostingConnections.ps1 -JSON -JSONInputPath .\FailoverToAE.json
    The above example will consume a JSON input to move VM's to a new hosting connection, set a new HostedMachineID and migrate the Catalog to a new Zone (Resource Location)
.EXAMPLE
    .\SwitchAzureHostingConnections.ps1 -JSON -JSONInputPath .\FailbackToASE.json
    The above example will consume a JSON input and reverse the failover process
.EXAMPLE
    .\SwitchAzureHostingConnections.ps1 -CatalogName Kindon-Azure-SouthEastAsia-Dedicated `
    -HostingConnectionSource Kindon_Azure_SouthEastAsia `
    -HostingConnectionTarget Kindon_Azure_EastAsia `
    -ResourceGroupTarget RG-SEA-CitrixCloud-asr `
    -ZoneSource Kindon_Azure_SEA `
    -ZoneTarget Kindon_Azure_EA
.NOTES
    The basic premise of this script is to action the following:
    1. Grab all VMs in the Catalog
    2. Reset the Hosting Connection to the Target Hosting Connection (Failover Region)
    3. Reset the HostedMachineID based on the supplied Target Resource Group
    4. Confirm Catalog is in the Source Zone and then migrate the Catalog to the Target Zone (Resource Location)
    
    Unfortunately, we cannot currently automate setting the source hosting connection into, or out of maintenance mode. This is a manual task
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\AzureVDIFailover.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false, ParameterSetName = 'JSON')]
    [Switch]$JSON,

    [Parameter(Mandatory = $false, ParameterSetName = 'JSON')]
    [String]$JSONInputPath,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$CatalogName,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$HostingConnectionSource,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$HostingConnectionTarget,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$ResourceGroupTarget,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$ZoneSource,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$ZoneTarget
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

function ImportModule {
    Write-Log -Message "Importing $ModuleName Module" -Level Info
    try {
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to Import $ModuleName Module. Exiting" -Level Warn
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

function FailoverHostingConnection {
    Write-Log -Message "Processing machine $StartCount of $Count" -Level Info
    Write-Log -Message "Processing $($VM.MachineName)" -Level Info
    Write-Log -Message "$($VM.MachineName) has hosting connection $($VM.HypervisorConnectionName) with ID $($VM.HypervisorConnectionUid) and HypID $($VM.HypHypervisorConnectionUid)" -Level Info
    #Switch HostingConnectionUID and VM HostedMachineID
    if ($VM.HypervisorConnectionName -eq $HostingConnectionSourceDetail.Name) {
        Write-Log -Message "$($VM.MachineName) is operating on source hosting connection $($VM.HypervisorConnectionName)" -Level Info
        try {
            Write-Log -Message "Switching hosting connection to target $($HostingConnectionTarget) for $($VM.MachineName)" -Level Info
            Set-BrokerMachine -MachineName $VM.MachineName -HypervisorConnectionUid $HostingConnectionTargetDetail.Uid
            try {
                $NewHostedMachineId = $ResourceGroupTarget.ToLower() + "/" + ($VM.HostedMachineId | Split-Path -Leaf)
                Write-Log -Message "Setting VM hosted Machine ID to $($NewHostedMachineId) for $($VM.MachineName)" -Level Info
                Set-BrokerMachine -MachineName $VM.MachineName -HostedMachineId $NewHostedMachineId
            }
            catch {
                Write-Log -Message $_ -Level Warn
                Write-Log -Message "Failed to change hosted Machine ID for $($VM.MachineName)"
                Break
                $ErrorCount += 1
            }
        }
        catch {
            Write-Log -Message $_ -Level Warn
            Write-Log -Message "Failed to change hosting connection for $($VM.MachineName)"
            Break
            $ErrorCount += 1
        }
    }
    elseif ($VM.HypervisorConnectionName -eq $HostingConnectionTargetDetail.Name) {
        Write-Log -Message "Operating on target hosting connection. Nothing to action" -Level Info
    }
    else {
        Write-Log -Message "VM is operating on $($VM.HypervisorConnectionName) which is neither source or target hosting connections" -Level Warn
    }
    $StartCount += 1
}    

function SwitchCatalogZone {
    if ($Catalog.ZoneName -eq $ZoneSource) {
        Write-Log -Message "Catalog is operating in Source Zone: $ZoneSource. Switching to $ZoneTarget" -Level Info
        try {
            Set-BrokerCatalog -Name $CatalogName -ZoneUid (Get-ConfigZone -name $ZoneTarget).Uid
            Write-Log -Message "Successfully set Zone for $CatalogName to $ZoneTarget" -Level Info
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    elseif ($Catalog.ZoneName -eq $ZoneTarget) {
        Write-Log -Message "Catalog is operating in Target Zone: $ZoneTarget. No Action required" -Level Info
    }
    else {
        Write-Log -Message "The Catalog is a member of $($Catalog.ZoneName) which is neither the specified Source or Target Zone. No action taken" -Level Warn
    }    
}
#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

# ============================================================================
# Handle JSON input
# ============================================================================
if ($JSON.IsPresent) {
    Write-Log -Message "JSON input selected. Importing JSON data from: $JSONInputPath" -Level Info
    try {
        if (!(Test-Path $JSONInputPath)) {
            Write-Log -Message "Cannot find file: $JSONInputPath" -Level Warn
            StopIteration
            Exit 1
        }
        $EnvironmentDetails = Get-Content -Raw -Path $JSONInputPath -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        Write-Log -Message "JSON import failed. Exiting" -Level Warn
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }

    $CatalogName = $EnvironmentDetails.CatalogName #Catalog containing machines we are failing over
    $HostingConnectionSource = $EnvironmentDetails.HostingConnectionSource
    $HostingConnectionTarget = $EnvironmentDetails.HostingConnectionTarget
    $ResourceGroupTarget = $EnvironmentDetails.ResourceGroupTarget #This is required for updating hosted machine ID later on
    $ZoneSource = $EnvironmentDetails.ZoneSource
    $ZoneTarget = $EnvironmentDetails.ZoneTarget
}

# ============================================================================
# Handle Empty Values
# ============================================================================
if (!($CatalogName)) {
    Write-Log -Message "Missing value for Catalog Name. Exiting Script." -Level Warn
    StopIteration
    Exit 1
}
if (!($HostingConnectionSource)) {
    Write-Log -Message "Missing value for Source Hosting Connection. Exiting Script." -Level Warn
    StopIteration
    Exit 1
}
if (!($HostingConnectionTarget)) {
    Write-Log -Message "Missing value for Target Hosting Connection. Exiting Script." -Level Warn
    StopIteration
    Exit 1
}
if (!($ResourceGroupTarget)) {
    Write-Log -Message "Missing value for Target Resource Group. Exiting Script." -Level Warn
    StopIteration
    Exit 1
}
if (!($ZoneSource)) {
    Write-Log -Message "Missing value for Source Zone. Exiting Script." -Level Warn
    StopIteration
    Exit 1
}
if (!($ZoneTarget)) {
    Write-Log -Message "Missing value for Target Zone. Exiting Script." -Level Warn
    StopIteration
    Exit 1
}

# ============================================================================
# Load Snapins
# ============================================================================
try {
    Write-Log -Message "Loading Citrix Snapins" -Level Info
    Add-PSSnapin citrix*
}
catch {
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}

# ============================================================================
# Try for Authentication
# ============================================================================
try {
    Write-Log -Message "Confirming Authentication with Citrix Cloud" -Level Info
    $null = Get-BrokerSite -ErrorAction Stop # This should trigger an auth call if session has timed out (else Get-XDAuthentication)
}
catch {
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}

# ============================================================================
# Get Environment Details
# ============================================================================
Write-Log -Message "Working with Catalog: $($CatalogName)" -Level Info
Write-Log -Message "Working with Source Hosting Connection: $($HostingConnectionSource)" -Level Info
Write-Log -Message "Working with Target Hosting Connection: $($HostingConnectionTarget)" -Level Info
Write-Log -Message "Working with Target Resource Group: $($ResourceGroupTarget)" -Level Info
Write-Log -Message "Working with Source Zone: $($ZoneSource)" -Level Info
Write-Log -Message "Working with Target Zone: $($ZoneTarget)" -Level Info

# Get Catalog Details
$Catalog = try {
    Write-Log -Message "Attempting to get Catalog details for $($CatalogName)"
    Get-BrokerCatalog -Name $CatalogName -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    Write-Log -Message "Could not get Catalog. Exit Script" -Level Warn
    StopIteration
    Exit 1
}

# Only support Manual Catalogs
if ($Catalog.ProvisioningType -eq "Manual") {
    Write-Log -Message "Catalog $CatalogName is a Manually provisioned Catalog. Proceeding" -Level Info
}
else {
    Write-Log -Message "Catalog $CatalogName is a $($Catalog.ProvisioningType) provisioned Catalog and cannot be utilised. Exit Script" -Level Warn
    StopIteration
    Exit 1
}

# Get Hosting Details
$HostingConnectionSourceDetail = try {
    Write-Log -Message "Attempting to get Source Hosting Connection details" -Level Info
    Get-BrokerHypervisorConnection -Name $HostingConnectionSource -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    Write-Log -Message "Could not get Hosting Connection: $HostingConnectionSource. Exit Script" -Level Warn
    StopIteration
    Exit 1
}

$HostingConnectionTargetDetail = try {
    Write-Log -Message "Attempting to get Target Hosting Connection details" -Level Info
    Get-BrokerHypervisorConnection -Name $HostingConnectionTarget -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    Write-Log -Message "Could not get Hosting Connection: $HostingConnectionTarget. Exit Script" -Level Warn
    StopIteration
    Exit 1
}

# Get VM Details
$VMS = try {
    Write-Log -Message "Attempting to get virtual machine details" -Level Info
    Get-BrokerMachine -CatalogName $Catalog.Name -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}

# Get machine count
$Count = ($VMs | Measure-Object).Count

if ($null -eq $Count) {
    Write-Log -Message "There are no machines to process. Exit Script" -Level Warn
    StopIteration
    Exit 0
}
else {
    Write-Log -Message "Machine Count to process: $($Count)" -Level Info
}

# ============================================================================
# Execute the failover tasks
# ============================================================================
$StartCount = 1
$ErrorCount = 0

foreach ($VM in $VMs) {
    FailoverHostingConnection
}

# Switch Catalog Zone
SwitchCatalogZone

# Check error count
if ($ErrorCount -ne "0") {
    Write-Log -Message "There are $ErrorCount errors recorded. Please review logfile $LogPath"
}

Write-Log -Message "#####------------------------------------------------------------------------#####" -Level Warn
Write-Log -Message "#####--------------------------------CRITICAL--------------------------------#####" -Level Warn
Write-Log -Message "##     If you are failing over a region with a dedicated hosting connection     ##" -Level Warn
Write-Log -Message "##     you MUST set the current hosting connection into maintenance mode.       ##" -Level Warn
Write-Log -Message "##                                                                              ##" -Level Warn
Write-Log -Message "##  If you are failing back, remove hosting connection from maintenance mode.   ##" -Level Warn
Write-Log -Message "#####------------------------------------------------------------------------#####" -Level Warn
Write-Log -Message "#####------------------------------------------------------------------------#####" -Level Warn

StopIteration
Exit 0
#endregion
