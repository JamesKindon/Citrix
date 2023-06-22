<#
.SYNOPSIS
    Migrates Dedicated MCS provisioned machines to a manual provisioned catalog and delivery gruop
.DESCRIPTION
    Loops through source catalog, removes the VM from existing delivery group, moves to a new catalog, handles provisioning relics, adds to new delivery group with user assignments retained
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER JSON
    Will consume a JSON import for configuration
.PARAMETER JSONInputPath
    Specifies the JSON input file
.PARAMETER SourceCatalog
    Specifies the source catalog for MCS machines
.PARAMETER TargetCatalog
    Specifies the target catalog for machines migrated from MCS
.PARAMETER SourceDeliveryGroup
    Specifies the source Delivery Group to mirror Published Name, Access Policy Rules and Functional Levels from. Used in conjunction with AlignTargetDeliveryGroupToSource Parameter
.PARAMETER TargetDeliveryGroup
    Specifies the target Delivery Group for migrated machines
.PARAMETER AlignTargetDeliveryGroupToSource
    Switch to enable mirroring of settings from Source Delivery Group. Used in conjunction with SourceDeliveryGroup Parameter
.PARAMETER OverridePublishedName
    Value to override the published desktop name with a new value else will consume existing published name
.PARAMETER SetPublishedNameToMachineName
    Switch to force set the published name to the VM name
.PARAMETER Controller
    Value for the Delivery Controller to Target, Eg, DDC1
.PARAMETER TargetMachineScope
    Specifies how machines are handled, either All, MachineList or CSV. Defaults to All.
        'All': All machines in source catalog will be targeted
        'MachineList': An array of defined machines to target
        'CSV': a CSV input of machines to target. Used in conjunction with TargetMachineCSVList Param
.PARAMETER TargetMachineList
    An array of machines to target "VM01","VM02
.PARAMETER TargetMachineCSVList
    Target CSV File for machine targets. Used in conjunction with the TargetMachineScope Param when using the CSV value. CSV must use the HostedMachineName Header. Suggest exporting via Get-BrokerMachine
    For Exameple: Get-BrokerMachine -CatalogName "W10 MCS Migration Test" | Export-CSV -NoTypeInformation c:\temp\VMList.csv
.PARAMETER MaxRecordCount
    Overrides the query max for VM lookups - defaults to 10000
.EXAMPLE
    .\MigrateMCSToManual -SourceCatalog "W10 MCS Migration Test" -TargetCatalog "W10 MCS Migrated Test" -TargetDeliveryGroup "W10 MCS Migrated Test" -SetPublishedNameToMachineName -Controller DDC1
    Migrates vm's from source catalog, moves to target catalog and target delivery group and sets the published name to the VM name using the Controller DDC1. If no Catalog or Delivery group matching the specified values are found, they will be created.
.EXAMPLE
    .\MigrateMCSToManual -JSON -JSONInputPath 'C:\Temp\MigrationConfiguration.json' -AlignTargetDeliveryGroupToSource
    Migrates vm's based on JSON input. If no Catalog or Delivery group matching the specified values are found, they will be created. The Target Delivery Group will be created based on the specified Source Delivery Group if found, else defaults will apply.
.EXAMPLE
    .\MigrateMCSToManual -SourceCatalog "W10 MCS Migration Test" -TargetCatalog "W10 MCS Migrated Test" -SourceDeliveryGroup "W10 MCS Migration Test" -TargetDeliveryGroup "W10 MCS Migrated Test" -OverridePublishedName "MyVM" -Controller DDC1 -AlignTargetDeliveryGroupToSource
    Migrates vm's from source catalog, moves to target catalog and target delivery group and sets the published name to MyVM using the Controller DDC1. If no Catalog or Delivery group matching the specified values are found, they will be created. The Target Delivery Group will be created based on the specified Source Delivery Group if found, else defaults will apply.
.EXAMPLE
    .\TestVMMig.ps1 -SourceCatalog "W10 MCS Migration Test" -TargetCatalog "W10 MCS Migrated Test" -SourceDeliveryGroup "W10 MCS Migration Test" -TargetDeliveryGroup "W10 MCS Migrated Test" -Controller DDC1 -TargetMachineScope MachineList -TargetMachineList "VM01" -AlignTargetDeliveryGroupToSource
