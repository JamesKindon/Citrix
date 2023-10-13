<#
.SYNOPSIS
    Migrates dedicated Citrix Single Session Desktops to a new Citrix site.
.DESCRIPTION
    Migrates dedicated Citrix Single Session Desktops to a new Citrix Site. 
    Supports both manual and MCS provisioned full cloned desktops. Also supports removing the source VMs from the source site if required.
.PARAMETER LogPath
    Optional. Logpath output for all operations. The default is C:\Logs\MigrateDedicatedMachines.log
.PARAMETER LogRollover
    Optional. Number of days before logfiles are rolled over. Default is 5.
.PARAMETER SourceController
    Mandatory. The Controller where the source machines can be found.
.PARAMETER TargetController
    Mandatory. The Controller where the target machines will go.
.PARAMETER TargetCatalog
    Optional. The Catalog where machines will go. If not specified, the target controller will be queried and a list of appropriate catalogs will be presented.
.PARAMETER TargetDeliveryGroup
    Optional. The Delivery Group where machines will go. If not specified, the target controller will be queried and a list of appropriate Delivery Groups will be presented.
.PARAMETER TargetHostingConnection
    Optional. The name of the Hosting Connection hosting the machine in the target site. If not specified, the target controller will be queried and a list of appropriate Hosting Connections will be presented.
.PARAMETER TargetMachineScope
    Mandatory. The method used to target machine scoping. Can be either:
        - MachineList (an array). Used with the TargetMachineList parameter.
        - Catalog (a string). Used with the SourceCatalog parameter.
.PARAMETER TargetMachineList
    Optional. An array of machines to target. "Machine1","Machine2","Machine3". Used with the TargetMachineScope parameter when set to MachineList.
.PARAMETER SourceCatalog
    Optional. If choosing to use a Catalog as the source of machines, the SourceCatalog parameter is required
.PARAMETER ExclusionList
    Optional. A list of machines to exclude from processing. Used regardless of the the TargetmachineScope parameter.
.PARAMETER IncludeMCSMachinesFromSource
    Optional. By default, MCS machines are excluded, however you can include them using this parameter.
.PARAMETER RemoveVMFromSource
    Optional. Allows the script to remove the migrated machine from the source environment. This includes removing ProvVM components in an MCS scenario if the IncludeMCSMachinesFromSource is used.
.PARAMETER SetMaintenanceModeInTarget
    Optional. Allows setting maintenance mode on the machines moved to the target site.
.PARAMETER SetMaintenanceModeInSource
    Optional. Allows setting maintenance mode on the machines in the source site.
.PARAMETER PublishedName
    Optional. Allows setting the PublishedName on the target desktop. Supports both MatchSourceDG and New. 
        - If using MatchSourceDG, the source Delivery Group will be queried and the target machines will have their PublishedName set to this value. This helps with consistency.
        - If using New, then you must specify the NewPublishedName Parameter and value.
        - If not set, the PublishedName will be retained from the source machine which may well be blank.
.PARAMETER NewPublishedName
    Optional. The value of the Published Name if the PublishedName parameter is used.
.PARAMETER ResetTargetHostingConnection
    Optional. Reset the Target Hosting Connection if any machine objects are altered. This removes the Sync delay between Citrix and the Hosting platform and allows power status to be retrieved.
.PARAMETER MaxRecordCount
    Optional. The max number of machines to be queried in the source and target sites. The default is 1000.
.PARAMETER Whatif
    Optional. Will action the script in a whatif processing mode only.
.PARAMETER HideSourceMCSWarning
    Optional. If you enable MCS inclusion via IncludeMCSMachinesFromSource parameter and you enable RemoveVMFromSource, a warning/disclaimer will be shown due to discrepencies in Citrix Powershell versions
        You can hide this warning if you have tested appropriately.
.NOTES
    This script identified an issue specifically with Studio 2305 Powershell based modules/snapins targetting a Citrix 2203 LTSR environment. 
    In this scenario, the -ForgetVM switch is ignored when handling ProvVM deletions. This means that the machine is deleted from the hypervisor.
    This issue does not occur when versions are aligned. This is a known, but currently undocumented issue by Citrix. You have been warned. Test first.
    This issue only presents if you use the RemoveVMFromSource switch with IncludeMCSMachinesFromSource also selected.
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\MigrateDedicatedMachines.log", # Where we log to

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # Number of days before logfile rollover occurs

    [Parameter(Mandatory = $true)]
    [ValidateSet("MachineList", "Catalog")]
    [string]$TargetMachineScope, # The method used to target machine scoping.

    [Parameter(Mandatory = $false)]
    [Array]$TargetMachineList,

    [Parameter(Mandatory = $false)]
    [string]$SourceCatalog,

    [Parameter(Mandatory = $false)]
    [array]$ExclusionList, # List of vm names to exclude.

    [Parameter(Mandatory = $false)]
    [String]$TargetHostingConnection, # The Target Hosting Connection Name pointing to the Target Nutanix Cluster.

    [Parameter(Mandatory = $false)]
    [Switch]$ResetTargetHostingConnection, # Reset the target Hosting Connection.

    [Parameter(Mandatory = $false)]
    [switch]$Whatif, # will process in a whatif mode without actually altering anything

    [Parameter(Mandatory = $true)]
    [String]$SourceController,

    [Parameter(Mandatory = $true)]
    [String]$TargetController,

    [Parameter(Mandatory = $false)]
    [String]$TargetCatalog,

    [Parameter(Mandatory = $false)]
    [String]$TargetDeliveryGroup,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMCSMachinesFromSource,

    [Parameter(Mandatory = $false)]
    [switch]$SetMaintenanceModeInTarget,

    [Parameter(Mandatory = $false)]
    [switch]$SetMaintenanceModeInSource,

    [Parameter(Mandatory = $false)]
    [ValidateSet("MatchSourceDG", "New")]
    [String]$PublishedName,

    [Parameter(Mandatory = $false)]
    [String]$NewPublishedName,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveVMFromSource,

    [Parameter(Mandatory = $false)]
    [int]$MaxRecordCount = 1000,

    [Parameter(Mandatory = $false)]
    [switch]$HideSourceMCSWarning

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

