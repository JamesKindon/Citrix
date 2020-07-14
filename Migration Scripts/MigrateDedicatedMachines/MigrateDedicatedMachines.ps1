<#
.SYNOPSIS
    via an exported XML from an existing dedicated VDI catalog (Power Managed), migrate machines to Citrix Cloud with new hosting connection mappings
.DESCRIPTION
    requires a clean export of an existing catalog to Clixml (See notes)
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER JSON
    Will consume a JSON import for configuration
    JSON requires the following sourced from Citrix Environment
        HostingConnectionName - sourced via (Get-BrokerHypervisorConnection | Select-Object Name)
        CatalogName - sourced via (Get-BrokerCatalog | Select-Object Name)
        PublishedName - "Display name Here" 
        DeliveryGroupName - sourced via (Get-BrokerDesktopGroup | Select-Object Name)
.PARAMETER JSONInputPath
    Specifies the JSON input file
 .PARAMETER InputPath
    Specifies the CLIXML file for import
.EXAMPLE
    .\MigrateDedicatedMachines.ps1
    Will prompt for VM input, and all environment destination details (via Get commands and GridView) if variables not set
.EXAMPLE
    .\MigrateDedicatedMachines.ps1 -InputPath c:\migration\vms.xml
    Will take vm input from specified xml, and then prompt for all environment destination details (via Get commands and GridView) if variables not set
.EXAMPLE
    .\MigrateDedicatedMachines.ps1 -JSON -JSONInputPath c:\migration\EnvironmentDetails.json -InputPath c:\migration\vms.xml
    Will take both JSON input for environment details, and VM input based on specified XML file
.NOTES
    Export required information from existing catalog. Example:

    $CatalogName = 'CATALOGNAMEHERE'
    $ExportLocation = 'PATH HERE\vms.xml'
    Get-BrokerMachine -CatalogName $CatalogName -MaxRecordCount 100000 | Export-Clixml $ExportLocation

    TODO
        - Add Export Function
        - Add JSON creation Function
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\MachineMigration.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs
    
    [Parameter(Mandatory = $false)]
    [Switch]$JSON,

    [Parameter(Mandatory = $false)]
    [String]$JSONInputPath,

    [Parameter(Mandatory = $false)]
    [String]$InputFile
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