.NOTES
    Script has been designed to work with both Citrix Cloud and On-Prem deployments
.NOTES
    ChangeLog:
        [17.04.23, James Kindon] Add Controller Parameter (localhost by default)
        [17.04.23, James Kindon] Add TargetMachineScope, TargetMachines and TargetMachineCSVList Parameters and altered filtering logic for Get VM's
        [17.04.23, James Kindon] Add CreateManualCatalog Function and alter validation logic - create on failure to locate
        [17.04.23, James Kindon] Add CreateTargetDeliveryGroup Function and alter validation logic - create on failure to locate
        [17.04.23, James Kindon] Add MaxRecordCount Paramter with default of 10000 objects
        [17.04.23, James Kindon] Fix DisplayName handling of $null values
        [18.04.23, James Kindon] Add SourceDeliveryGroup Parameter and AlignTargetDeliveryGroupToSource Parameter. Alter Delivery Group creation function to create with source DG settings if specified
        [18.04.23, James Kindon] Moved OverridePublishedName to string from switch. Removed PublishedName Param
        [18.04.23, James Kindon] Altered JSON inputs to capture SourceDeliveryGroup, Controller, OverridePublishedName, TargetMachineScope, TargetMachineList, TargetMachineCSVList
        [18.04.23, James Kindon] Updated Parameter Sets and added code logic to deal with awkward param combinations failing on sets (region Error Handling)
        [22.06.23, James Kindon] Added success logging output and ErrorAction Stop to remove loop
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\MCSMigration.log", # Where we log to

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$Controller = "localhost", # AdminAddress for the Controller

    [Parameter(Mandatory = $false, ParameterSetName = 'JSON')]
    [Switch]$JSON, # We are going to use JSON input

    [Parameter(Mandatory = $true, ParameterSetName = 'JSON')]
    [String]$JSONInputPath, # And here is the JSON file

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [ValidateSet('All', 'MachineList', 'CSV')]
    [String]$TargetMachineScope = "All", # Target Machine Scopes for Migration

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [Array]$TargetMachineList, # Array of machines to target

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$TargetMachineCSVList, # Target CSV File for TargetMachineScope

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$SourceCatalog, # Where the machines are coming from (and MCS catalog)

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$TargetCatalog, # Where the machines are going to - either existing or new manual power managed catalog

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$SourceDeliveryGroup, # Specify Source Delivery Group to reference

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$TargetDeliveryGroup, # Where the machines are going to - either existing or new

    [Parameter(Mandatory = $false)]
    [Switch]$AlignTargetDeliveryGroupToSource, # Build Target Delivery Group with Attributes from Source Delivery Group

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [Parameter(ParameterSetName = 'JSON')]
    [Switch]$SetPublishedNameToMachineName, # sets the published name on the VM to the machine name

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$OverridePublishedName, # Overrides the Published Name on the VM to the specified value

    [Parameter(Mandatory = $false)]
    [int]$MaxRecordCount = 10000 # Max Record Count Override

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
    if ($null -eq (Get-BrokerMachine -MachineName $VM.MachineName -AdminAddress $Controller -ErrorAction SilentlyContinue)) {
        Write-Log -Message "$($VM.MachineName): Adding to Catalog $($NewCatalog.Name)" -Level Info
        try {
            $null = New-BrokerMachine -CatalogUid $NewCatalog.Uid -HostedMachineId $VM.HostedMachineId -HypervisorConnectionUid $VM.HypervisorConnectionUid -MachineName $VM.SID -AdminAddress $Controller -Verbose -ErrorAction Stop
            Write-Log -Message "$($VM.MachineName): Successfully added to Catalog $($NewCatalog.Name)" -Level Info
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    else {
        $ExistingCatalog = (Get-BrokerMachine -MachineName $VM.MachineName -AdminAddress $Controller ).CatalogName
        Write-Log -Message "$($VM.MachineName): Already exists in catalog $($ExistingCatalog)" -Level Warn
    }
}

function AddVMtoDeliveryGroup {
    $DG = (Get-BrokerMachine -MachineName $VM.MachineName -AdminAddress $Controller).DesktopGroupName
    if ($null -eq $DG) {
        Write-Log -Message "$($VM.MachineName): Adding to Delivery Group $($TargetDeliveryGroup)" -Level Info
        try {
            Add-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $TargetDeliveryGroup -AdminAddress $Controller -Verbose -ErrorAction Stop
            Write-Log -Message "$($VM.MachineName): Sucessfully added to Delivery Group $($TargetDeliveryGroup)" -Level Info
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    else {
        Write-Log -Message "$($VM.MachineName): Already a member of: $DG" -Level Warn
    } 
}

function AddUsertoVM {
    Write-Log -Message "$($VM.MachineName): Processing User Assignments" -Level Info
    $AssignedUsers = $VM.AssociatedUserNames
    if ($AssignedUsers) {
        foreach ($User in $AssignedUsers) {
            Write-Log -Message "$($VM.MachineName): Adding $($User)" -Level Info
            try {
                Add-BrokerUser $User -PrivateDesktop $VM.MachineName -AdminAddress $Controller -Verbose -ErrorAction Stop
                Write-Log -Message "$($VM.MachineName): Successfully processed User Assignment for $($User)" -Level Info
            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }
    }
    else {
        Write-Log -Message "$($VM.MachineName): There are no user assignments defined" -Level Warn
    }
}

function SetVMDisplayName {
    if ($null -ne $PublishedName) {
        Write-Log -Message "$($VM.MachineName): Setting Published Name to: $PublishedName" -Level Info
        try {
            Set-BrokerMachine -MachineName $VM.MachineName -PublishedName $PublishedName -AdminAddress $Controller -Verbose -ErrorAction Stop
            Write-Log -Message "$($VM.MachineName): Successfully set Published Name to: $PublishedName" -Level Info
        }
        catch {
            Write-Log -Message $_ -level Warn
        }
    }
    else {
        Write-Log -Message "$($VM.MachineName): No Published name specified so ignoring" -Level Info
    }
}

function LoadCitrixSnapins {
    try {
        Write-Log -Message "Loading Citrix Snapins" -Level Info
        Add-PSSnapin citrix*
    }
    catch {
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }
}

function TryForAuthentication {
    try {
        Write-Log -Message "Confirming Authentication" -Level Info
        $null = Get-BrokerSite -AdminAddress $Controller -ErrorAction Stop # This should trigger an auth call if session has timed out (else Get-XDAuthentication)
    }
    catch [Citrix.Broker.Admin.SDK.SdkOperationException] {
        try {
            Get-XDAuthentication
        }
        catch {
            Write-Log -Message $_ -Level Warn
            StopIteration
            Exit 1    
        }
    }
    catch {
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }
}

function CheckCatalogIsMCS {
    if ($Catalog.ProvisioningType -eq "MCS" -and $Catalog.PersistUserChanges -eq "OnLocal") {
        Write-Log "Source Catalog: $($Catalog.Name) is an MCS catalog. Proceeding" -Level Info
    }
    elseif ($Catalog.ProvisioningType -eq "MCS" -and $Catalog.PersistUserChanges -eq "Discard") {
        Write-Log "Source Catalog: $($Catalog.Name) is a non persistent MCS catalog. Exiting Script" -Level Warn
        StopIteration
        Exit 1
    }
    elseif ($Catalog.ProvisioningType -ne "MCS") {
        Write-Log "Source Catalog: $($Catalog.Name) is not an MCS catalog. Exiting Script" -Level Warn
        StopIteration
        Exit 1
    }
}

function CheckCatalogisManual {
    if ($NewCatalog.ProvisioningType -eq "Manual") {
        Write-Log -Message "Target Catalog: $($NewCatalog.Name) is a Manual Catalog. Proceeding" -Level Info
    }    
    else {
        Write-Log -Message "Target Catalog: $($NewCatalog.Name) is provisioned catalog and cannot be used in a supported fashion. Exiting Script" -Level Warn
        StopIteration
        Exit 1
    }
}

function CreateManualCatalog {
    try {
        $SourceCat = Get-BrokerCatalog -name $SourceCatalog -AdminAddress $Controller
        New-BrokerCatalog -AllocationType Static -CatalogKind PowerManaged -Name $TargetCatalog -MinimumFunctionalLevel $SourceCat.MinimumFunctionalLevel -ZoneUid $SourceCat.ZoneUid -AdminAddress $Controller -ErrorAction Stop
    }
    catch {
        StopIteration
        Exit 1
    }
}

function CreateTargetDeliveryGroup {
    try {
        if ($AlignTargetDeliveryGroupToSource.IsPresent -and $SourceDeliveryGroup -ne "") {
            # Build Delivery Group Configuration based on Source Delivery Group
            Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Align Target Delivery Group To Source specified. Referencing Source DG: $($SourceDeliveryGroup)" -Level Info
            try {
                $SourceDG = Get-BrokerDesktopGroup -name $SourceDeliveryGroup -AdminAddress $Controller -ErrorAction Stop
                $NewDG = New-BrokerDesktopGroup -Name $TargetDeliveryGroup -DesktopKind Private -MinimumFunctionalLevel $SourceDG.MinimumFunctionalLevel -AdminAddress $Controller -ErrorAction Stop
                # Published Name
                Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Setting Published Name. Referencing Source Delivery Group: $($SourceDeliveryGroup)" -Level Info
                Set-BrokerDesktopGroup -Name $NewDG.Name -PublishedName $SourceDG.PublishedName -AdminAddress $Controller -ErrorAction Stop
                # Access Policy Rules
                Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Creating Default Access Policy Rules. Referencing Source Delivery Group: $($SourceDeliveryGroup)" -Level Info
                $BrokerAccessPolicyRules = Get-BrokerAccessPolicyRule -DesktopGroupUid $SourceDG.Uid -AdminAddress $Controller -ErrorAction Stop
                # Access Policy Rule Assignments
                $SourceRuleAG = $BrokerAccessPolicyRules | Where-Object {$_.AllowedConnections -eq "ViaAG" -and $_.Name -like "$SourceDeliveryGroup*"}
                $NewRuleAG = New-BrokerAccessPolicyRule -Name $($TargetDeliveryGroup+"_AG") -Enabled $true -AllowedProtocols @("HDX","RDP") -AllowedUsers $SourceRuleAG.AllowedUsers -AllowRestart $true -AllowedConnections ViaAG -IncludedSmartAccessFilterEnabled $true -IncludedUserFilterEnabled $true -DesktopGroupUid $NewDG.Uid -AdminAddress $Controller
                $SourceRuleAGIncludedUsers = $SourceRuleAG.IncludedUsers
                foreach ($Inclusion in $SourceRuleAGIncludedUsers) {
                    Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Adding $($Inclusion.Name) to Access Policy Rule: $($NewRuleAG.Name) " -Level Info
                    Set-BrokerAccessPolicyRule -Name $NewRuleAG.Name -AddIncludedUsers $Inclusion.Name -AdminAddress $Controller
                }
                
                $SourceRuleDirect = $BrokerAccessPolicyRules | Where-Object {$_.AllowedConnections -eq "NotViaAG" -and $_.Name -like "$SourceDeliveryGroup*"}
                $NewRuleDirect = New-BrokerAccessPolicyRule -Name $($TargetDeliveryGroup+"_Direct") -Enabled $true -AllowedProtocols @("HDX","RDP") -AllowedUsers $SourceRuleDirect.AllowedUsers -AllowRestart $true -AllowedConnections NotViaAG -IncludedSmartAccessFilterEnabled $true -IncludedUserFilterEnabled $true -DesktopGroupUid $NewDG.Uid -AdminAddress $Controller
                $SourceRuleDirectIncludedUsers = $SourceRuleDirect.IncludedUsers
                foreach ($Inclusion in $SourceRuleDirectIncludedUsers) {
                    Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Adding $($Inclusion.Name) to Access Policy Rule: $($NewRuleDirect.Name) " -Level Info
                    Set-BrokerAccessPolicyRule -Name $NewRuleDirect.Name -AddIncludedUsers $Inclusion.Name -AdminAddress $Controller
                }
                Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup) Published Name, Default Access Policy Rules and User Filters have been mirrored from Source Delivery Group: $($SourceDeliveryGroup). Additional more advanced configuration may be required depending on the environment " -Level Warn
            }
            catch {
                Write-Log -Message $_ -level Warn
                StopIteration
                Exit 1 
            }
        }
        else {
            Write-Log -Message "Either the Parameter: AlignTargetDeliveryGroupToSource is not specified or the Parameter: SourceDeliveryGroup value is blank. Creating Default Delivery Group configuration" -level Info
            $SourceCatFunc = (Get-BrokerCatalog -name $SourceCatalog -AdminAddress $Controller).MinimumFunctionalLevel
            New-BrokerDesktopGroup -Name $TargetDeliveryGroup -DesktopKind Private -MinimumFunctionalLevel $SourceCatFunc -AdminAddress $Controller -ErrorAction Stop
            Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Created successfully" -Level Info

            Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Creating default Access Policy Rules" -Level Info
            $DesktopGroupUid = Get-BrokerDesktopGroup -Name $TargetDeliveryGroup | Select-Object -ExpandProperty Uid
            New-BrokerAccessPolicyRule -Name $($TargetDeliveryGroup+"_AG") -Enabled $true -AllowedProtocols @("HDX","RDP") -AllowedUsers Filtered -AllowRestart $true -AllowedConnections ViaAG -IncludedSmartAccessFilterEnabled $true -IncludedUserFilterEnabled $true -DesktopGroupUid $DesktopGroupUid -AdminAddress $Controller
            New-BrokerAccessPolicyRule -Name $($TargetDeliveryGroup+"_Direct") -Enabled $true -AllowedProtocols @("HDX","RDP") -AllowedUsers Filtered -AllowRestart $true -AllowedConnections NotViaAG -IncludedSmartAccessFilterEnabled $true -IncludedUserFilterEnabled $true -DesktopGroupUid $DesktopGroupUid -AdminAddress $Controller
            Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup): Default Access Policy Rules created successfuly" -Level Info 
            Write-Log -Message "!!------- Target Delivery Group: $($TargetDeliveryGroup): Does not contain any allowed users or desktop assignment rules. Manually add these as required" -Level Warn
            Write-Log -Message "!!------- Target Delivery Group: $($TargetDeliveryGroup): Contains a default Published Name value. This may impact the user experience. Manually alter this as required" -Level Warn
        }
    }
    catch {
        Write-Log -Message $_ -level Warn
        StopIteration
        Exit 1
    }   
}

function RemoveMCSProvisionedMachine {
    Write-Log -Message "Processing $($VM.MachineName)" -Level Info
    # Set Maintenance Mode
    try {
        Write-Log -Message "$($VM.MachineName): Setting Maintenance Mode to On" -Level Info
        Set-BrokerMachine -MachineName $VM.MachineName -InMaintenanceMode $true -AdminAddress $Controller -ErrorAction Stop
        Write-Log -Message "$($VM.MachineName): Successfully set Maintenance Mode to On" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        $ErrorCount += 1
    }
    # Remove from Desktop Group
    try {
        if ($VM.DesktopGroupName) {
            Write-Log -Message "$($VM.MachineName): Removing from Delivery Group $($VM.DesktopGroupName)" -Level Info
            Remove-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $VM.DesktopGroupName -force -AdminAddress $Controller -ErrorAction Stop
            Write-Log -Message "$($VM.MachineName): Successfully removed from Delivery Group $($VM.DesktopGroupName)" -Level Info 
        }
    }
    catch {
        Write-Log -Message $_ -Level Warn
        $ErrorCount += 1
        Break
    }
    # Unlock Account
    $ProvVM = (get-provvm -VMName ($VM.MachineName | Split-Path -Leaf))
    try {
        Write-Log -Message "$($VM.MachineName): Unlocking ProvVM Account" -Level Info
        Unlock-ProvVM -VMID $ProvVM.VMId -ProvisioningSchemeName $VM.CatalogName -AdminAddress $Controller -ErrorAction Stop
        Write-Log -Message "$($VM.MachineName): Successfully unlocked ProvVM Account" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        $ErrorCount += 1
    }
    # RemoveProvVM
    try {
        Write-Log -Message "$($VM.MachineName): Removing ProvVM but keeping VM" -Level Info
        $null = remove-ProvVM -VMName $ProvVM.VMName -ProvisioningSchemeName $VM.CatalogName -ForgetVM -AdminAddress $Controller -ErrorAction Stop
        Write-Log -Message "$($VM.MachineName): Successfully removed ProvVM $($ProvVM.VMName)" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        $ErrorCount += 1
    }
    # remove account from machine catalog
    try {
        Write-Log -Message "$($VM.MachineName): Removing Account from Machine Catalog $($VM.CatalogName)" -Level Info
        $null = Remove-AcctADAccount -IdentityPoolName $VM.CatalogName -ADAccountSid $ProvVM.ADAccountSid -RemovalOption None -AdminAddress $Controller -ErrorAction Stop
        Write-Log -Message "$($VM.MachineName): Successfully removed Account from Machine Catalog $($VM.CatalogName)" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        $ErrorCount += 1
    }   
    # remove BrokerMachine
    try {
        Write-Log -Message "$($VM.MachineName): Removing VM from Machine Catalog $($VM.CatalogName)" -Level Info
        remove-BrokerMachine -MachineName $VM.MachineName -AdminAddress $Controller -ErrorAction Stop
        Write-Log -Message "$($VM.MachineName): Successfully removed VM from Machine Catalog $($VM.CatalogName)" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        $ErrorCount += 1
        Break
    }
    GetUpdatedCatalogAccountIdentityPool 
}

function GetCatalogAccountIdentityPool {
    $IdentityPool = try { #get details about the Identity Pool
        Write-Log -Message "Source Catalog: $($SourceCatalog) Getting Identity Pool information" -Level Info
        Get-AcctIdentityPool -IdentityPoolName $SourceCatalog -AdminAddress $Controller -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Source Catalog: $($SourceCatalog) Cannot get information about associated Identity Pool. Not proceeding" -Level Warn
        StopIteration
        Exit 1
    }
}

function GetUpdatedCatalogAccountIdentityPool  {
    Write-Log -Message "Source Catalog: $($SourceCatalog) getting updated associated identity Pool information" -Level Info
    $UpdatedIdentityPool = try { #get details about the Identity Pool
        Get-AcctIdentityPool -IdentityPoolName $SourceCatalog -AdminAddress $Controller -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "$($SourceCatalog): Cannot get updated associated identity Pool information " -Level Warn
        Break
    }
    
    if (!($UpdatedIdentityPool.OU)) { #incase this is the last machine being removed - reset the OU back to the inital OU
        try {
            Write-Log -Message "Setting OU for Identity Pool: $($IdentityPool.IdentityPoolName) back to Initial OU: $($IdentityPool.OU)" -Level Info
            Set-AcctIdentityPool -IdentityPoolName $IdentityPool.IdentityPoolName -OU $IdentityPool.OU -AdminAddress $Controller -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    else {
        Write-Log -Message "Identity Pool: $($UpdatedIdentityPool.IdentityPoolName) is set to $($UpdatedIdentityPool.OU)" -Level Info
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

#Region Error Handling where to complex for Param Sets
# Handle TargetMachineScope
if ($TargetMachineScope -eq "CSV" -and $TargetMachineCSVList -eq "") {
    Write-Log -Message "PARAMETER ERROR: You cannot use a CSV input for TargetMachineScope and not include a TargetMachineCSVList. Please use the TargetMachineCSVList Parameter" -Level Warn
    StopIteration
    Exit 1
}
if ($TargetMachineScope -eq "CSV" -and $null -ne $TargetMachineList) {
    Write-Log -Message "PARAMETER ERROR: You cannot use a CSV input for TargetMachineScope and specify a Manual TargetMachineList. Please use the TargetMachineCSVList Parameter" -Level Warn
    StopIteration
    Exit 1
}
if ($TargetMachineScope -eq "MachineList" -and $TargetMachineList -eq "") {
    Write-Log -Message "PARAMETER ERROR: You cannot use a MachineList input for TargetMachineScope and not include a Machine List. Please use the TargetMachineList Parameter" -Level Warn
    StopIteration
    Exit 1
}
if ($TargetMachineScope -eq "MachineList" -and $TargetMachineCSVList -ne "") {
    Write-Log -Message "PARAMETER ERROR: You cannot use a MachineList input for TargetMachineScope and specify a TargetMachineCSVList. Please use the TargetMachineList Parameter" -Level Warn
    StopIteration
    Exit 1
}
if ($TargetMachineScope -eq "All" -and $TargetMachineCSVList -ne "") {
    Write-Log -Message "ERROR: You cannot use a TargetMachineScope of All and specify a TargetMachineCSVList. Please remove the TargetMachineCSVList Parameter" -Level Warn
    StopIteration
    Exit 1
}
if ($TargetMachineScope -eq "All" -and $null -ne $TargetMachineList) {
    Write-Log -Message "PARAMETER ERROR: You cannot use a TargetMachineScope of All and specify a TargetMachineList. Please remove the TargetMachineList Parameter" -Level Warn
    StopIteration
    Exit 1
}
# Handle PublishedName
if ($SetPublishedNameToMachineName.IsPresent -and $OverridePublishedName -ne "") {
    Write-Log -Message "PARAMETER ERROR: You cannot use SetPublishedNameToMachineName and OverridePublishedName variables together" -Level Warn
    StopIteration
    Exit 1
}
#endregion

#Region JSON
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

    $Controller = $EnvironmentDetails.Controller
    $SourceCatalog = $EnvironmentDetails.SourceCatalog
    $TargetCatalog = $EnvironmentDetails.TargetCatalog
    $SourceDeliveryGroup = $EnvironmentDetails.SourceDeliveryGroup
    $TargetDeliveryGroup = $EnvironmentDetails.TargetDeliveryGroup
    $OverridePublishedName = $EnvironmentDetails.OverridePublishedName
    $TargetMachineScope = $EnvironmentDetails.TargetMachineScope
    $TargetMachineList = $EnvironmentDetails.TargetMachineList
    $TargetMachineCSVList = $EnvironmentDetails.TargetMachineCSVList

    # Handle Machine List Array in JSON Input
    if ($EnvironmentDetails.TargetMachineList -like "*,*") {
        $EnvironmentDetails.TargetMachineList = [array]$EnvironmentDetails.TargetMachineList.Split(",")
        $TargetMachineList = $EnvironmentDetails.TargetMachineList
    }
}
#endregion

#Region Connection
# ============================================================================
# Connect to Environment
# ============================================================================

LoadCitrixSnapins

TryForAuthentication
#endregion

# ============================================================================
# Get Environment Details
# ============================================================================
Write-Log -Message "Working with Source Catalog: $($SourceCatalog)" -Level Info
Write-Log -Message "Working with Target Catalog: $($TargetCatalog)" -Level Info
if ($AlignTargetDeliveryGroupToSource.IsPresent -and $SourceDeliveryGroup -ne "") {
    Write-Log -Message "Working with Source Delivery Group: $($SourceDeliveryGroup)" -Level Info
}
Write-Log -Message "Working with Target Delivery Group: $($TargetDeliveryGroup)" -Level Info
Write-Log -Message "Working with Delivery Controller: $($Controller)" -Level Info
Write-Log -Message "Working with Target Machine Scope: $($TargetMachineScope)" -Level Info

#Region Catalog Handling
#GetSourceCatalog
$Catalog = try {
    Write-Log -Message "Source Catalog: Getting details for $SourceCatalog" -Level Info
    Get-BrokerCatalog -Name $SourceCatalog -AdminAddress $Controller -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -level Warn
    StopIteration
    Exit 1
}

CheckCatalogIsMCS

GetCatalogAccountIdentityPool

#GetTargetCatalog
$NewCatalog = try {
    Write-Log -Message "Target Catalog: Getting details for $TargetCatalog" -Level Info
    Get-BrokerCatalog -Name $TargetCatalog -AdminAddress $Controller -ErrorAction Stop
}
catch {
    Write-Log -Message "Target Catalog: $($TargetCatalog) not found. Creating Target Catalog"
    CreateManualCatalog
}

CheckCatalogisManual

#endregion

#Region Delivery Group Handling
#GetTargetDeliveryGroup
$DeliveryGroup = try {
    Write-Log -Message "Target Delivery Group: Getting Detail for $TargetDeliveryGroup" -Level Info
    Get-BrokerDesktopGroup -name $TargetDeliveryGroup -AdminAddress $Controller -ErrorAction Stop
}
catch {
    Write-Log -Message "Target Delivery Group: $($TargetDeliveryGroup) not found. Creating Target Delivery Group"
    CreateTargetDeliveryGroup
} 
#endregion

#Region VM Handling
#GetVMs
if ($TargetMachineScope -eq "All") {
    Write-Log -Message "Source Catalog: Getting VMs from: $SourceCatalog" -Level Info
    $VMS = Get-BrokerMachine -CatalogName $SourceCatalog -AdminAddress $Controller -MaxRecordCount $MaxRecordCount -ErrorAction Stop       
}
elseif ($TargetMachineScope -eq "MachineList") {
    if ($null -ne $TargetMachineList) {
        Write-Log -Message "Source Machine List: Getting VMs from specified list $($TargetMachineList)" -Level Info
        $VMS = Get-BrokerMachine -CatalogName $SourceCatalog -AdminAddress $Controller -MaxRecordCount $MaxRecordCount | Where-Object { $_.HostedMachineName -in $TargetMachineList }
    }
    else {
        Write-Log -Message "No Machine Specified in Machine List. Exit Script" -Level Warn
        StopIteration
        Exit 1
    }
}
elseif ($TargetMachineScope -eq 'CSV') {
    if (!(Test-Path -path $TargetMachineCSVList)) {
        Write-Log -Message "CSV Path: $($TargetMachineCSVList) not found. Please check the path. Exit Script" -Level Warn
        StopIteration
        Exit 1
    }
    else {
        Write-Log -Message "Importing VMS from CSV List $($TargetMachineCSVList)" -Level Info
        try {
            $CSVList = Import-Csv -Path $TargetMachineCSVList -ErrorAction Stop 
            $VMS = Get-BrokerMachine -CatalogName $SourceCatalog -AdminAddress $Controller -MaxRecordCount $MaxRecordCount | Where-Object { $_.HostedMachineName -in $CSVList.HostedMachineName } ##//Looking for a match...only get machines in $CSVList
        }
        catch {
            Write-Log -Message $_ -level Warn
            Write-Log -Message "Failed to Import CSV File. Exit Script" -level Warn
            StopIteration
            Exit 1
        }
    }
} 
#endregion

# ============================================================================
# Execute the migration
# ============================================================================
$Count = ($VMs | Measure-Object).Count
$StartCount = 1
$ErrorCount = 0

if ($Count -lt 1) {
    Write-Log -Message "There are no machines to process. Please check parameter entries. Exit Script" -Level Info
    StopIteration
    Exit 0
}
else {
    Write-Log -Message "There are $Count machines to process" -Level Info
}

foreach ($VM in $VMs) {
    if ($VM.ProvisioningType -eq "MCS") {
        Write-Log -Message "Processing machine $StartCount of $Count" -Level Info

        Write-Log -Message "$($VM.MachineName): Processing removal tasks" -Level Info
        RemoveMCSProvisionedMachine

        Write-Log -Message "$($VM.MachineName): Processing addition tasks" -Level Info
        AddVMToCatalog
        AddVMtoDeliveryGroup
        AddUsertoVM
        if ($OverridePublishedName) {
            $PublishedName = $OverridePublishedName
            SetVMDisplayName
        }
        elseif ($SetPublishedNameToMachineName.IsPresent) {
            $PublishedName = ($VM.MachineName | Split-Path -leaf)
            SetVMDisplayName
        }
        else {
            $PublishedName = $VM.PublishedName
            SetVMDisplayName
        }
        $StartCount += 1
    }
    else {
        Write-Log -Message "$($VM.MachineName) is not a MCS provisioned machine. Not proceeding" -Level Warn
        Break
    }
}

# Check error count
if ($ErrorCount -ne "0") {
    Write-Log -Message "There are $ErrorCount errors recorded. Please review logfile $LogPath" -Level Info
}

StopIteration
Exit 0
#endregion