function ValidateCitrixController {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AdminAddress
    )

    try {
        Write-Log -Message "[Citrix Validation] Validating Citrix Site is contactable at Delivery Controller: $($AdminAddress)" -Level Info
        $Site = Get-BrokerSite -AdminAddress $AdminAddress -ErrorAction Stop
        Write-Log -Message "[Citrix Validation] Successfully Validated Citrix Site: $($Site.Name) is contactable at Delivery Controller: $($AdminAddress)" -Level Info
    }
    catch {
        Write-Log -Message "[Citrix Validation] Failed to validate Citrix Delivery Controller: $($AdminAddress)" -Level Warn
        Write-Host $_
        StopIteration
        Exit 1
    }
}

function WriteWarningAboutMCSRemoval {

    Write-Log -Message "`n
    ======================================================================================================================================================
     ___    ___   ___    ___   _        _     ___   __  __   ___   ___ 
    |   \  |_ _| / __|  / __| | |      /_\   |_ _| |  \/  | | __| | _ \
    | |) |  | |  \__ \ | (__  | |__   / _ \   | |  | |\/| | | _|  |   /
    |___/  |___| |___/  \___| |____| /_/ \_\ |___| |_|  |_| |___| |_|_\
                                
    ======================================================================================================================================================

    You have selected to remove MCS provisioned machines from the source environment. Whilst this is a great option, you need to test and validate that the behaviour is as expected. `n
    There are several scenarios that this script cannot control when it comes to ProvVM removal challenges. `n
    For example, if you are using a newer version of the Citrix PowerShell Snapins than your site is currently running, the -ForgetVM switch may not operate as documented, and the VM entity will be removed/deleted (yes deleted) from the hypervisor. `n
    This is not a script logic issue, it is a functional problem not yet documented publically by Citrix at time of this script release. `n
    If you are running this script on a Delivery Controller, you will be fine. If you are running this script from an Admin Server and the following scenario is true, then you need to test this script before proceeding at scale: `n
    Delivery Controller/Site version = 2203 (example) and Admin Server Studio/PowerShell snapin version is 2305 (example) `n
    ======================================================================================================================================================
    " -Level Warn

    do { $userChoice = Read-Host -Prompt "Have you tested MCS removal and want to continue? (Y[es]/N[o])" } 
    while ($userChoice -notmatch '[ynYN]')
    $userChoice = $userChoice.ToLower()

    if ($userChoice -eq "n") {
        Write-Log -Message "[User Consent] Consent has not been granted. Script will exit." -Level Info
        StopIteration
        Exit 0
    } 
    else {
        Write-Log -Message "[User Consent] Consent has been granted. Assuming testing has been completed. Proceeding." -Level Info
    }

}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
$full_clone_check_list = @("VCenter","VmwareFactory","XenServer","XenFactory","SCVMM","MicrosoftPSFactory")
#endregion Variables

#region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

#region script parameter reporting
#------------------------------------------------------------
# Script processing detailed reporting
#------------------------------------------------------------
Write-Log -Message "[Script Params] Logging Script Parameter configurations" -Level Info
Write-Log -Message "[Script Params] Script LogPath = $($LogPath)" -Level Info
Write-Log -Message "[Script Params] Script LogRollover = $($LogRollover)" -Level Info
Write-Log -Message "[Script Params] Script Whatif = $($Whatif)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Machine Scope = $($TargetMachineScope)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Machine List = $($TargetMachineList)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Hosting Connection Name = $($TargetHostingConnection)" -Level Info
Write-Log -Message "[Script Params] Citrix Reset Target Hosting Connection = $($ResetTargetHostingConnection)" -Level Info
Write-Log -Message "[Script Params] VM ExclusionList = $($ExclusionList)" -Level Info
Write-Log -Message "[Script Params] Citrix Source Catalog = $($SourceCatalog)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Controller = $($TargetController)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Catalog = $($TargetCatalog)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Delivery Group = $($TargetDeliveryGroup)" -Level Info
Write-Log -Message "[Script Params] Citrix Include MCS Machines from Source = $($IncludeMCSMachinesFromSource)" -Level Info
Write-Log -Message "[Script Params] Citrix Set Maintenance Mode in Target = $($SetMaintenanceModeInTarget)" -Level Info
Write-Log -Message "[Script Params] Citrix Set Maintenance Mode in Source = $($SetMaintenanceModeInSource)" -Level Info
Write-Log -Message "[Script Params] Citrix Published Name = $($PublishedName)" -Level Info
Write-Log -Message "[Script Params] Citrix New Published Name = $($NewPublishedName)" -Level Info
Write-Log -Message "[Script Params] Citrix Remove VM From Source = $($RemoveVMFromSource)" -Level Info
Write-Log -Message "[Script Params] Citrix Max Record Count = $($MaxRecordCount)" -Level Info
Write-Log -Message "[Script Params] Citrix MCS Warning Override = $($HideSourceMCSWarning)" -Level Info
#endregion script parameter reporting