function AddVMtoCatalog {
    if ($null -eq (Get-BrokerMachine -MachineName $VM.MachineName -ErrorAction SilentlyContinue)) {
        Write-Log -Message "Adding $($VM.MachineName) to Catalog $($Catalog.Name)" -Level Info
        try {
            $null = New-BrokerMachine -CatalogUid $Catalog.Uid -HostedMachineId $VM.HostedMachineId -HypervisorConnectionUid $HostingConnectionDetail.Uid -MachineName $VM.SID -Verbose -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    else {
        Write-Log -Message "Machine $($VM.MachineName) already exists in catalog $($VM.CatalogName)" -Level Warn
    }
}

function AddVMtoDeliveryGroup {
    $DG = (Get-BrokerMachine -MachineName $VM.MachineName).DesktopGroupName
    if ($null -eq $DG) {
        Write-Log -Message "Adding $($VM.MachineName) to DesktopGroup $DeliveryGroupName" -Level Info
        try {
            Add-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $DeliveryGroupName -Verbose -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    else {
        Write-Log -Message "$($VM.MachineName) already a member of: $DG" -Level Warn
    } 
}

function AddUsertoVM {
    Write-Log -Message "Attempting User Assignments" -Level Info
    $AssignedUsers = $VM.AssociatedUserNames
    if ($AssignedUsers) {
        Write-Log -Message "Processing $($VM.MachineName)" -Level Info
        foreach ($User in $AssignedUsers) {
            Write-Log -Message "Adding $($User) to $($VM.MachineName)" -Level Info
            try {
                Add-BrokerUser $User -PrivateDesktop $VM.MachineName -Verbose -ErrorAction Stop
            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }
    }
    else {
        Write-Log -Message "There are no user assignments defined for $($VM.MachineName)" -Level Warn
    }
}

function SetVMDisplayName {
    if ($null -ne $PublishedName) {
        Write-Log -Message "Setting Published Name for $($VM.MachineName) to $PublishedName" -Level Info
        try {
            Set-BrokerMachine -MachineName $VM.MachineName -PublishedName $PublishedName -Verbose -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -level Warn
        }
    }
}
#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================

# Optionally set configuration without being prompted
#$VMs = Import-Clixml -Path 'Path to XML Here'
#$HostingConnectionName = "Hosting Connection Name Here" #(Get-BrokerHypervisorConnection | Select-Object Name)
#$CatalogName = "Catalog Name Here" #(Get-BrokerCatalog | Select-Object Name)
#$PublishedName = "Display name Here" 
#$DeliveryGroupName = "Delivery Group Name here" #(Get-BrokerDesktopGroup | Select-Object Name)

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

# Load Assemblies
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

# Import CLIXML Config File
if ($InputFile.IsPresent) {
    $VMs = try {
        Import-Clixml -Path $InputFile -ErrorAction Stop
    }
    catch {
        Write-Log $_ -Level Warn
        StopIteration
        Exit 1
    }
}

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

    $HostingConnectionName = $EnvironmentDetails.HostingConnectionName
    $CatalogName = $EnvironmentDetails.CatalogName
    $PublishedName = $EnvironmentDetails.PublishedName
    $DeliveryGroupName = $EnvironmentDetails.DeliveryGroupName
}

# Import Citrix Snapins
try {
    Add-PSSnapin citrix* -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -level Warn
    StopIteration
    Exit 1
}

# Try for Auth
try {
    Get-XDAuthentication -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -level Warn
    Write-Log -Message "Failed to Authenticate. Exiting" -Level Warn
    StopIteration
    Exit 1
}

# If Not Manually set, prompt for variable configurations
if ($null -eq $VMs) {
    Write-Log -Message "Please Select an XML Import File" -Level Info
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter           = 'XML Files (*.xml)|*.*'
    }
    $null = $FileBrowser.ShowDialog()
    try {
        $VMs = Import-Clixml -Path $FileBrowser.FileName -ErrorAction Stop
    }
    catch {
        Write-Log -Message "No input file selected. Exit" -Level Warn
        StopIteration
        Exit 1
    }
}

#Optionally prompt for Hosting, Catalogs and Delivery Groups if not set
if ($null -eq $HostingConnectionName) {
    $HostingConnectionName = Get-BrokerHypervisorConnection | Select-Object Name, State, IsReady | Out-GridView -PassThru -Title "Select a Hosting Connection"
}

if ($null -eq $CatalogName) {
    $CatalogName = Get-BrokerCatalog | Select-Object Name, AllocationType, PersistUserChanges, ProvisioningType, SessionSupport, ZoneName | Out-GridView -PassThru -Title "Select a Destination Catalog"
}

if ($null -eq $DeliveryGroupName) {
    $DeliveryGroupName = Get-BrokerDesktopGroup | Select-Object Name, DeliveryType, Description, DesktopKind, Enabled, SessionSupport | Out-GridView -PassThru -Title "Select a Desktop Group"
}

Write-Log -Message "Hosting Connection name is set to: $($HostingConnectionName)" -Level Info
Write-Log -Message "Catalog name is set to: $($CatalogName)" -Level Info
Write-Log -Message "Delivery Group name is set to: $($DeliveryGroupName)" -Level Info
if ($null -ne $PublishedName) {
    Write-Log -Message "Published name is set to: $($PublishedName)" -Level Info
}

# Try to get Catalog
$Catalog = try {
    Get-BrokerCatalog -Name $CatalogName -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}

#Try to get Hosting Connection
$HostingConnectionDetail = try {
    Get-BrokerHypervisorConnection | Where-Object { $_.Name -eq $HostingConnectionName } -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}

$Count = ($VMs | Measure-Object).Count
$StartCount = 1

Write-Log -Message "There are $Count machines to process" -Level Info

foreach ($VM in $VMs) {
    Write-Log -Message "Processing machine $StartCount of $Count" -Level Info

    AddVMtoCatalog
    AddVMtoDeliveryGroup
    SetVMDisplayName
    AddUsertoVM
    
    $StartCount += 1
}

StopIteration
#endregion