#check PoSH version
if ($PSVersionTable.PSVersion.Major -lt 5) { 
    Write-Log -Message "[ERROR] Please upgrade to Powershell v5 or above (https://www.microsoft.com/en-us/download/details.aspx?id=50395)" -Level Warn
    StopIteration
    Exit 1 
}

if ($PSVersionTable.PSedition -eq "Core") { 
    Write-Log -Message "[ERROR] You cannot use snapins with PowerShell Core. You must use PowerShell 5.x" -Level Warn 
    StopIteration
    Exit 1
}

#region Param Validation
if ($TargetMachineScope -eq "MachineList" -and !($TargetMachineList)) {
    Write-Log -Message "[PARAM ERROR]: You must specify a list of machines using the MachineList Parameter" -Level Warn
    StopIteration
    Exit 0
}
if ($TargetMachineScope -eq "Catalog" -and !($SourceCatalog)) {
    Write-Log -Message "[PARAM ERROR]: You must specify a Source Catalog to use with the Catalog TargetMachineScope Parameter" -Level Warn
    StopIteration
    Exit 0
}
if ($PublishedName -eq "New" -and !($NewPublishedName)) {
    Write-Log -Message "[PARAM ERROR]: You must specify a new Published Name using the NewPublishedName Parameter" -Level Warn
    StopIteration
    Exit 0
}
if ($SetMaintenanceModeInTarget -and $SetMaintenanceModeInSource) {
    Write-Log -Message "[PARAM ERROR]: You cannot specify Maintenance mode for both Source and Target environments using this script" -Level Warn
    StopIteration
    Exit 0
}
if ($SetMaintenanceModeInSource -and $RemoveVMFromSource) {
    Write-Log -Message "[PARAM ERROR]: SetMaintenanceModeInSource and RemoveVMFromSource are mutally exclusive operations. You cannot specify both options" -Level Warn
    StopIteration
    Exit 0
}
if ($RemoveVMFromSource -and !($HideSourceMCSWarning)) {
    WriteWarningAboutMCSRemoval
}

#endregion Param Validation

#region Module Load
#------------------------------------------------------------
# Import Citrix Snapins
#------------------------------------------------------------
try {
    Write-Log -Message "[Citrix PowerShell] Attempting to import Citrix PowerShell Snapins" -Level Info
    Add-PSSnapin -Name Citrix* -ErrorAction Stop
    Get-PSSnapin Citrix* -ErrorAction Stop | out-null
    Write-Log -Message "[Citrix PowerShell] Successfully imported Citrix PowerShell Snapins" -Level Info
}
catch {
    Write-Log -Message "[Citrix PowerShell] Failed to import Citrix PowerShell Snapins" -Level Warn
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}
#endregion Module Load

#region validate Sites
ValidateCitrixController -AdminAddress $SourceController
ValidateCitrixController -AdminAddress $TargetController
#endregion validate Sites

#region prompt for missing inputs
if (!$TargetCatalog) {
    Write-Log -Message "[Script Params] Missing Target Catalog Param input. Listing available options in target site" -Level Info
    $TargetCatalog = (Get-BrokerCatalog -AdminAddress $TargetController -Filter { ProvisioningType -eq "Manual" -and SessionSupport -eq "SingleSession" } | Select-Object Name, AllocationType, PersistUserChanges, ProvisioningType, SessionSupport, ZoneName, HypervisorConnectionUid | Out-GridView -PassThru -Title "Select a Destination Catalog").Name
    if (!$TargetCatalog) { 
        Write-Log -Message "[PARAM ERROR] You must select a Target Catalog to process this script" -Level Warn 
        StopIteration 
        Exit 1 }
}
if (!$TargetDeliveryGroup) {
    Write-Log -Message "[Script Params] Missing Target Delivery Group Param input. Listing available options in target site" -Level Info
    $TargetDeliveryGroup = (Get-BrokerDesktopGroup -AdminAddress $TargetController -Filter { SessionSupport -eq "SingleSession" -and DeliveryType -eq "DesktopsOnly" } | Select-Object Name, DeliveryType, Description, DesktopKind, Enabled, SessionSupport | Out-GridView -PassThru -Title "Select a Desktop Group").Name
    if (!$TargetDeliveryGroup) { 
        Write-Log -Message "[PARAM ERROR] You must select a Target Delivery Group to process this script" -Level Warn
        StopIteration
        Exit 1 
    }
}
if (!$TargetHostingConnection) {
    Write-Log -Message "[Script Params] Missing Target Hosting Connection Param input. Listing available options in target site" -Level Info
    $TargetHostingConnection = (Get-BrokerHypervisorConnection -AdminAddress $TargetController | Select-Object Name, HypHypervisorType, State, IsReady, MachineCount | Out-GridView -PassThru -Title "Select a Hosting Connection").Name
    if (!$TargetHostingConnection) { 
        Write-Log -Message "[PARAM ERROR] You must select a Target Hosting Connection to process this script" -Level Warn
        StopIteration
        Exit 1 
    }
}
#endregion prompt for missing inputs

#region Validate Target Catalog
Write-Log -Message "[Citrix Catalog $($TargetCatalog)] Validating the target Catalog" -Level Info
try {
    $target_catalog_details = Get-BrokerCatalog -Name $TargetCatalog -AdminAddress $TargetController -ErrorAction Stop
    
    if ($target_catalog_details.ProvisioningType -eq "Manual") {
        Write-Log -Message "[Citrix Catalog $($TargetCatalog)] Catalog Provisioning type is: $($target_catalog_details.ProvisioningType) and is supported" -Level Info
    }
    else {
        Write-Log -Message "[Citrix Catalog $($TargetCatalog)] Catalog Provisioning type is: $($target_catalog_details.ProvisioningType) and is not supported" -Level Warn
        StopIteration
        Exit 1
    }
}
catch {
    Write-Log -Message "[Citrix Catalog $($TargetCatalog)] Failed to retreive Catalog" -Level Info
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}
#endregion Validate Target Catalog

#region Validate Target Delivery Group
Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] Validating Delivery Group" -Level Info
try {
    $target_delivery_group_details = Get-BrokerDesktopGroup -Name $TargetDeliveryGroup -AdminAddress $TargetController -ErrorAction Stop
    
    if ($target_delivery_group_details.SessionSupport -eq "SingleSession") {
        Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] is a Single Session Delivery Group and is supported" -Level Info
    }
    else {
        Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] is a $($target_delivery_group_details.SessionSupport) Delivery Group and is not supported" -Level Warn
        StopIteration
        Exit 1
    }

    ## DesktopKind

    if ($target_delivery_group_details.TotalDesktops -eq 0) {
        Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] Has no members and can be used for the migration" -Level Info
    }
    else {
        Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] Has $($target_delivery_group_details.TotalDesktops) members. Identifying if this is a supported Delivery Group based on Provisioning types of members" -Level Info

        $target_delivery_group_catalog_name = (Get-BrokerMachine -DesktopGroupName $TargetDeliveryGroup -AdminAddress $TargetController | Select-Object -First 1).CatalogName
        $target_delivery_group_catalog_type = (Get-BrokerCatalog -Name $target_delivery_group_catalog_name -AdminAddress $TargetController).ProvisioningType

        if ($target_delivery_group_catalog_type -eq "MCS" -or $target_delivery_group_catalog_type -eq "PVS" ) {
            Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] Contains $($target_delivery_group_catalog_type) Provisioned machines and cannot be used" -Level Warn
            StopIteration
            Exit 1
        }
        else {
            Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] Has no provisioned machines and is supported" -Level Info
        }
    }
}
catch {
    Write-Log -Message "[Citrix Delivery Group $($TargetDeliveryGroup)] Failed to retreive Delivery Group" -Level Info
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}
#endregion Validate Target Delivery Group

#region Valiate Target Hosting Connection
Write-Log -Message "[Citrix Hosting] Validating Hosting Connection: $($TargetHostingConnection)" -Level Info
try {
    $target_hosting_connection = Get-BrokerHypervisorConnection -Name $TargetHostingConnection -AdminAddress $TargetController -ErrorAction Stop
    Write-Log -Message "[Citrix Hosting] Hypervisor Plugin type is: $($target_hosting_connection.HypHypervisorType)" -Level Info
}
catch [Citrix.Broker.Admin.SDK.SdkOperationException] {
    Write-Log -Message "[Citrix Hosting] Hosting Connection $($TargetHostingConnection) does not exist at Controller: $($TargetController)" -level Warn
    StopIteration
    Exit 1
}
catch {
    Write-Log -Message "[Citrix Hosting] Failed to retrieve Hosting Connection: $($TargetHostingConnection)" -level Warn
    Write-Log -Message $_ -Level Warn
    StopIteration
    Exit 1
}
#endregion Valiate Target Hosting Connection

#region validate Source Catalog
$catalog_supported_clone_type_check_completed = $false

if ($TargetMachinescope -eq "Catalog") {
    Write-Log -Message "[Citrix Catalog $($SourceCatalog)] Validating the source Catalog selected for input" -Level Info
    try {
        $source_catalog_details = Get-BrokerCatalog -Name $SourceCatalog -AdminAddress $SourceController -ErrorAction Stop
        if ($source_catalog_details.ProvisioningType -eq "Manual" -or $source_catalog_details.ProvisioningType -eq "MCS") {
            Write-Log -Message "[Citrix Catalog $($SourceCatalog)] Catalog Provisioning type is: $($source_catalog_details.ProvisioningType) and is supported" -Level Info
            #Validate Disk Clone Type here so we don't need to loop through each VM
            if ($source_catalog_details.ProvisioningType -eq "MCS") {
                try {
                    $source_catalog_hypervisor_connection_type = (Get-BrokerHypervisorConnection -Uid $source_catalog_details.HypervisorConnectionUid -AdminAddress $SourceController -ErrorAction Stop).HypHypervisorType
                    if (!$source_catalog_hypervisor_connection_type) {
                        Write-Log -Message "[Citrix Catalog $($SourceCatalog)] Unable to determine hypervisor type. Will not continue." -Level Warn
                        StopIteration
                        Exit 1
                    }

                    if ($source_catalog_hypervisor_connection_type -in $full_clone_check_list) {
                        Write-Log -Message "[Citrix Catalog $($SourceCatalog)] Hypervisor is $($source_catalog_hypervisor_connection_type) so validating MCS Disk Clone type" -Level Info

                        $prov_scheme_provision_clone_type = (Get-ProvScheme -ProvisioningSchemeUid $source_catalog_details.ProvisioningSchemeId -AdminAddress $SourceController -ErrorAction Stop).UseFullDiskCloneProvisioning

                        if ($prov_scheme_provision_clone_type -eq "True") {
                            Write-Log -Message "[Citrix Catalog $($SourceCatalog)] The Catalog is using Full Clone provisioning. This catalog contains machines that are supported for migration" -Level Info
                            $catalog_supported_clone_type_check_completed = $true
                        }
                        else {
                            Write-Log -Message "[Citrix Catalog $($SourceCatalog)] The Catalog is using Fast (Thin) Clone provisioning. This catalog contains machines that cannot be migrated" -Level Warn
                            StopIteration
                            Exit 1
                        }
                    }
                }
                catch {
                    Write-Log -Message "[Citrix Catalog $($SourceCatalog)] Unable to Validate Catalog Provisioning Clone Type" -Level Warn
                    Write-Log -Message $_ -Level Warn
                    StopIteration
                    Exit 1
                }
                
            }
        }
        else {
            Write-Log -Message "[Citrix Catalog $($TargetCatalog)] Catalog Provisioning type is: $($target_catalog_details.ProvisioningType) and is not supported" -Level Info
            StopIteration
            Exit 1
        }
    }
    catch {
        Write-Log -Message "[Citrix Catalog $($SourceCatalog)] Failed to retreive Catalog" -Level Info
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }
}
#endregion validate Source Catalog

#region Validate Hosting Between Source and Target
if ($TargetMachinescope -eq "Catalog") {
    if ($source_catalog_hypervisor_connection_type -ne $target_hosting_connection.HypHypervisorType) {
        Write-Log -Message "[Hosting Validation Error] Source Hosting Connection is: $($source_catalog_hypervisor_connection_type) but Target Hosting Connection is: $($target_hosting_connection.HypHypervisorType). You cannot move a VM between different hosting connection types with this script" -Level Warn
        StopIteration
        Exit 1
    }
}
#endregion Validate Hosting Between Source and Target

#region Machine Scoping
if ($TargetMachineScope -eq "MachineList") {
    $target_vms = $TargetMachineList
}
if ($TargetMachinescope -eq "Catalog") {
    try {
        Write-Log -Message "[VM Retrieval] Getting a list of machines from Catalog $($source_catalog_details.Name)" -Level Info
        $target_vms = (Get-BrokerMachine -CatalogName $source_catalog_details.Name -AdminAddress $SourceController -MaxRecordCount $MaxRecordCount -ErrorAction Stop).HostedMachineName 
    }
    catch {
        Write-Log -Message "[VM Retrieval] Failed to get a list of machines from Catalog $($source_catalog_details.Name)" -Level Warn
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }

    if ($null -eq $target_vms) {
        Write-Log -Message "[VM Retrieval] There were no machines returned from Catalog: $($source_catalog_details.Name)" -Level Info
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }
}

#endregion Machine Scoping

# Start Iteration Counts
$total_count = $target_vms.Count
$current_count = 1
$failed_vm_count = 0
$successful_vm_count = 0
$excluded_count = 0

#region Process VMS
foreach ($vm in $target_vms) {
    Write-Log -Message "[VM] Processing VM $($current_count) of $($total_count)" -Level Info
    if ($vm -in $ExclusionList) {
        Write-Log -Message "[VM $($vm)] is in the exclusion list and won't be processed" -Level Warn
        $excluded_count ++
        Continue
    }
    try {
        #region Validate Source machine
        $source_vm_details = Get-BrokerMachine -HostedMachineName $vm -AdminAddress $SourceController -MaxRecordCount $MaxRecordCount -ErrorAction Stop

        if ($source_vm_details.ProvisioningType -eq "PVS") {
            Write-Log -Message "[VM $($vm)] is a PVS provisioned machine so VM will not be included" -Level Warn
            $failed_vm_count ++
            Continue
        }
        elseif ($source_vm_details.ProvisioningType -eq "MCS") {
            if ($IncludeMCSMachinesFromSource) {
                Write-Log -Message "[VM $($vm)] is an MCS provisioned machine. Include MCS Machines from Source has been enabled so VM will be included" -Level Info
                
                if ($catalog_supported_clone_type_check_completed -eq $false) {
                    # We aren't using a Catalog as machine source, thus we haven't yet checked the clone type capability. Validate the machine is of a full clone type
                    try {
                        $vm_hypervisor_connection_type = (Get-BrokerHypervisorConnection -Uid $source_vm_details.HypervisorConnectionUid -AdminAddress $SourceController -ErrorAction Stop).HypHypervisorType
                        if (!$vm_hypervisor_connection_type) {
                            Write-Log -Message "[VM $($vm)] Unable to determine hypervisor type. VM will not be included" -Level Warn
                            $failed_vm_count ++
                            Continue
                        }
                        if ($vm_hypervisor_connection_type -ne $target_hosting_connection.HypHypervisorType) {
                            Write-Log -Message "[VM $($vm)] Hosting Validation Error. Source Hosting Connection is: $($vm_hypervisor_connection_type) but Target Hosting Connection is: $($target_hosting_connection.HypHypervisorType). You cannot move a VM between different hosting connection types with this script" -Level Warn
                            $failed_vm_count ++
                            Continue
                        }
                        else {
                            Write-Log -Message "[VM $($vm)] Hosting connection types match. Source Hosting Connection is: $($vm_hypervisor_connection_type) and Target Hosting Connection is: $($target_hosting_connection_detail.HypHypervisorType)." -Level Info
                        }
                        if ($vm_hypervisor_connection_type -in $full_clone_check_list) {
                            Write-Log -Message "[VM $($vm)] Hypervisor is $($vm_hypervisor_connection_type) so validating MCS Disk Clone type" -Level Info
                            # grab the ProvScheme from the catalog the vm lives in
                            $vm_prov_scheme_association_id = (Get-BrokerCatalog -Uid $source_vm_details.CatalogUid -AdminAddress $SourceController -ErrorAction Stop).ProvisioningSchemeId
                            # Grab the Disk Provisioning Type - Boolean Value
                            $vm_prov_scheme_provision_clone_type = (Get-ProvScheme -ProvisioningSchemeUid $vm_prov_scheme_association_id -AdminAddress $SourceController -ErrorAction Stop).UseFullDiskCloneProvisioning
                            if ($vm_prov_scheme_provision_clone_type -eq "True") {
                                Write-Log -Message "[VM $($vm)] is an MCS provisioned machine. The Catalog is using Full Clone provisioning. This machine is supported for migration" -Level Info
                            }
                            else {
                                Write-Log -Message "[VM $($vm)] is an MCS provisioned machine. The Catalog is using Fast (Thin) Clone provisioning. This machine cannot be migrated." -Level Warn
                                $failed_vm_count ++
                                Continue
                            }
                        }
                    }
                    catch {
                        Write-Log -Message "[VM $($vm)] Unable to validate MCS Disk Clone type so VM will not be included" -Level Warn
                        Write-Log -Message $_ -Level Warn
                        $failed_vm_count ++
                        Continue
                    }
                }
            }
            else {
                Write-Log -Message "[VM $($vm)] is an MCS provisioned machine. Include MCS Machines from Source has not been enabled so VM will not be included" -Level Warn
                $failed_vm_count ++
                Continue
            }
        }
        #endregion Validate Source machine

        #region Validate machine in target site
        try {
            $machine_exists_in_target = Get-BrokerMachine -MachineName $source_vm_details.MachineName -AdminAddress $TargetController -ErrorAction Stop
            Write-Log "[VM $($vm)] Already exists in the target site" -Level Warn
            $failed_vm_count ++
            Continue
        }
        catch {
            Write-Log -Message "[VM $($vm)] VM does not exist in Target Site" -Level Info
        }
        #endregion Validate machine in target site

        #region Add Machine to Catalog
        if (!$Whatif) {
            #We are processing
            try {
                $target_machine = New-BrokerMachine -CatalogUid $target_catalog_details.Uid -HostedMachineId $source_vm_details.HostedMachineId -HypervisorConnectionUid $target_hosting_connection.Uid -MachineName $source_vm_details.MachineName -AdminAddress $TargetController -ErrorAction Stop
                Write-Log -Message "[VM $($vm)] Added to target site" -Level Info
            }
            catch {
                $failed_vm_count ++
                Continue
            }
        }
        else {
            # We are in whatif mode
            Write-Log -Message "[WHATIF] [VM $($vm)] Would add to Target Site at Controller $($TargetController)" -Level Info
            Write-Log -Message "[WHATIF] [VM $($vm)] Target Catalog UID: $($target_catalog_details.Uid)" -Level Info
            Write-Log -Message "[WHATIF] [VM $($vm)] Hosted Machine id $($source_vm_details.HostedMachineId)" -Level Info
            Write-Log -Message "[WHATIF] [VM $($vm)] Hypervisor Conection name: $($target_hosting_connection.Name)" -Level Info
            Write-Log -Message "[WHATIF] [VM $($vm)] Hypervisor Connection Uid: $($target_hosting_connection.Uid)" -Level Info
        }
        #endregion Add Machine to Catalog

        #region Set Machine Maintenance Mode
        if ($SetMaintenanceModeInTarget) {
            if (!$Whatif) {
                try {
                    Write-Log -Message "[VM $($vm)] Setting maintenance mode On in the target site" -Level Info
                    Set-BrokerMachine -MachineName $target_machine.MachineName -InMaintenanceMode $true -AdminAddress $TargetController -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "[VM $($vm)] Failed to set maintenance mode On in the target site" -Level Warn
                    $failed_vm_count ++
                    Continue
                }
            }
            else {
                # We are in whatif mode
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have set maintenance mode On in the target site" -Level Info
            }
            
        }
        if ($SetMaintenanceModeInSource) {
            if (!$WhatIf) {
                try {
                    Write-Log -Message "[VM $($vm)] Setting maintenance mode On in the source site" -Level Info
                    Set-BrokerMachine -HostedMachineName $vm -InMaintenanceMode $true -AdminAddress $SourceController
                }
                catch {
                    Write-Log -Message "[VM $($vm)] Failed to set maintenance mode On in the source site" -Level Warn
                    $failed_vm_count ++
                    Continue
                }
            }
            else {
                # We are in whatif mode
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have set maintenance mode On in the source site" -Level Info
            }
            
        }
        #endregion Set Machine Maintenance Mode
        
        #region Add to Delivery Group
        if (!$Whatif) {
            #We are processing
            try {
                Write-Log -Message "[VM $($vm)] Adding VM to delivery group $($target_delivery_group_details.Name)" -Level Info
                Add-BrokerMachine -DesktopGroup $target_delivery_group_details.Name -MachineName $target_machine.MachineName -AdminAddress $TargetController -ErrorAction Stop
            }
            catch {
                Write-Log -Message "[VM $($vm)] Failed to add VM to delivery group $($target_delivery_group_details.Name)" -Level Warn
                $failed_vm_count ++
                Continue
            }
        }
        else {
            #we are in Whatif Mode
            Write-Log -Message "[WHATIF] [VM $($vm)] Would have added VM to delivery group $($target_delivery_group_details.Name)" -Level Info
        }

        #endregion Add to Delivery Group

        #region Set PublishedName
        if ($PublishedName -eq "New") {
            Write-Log -Message "[VM $($vm)] Machine Published name will be: $($NewPublishedName)" -Level Info
            $machine_published_name = $NewPublishedName
        }
        elseif ($PublishedName -eq "MatchSourceDG") {
            try {
                $machine_published_name = (Get-BrokerDesktopGroup -Name $source_vm_details.DesktopGroupName -AdminAddress $SourceController -ErrorAction Stop).PublishedName
                Write-Log -Message "[VM $($vm)] Machine Published name will be: $($machine_published_name)" -Level Info
            }
            catch {
                Write-Log -Message "[VM $($vm)] Failed to get Delivery Group details for published name. Leaving blank" -Level Info
                Write-Log -Message $_ -Level Warn
                $machine_published_name = $null
                $failed_vm_count ++
            }
        }
        else {
            $machine_published_name = $source_vm_details.PublishedName
            if ($null -eq $machine_published_name) {
                Write-Log -Message "[VM $($vm)] Machine Published name will be blank" -Level Info
            }
            else {
                Write-Log -Message "[VM $($vm)] Machine Published name will be: $($source_vm_details.PublishedName)" -Level Info
            }
        }

        if (!$Whatif) {
            #We are processing
            if ($null -eq $machine_published_name) {
                #Nothing to do
            }
            else {
                try {
                    Write-Log -Message "[VM $($vm)] Setting Machine Published Name" -Level Info
                    Set-BrokerMachine -MachineName $target_machine.MachineName -PublishedName $machine_published_name -AdminAddress $TargetController -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "[VM $($vm)] Failed to set Machine Published Name" -Level Warn
                    $failed_vm_count ++
                } 
            }
        }
        else {
            #we are in Whatif Mode
            if ($null -eq $machine_published_name) {
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have retained a blank published name which will inherit the Delivery Group value in the target site" -Level Info
            }
            else {
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have set published name to: $($machine_published_name) in the target site" -Level Info
            }
            
        }
        #endregion Set PublishedName

        #region Handle Assignments
        $AssignedUsers = -split $source_vm_details.AssociatedUserNames

        if ($AssignedUsers) {
            if (!$Whatif) {
                # We are processing
                foreach ($User in $AssignedUsers) {
                    try {
                        Write-Log -Message "[VM $($vm)] Assigning: $($User)" -Level Info
                        Add-BrokerUser $User -PrivateDesktop $source_vm_details.MachineName -AdminAddress $TargetController -ErrorAction Stop
                    }
                    catch {
                        Write-Log -Message "[VM $($vm)] Failed to assign: $($User)" -Level Warn
                        $failed_vm_count ++
                    }
                }
            }
            else {
                #We are in Whatif mode
                foreach ($User in $AssignedUsers) {
                    Write-Log -Message "[WHATIF] [VM $($vm)] Would have assigned: $($User)" -Level Info
                }
                
            }
        }
        else {
            #No user assignments
            Write-Log -Message "[VM $($vm)] There are no assignments to process" -Level Info
        }
        #endregion Handle Assignments

        #region Handle VM removal from Source
        if ($RemoveVMFromSource) {
            Write-Log -Message "VM Removal from source has been enabled. Processing source VM removal" -Level Info
            if (!$WhatIf) {
                #We are processing

                # Set Maintenance Mode
                try {
                    Write-Log -Message "[VM $($vm)] Setting Maintenance Mode" -Level Info
                    Set-BrokerMachine -MachineName $source_vm_details.MachineName -InMaintenanceMode $true -AdminAddress $SourceController -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "[VM $($vm)] Failed to set Maintenance Mode" -Level Warn
                    $failed_vm_count ++
                    Continue
                }

                # Remove from DG
                try {
                    Write-Log -Message "[VM $($vm)] Removing from Delivery Group" -Level Info
                    Remove-BrokerMachine -MachineName $source_vm_details.MachineName -DesktopGroup $source_vm_details.DesktopGroupName -force -AdminAddress $SourceController -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "[VM $($vm)] Failed to remove from Delivery Group" -Level Warn
                    $failed_vm_count ++
                    Continue
                }

                # IF MCS Kill ProvVM etc
                if ($source_vm_details.ProvisioningType -eq "MCS") {
                    Write-Log -Message "[VM $($vm)] Machine is an MCS provisioned machine. Retrieving ProvVM" -Level Info
                    try {
                        $ProvVM = (Get-ProvVM -VMName ($source_vm_details.MachineName | Split-Path -Leaf) -AdminAddress $SourceController -ErrorAction Stop)
                    }
                    catch {
                        Write-Log -Message "[VM $($vm)] Failed to retrieve ProvVM" -Level Warn
                        $failed_vm_count ++
                        Continue
                    }

                    #unlock ProvVM
                    try {
                        Write-Log -Message "[VM $($vm)] Unlocking ProvVM" -Level Info
                        Unlock-ProvVM -VMID $ProvVM.VMId -ProvisioningSchemeName $source_vm_details.CatalogName -AdminAddress $SourceController -ErrorAction Stop
                    }
                    catch {
                        Write-Log -Message "[VM $($vm)] Failed to Unlock ProvVM" -Level Warn
                        $failed_vm_count ++
                        Continue
                    }

                    # remove ProvVM
                    try {
                        Write-Log -Message "[VM $($vm)] Removing ProvVM" -Level Info
                        $null = Remove-ProvVM -VMName $ProvVM.VMName -ProvisioningSchemeName $source_vm_details.CatalogName -ForgetVM -AdminAddress $SourceController -ErrorAction Stop
                    }
                    catch {
                        Write-Log -Message "[VM $($vm)] Failed to Remove ProvVM" -Level Warn
                        $failed_vm_count ++
                        Continue
                    }

                    # Remove AcctAD Account from Catalog
                    try {
                        Write-Log -Message "[VM $($vm)] Removing Acct AD Account and keeping the Active Directory Account" -Level Info
                        $null = Remove-AcctADAccount -IdentityPoolName $source_vm_details.CatalogName -ADAccountSid $ProvVM.ADAccountSid -RemovalOption None -AdminAddress $SourceController -ErrorAction Stop
                    }
                    catch {
                        Write-Log -Message "[VM $($vm)] Failed to remove Acct AD Account" -Level Warn
                        $failed_vm_count ++
                        Continue
                    }
                }

                # remove machine from Catalog
                try {
                    Write-Log -Message "[VM $($vm)] Removing Machine from Catalog" -Level Info
                    Remove-BrokerMachine -MachineName $source_vm_details.MachineName -AdminAddress $SourceController -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "[VM $($vm)] Failed to remove from Catalog" -Level Warn
                    $failed_vm_count ++
                    Continue
                }
            }
            else {
                #We are in whatif mode
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have been removed from the source site" -Level Info
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have set Maintenance Mode" -Level Info
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have removed from the Delivery Group: $($source_vm_details.DesktopGroupName)" -Level Info
                if ($source_vm_details.ProvisioningType -eq "MCS") {
                    Write-Log -Message "[WHATIF] [VM $($vm)] Machine is an MCS provisioned machine. Retrieving ProvVM" -Level Info
                    try {
                        $ProvVM = (Get-ProvVM -VMName ($source_vm_details.MachineName | Split-Path -Leaf) -AdminAddress $SourceController -ErrorAction Stop)
                    }
                    catch {
                        Write-Log -Message "[WHATIF] [VM $($vm)] Failed to retrieve ProvVM $($ProvVM.VMId)" -Level Warn
                        Continue
                    }
                    Write-Log -Message "[WHATIF] [VM $($vm)] Would have unlocked ProvVM $($ProvVM.VMId)" -Level Info
                    Write-Log -Message "[WHATIF] [VM $($vm)] Would have removed ProvVM $($ProvVM.VMName)" -Level Info
                    Write-Log -Message "[WHATIF] [VM $($vm)] Would have removed AcctAD Account with SID: $($ProvVM.ADAccountSid) but not removed the Active Directory Account" -Level Info
                }
                Write-Log -Message "[WHATIF] [VM $($vm)] Would have removed the VM from the Catalog $($source_vm_details.CatalogName)" -Level Info
            }
        }
        #endregion Handle VM removal from Source

        $successful_vm_count ++

    }
    catch [System.Management.Automation.RuntimeException] {
        Write-Log -Message "[VM: $($vm)] Does not exist at Controller $($SourceController)" -Level Warn
        $failed_vm_count ++
    }
    catch {
        Write-Log -Message "[VM: $($vm)] Failed to get machine at Controller $($SourceController)" -Level Warn
        $failed_vm_count ++
    }
    $current_count ++
}
#endregion Process VMS

#region Reset Target Hosting Connection
if ($ResetTargetHostingConnection) {
    if ($successful_vm_count -gt 0) {
        if (!$Whatif) {
            #we are executing
            Write-Log -Message "[Citrix Hosting] Resetting Citrix Hosting Connection: $($TargetHostingConnection)" -Level Info
            try {
                $update_hosting_connection = Update-HypHypervisorConnection "xdhyp:\Connections\$($TargetHostingConnection)" -AdminAddress $TargetController -ErrorAction Stop
            }
            catch {
                Write-Log -Message "[Citrix Hosting] Failed to reset Hosting Connection: $($TargetHostingConnection)" -Level Warn
                Write-Log -Message $_ -Level Warn
            }
        }
        else {
            #we are in whatif mode
            Write-Log -Message "[WHATIF] [Citrix Hosting] Would have reset Hosting Connection $($TargetHostingConnection)" -Level Info
        }
    }
}
else {
    Write-Log -Message "[Citrix Hosting] No machines were altered so Hosting Connection has not been reset" -Level Info
}
#endregion Reset Target Hosting Connection

Write-Log -Message "[Processing Statistics] Processed a total of $($total_count) machines" -Level Info
Write-Log -Message "[Processing Statistics] Excluded a total of $($excluded_count) machines" -Level Info
Write-Log -Message "[Processing Statistics] Successfully processed a total of $($successful_vm_count) machines" -Level Info
Write-Log -Message "[Processing Statistics] Failed to process a total of $($failed_vm_count) machines. Please check log file" -Level Info

StopIteration
Exit 0
#endregion