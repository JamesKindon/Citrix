<#
.SYNOPSIS
.DESCRIPTION
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER JSON
    Will consume a JSON import for configuration
.PARAMETER JSONInputPath
    Specifies the JSON input file
.PARAMETER SourceCatalog  
.PARAMETER TargetCatalog  
.PARAMETER TargetDeliveryGroup  
.PARAMETER OverridePublishedName  
.PARAMETER SetPublishedNameToMachineName
.PARAMETER PublishedName
.PARAMETER CitrixCloud
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\MCSMigration.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false, ParameterSetName = 'JSON')]
    [Switch]$JSON,

    [Parameter(Mandatory = $true, ParameterSetName = 'JSON')]
    [String]$JSONInputPath,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$SourceCatalog,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$TargetCatalog,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [String]$TargetDeliveryGroup,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [Parameter(ParameterSetName = 'JSON')]
    [Parameter(ParameterSetName = 'ReplacePublishedName')]
    [Switch]$SetPublishedNameToMachineName,

    [Parameter(Mandatory = $false, ParameterSetName = 'NoJSON')]
    [Parameter(ParameterSetName = 'ManualPublishedName')]
    [Switch]$OverridePublishedName,

    [Parameter(Mandatory = $true, ParameterSetName = 'NoJSON')]
    [Parameter(ParameterSetName = 'ManualPublishedName')]
    [String]$PublishedName
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

function AddVMtoCatalog {
    if ($null -eq (Get-BrokerMachine -MachineName $VM.MachineName -ErrorAction SilentlyContinue)) {
        Write-Log -Message "$($VM.MachineName): Adding to Catalog $($NewCatalog.Name)" -Level Info
        try {
            $null = New-BrokerMachine -CatalogUid $NewCatalog.Uid -HostedMachineId $VM.HostedMachineId -HypervisorConnectionUid $VM.HypervisorConnectionUid -MachineName $VM.SID -Verbose -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
    }
    else {
        $ExistingCatalog = (Get-BrokerMachine -MachineName $VM.MachineName).CatalogName
        Write-Log -Message "$($VM.MachineName): Already exists in catalog $($ExistingCatalog)" -Level Warn
    }
}

function AddVMtoDeliveryGroup {
    $DG = (Get-BrokerMachine -MachineName $VM.MachineName).DesktopGroupName
    if ($null -eq $DG) {
        Write-Log -Message "$($VM.MachineName): Adding to Delivery Group $($DeliveryGroup.Name)" -Level Info
        try {
            Add-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $DeliveryGroup.Name -Verbose -ErrorAction Stop
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
                Add-BrokerUser $User -PrivateDesktop $VM.MachineName -Verbose -ErrorAction Stop
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
    #Need to think about this more and compare with Delivery GroupName
    if ($null -ne $PublishedName) {
        Write-Log -Message "$($VM.MachineName): Setting Published Name to $PublishedName" -Level Info
        try {
            Set-BrokerMachine -MachineName $VM.MachineName -PublishedName $PublishedName -Verbose -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -level Warn
        }
    }
    else {
        Write-Log -Message "$($VM.MachineName): No Published name specified" -Level Info
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
        Write-Log -Message "Confirming Authentication with Citrix Cloud" -Level Info
        $null = Get-BrokerSite -ErrorAction Stop # This should trigger an auth call if session has timed out (else Get-XDAuthentication)
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

function RemoveMCSProvisionedMachine {
    Write-Log -Message "Processing $($VM.MachineName)" -Level Info
    # Set Maintenance Mode
    try {
        Write-Log -Message "$($VM.MachineName): Setting Maintenance Mode to On" -Level Info
        Set-BrokerMachine -MachineName $VM.MachineName -InMaintenanceMode $true
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Break
    }
    # Remove from Desktop Group
    try {
        if ($VM.DesktopGroupName) {
            Write-Log -Message "$($VM.MachineName): Removing from Delivery Group $($VM.DesktopGroupName)" -Level Info
            Remove-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $VM.DesktopGroupName -force    
        }
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Break
    }
    # Unlock Account
    try {
        Write-Log -Message "$($VM.MachineName): Unlocking ProvVM Account" -Level Info
        #Unlock-ProvVM -VMID (get-provvm -VMName $VM.hostedmachinename).VMId -ProvisioningSchemeName $VM.CatalogName
        Unlock-ProvVM -VMID (get-provvm -VMName ($VM.MachineName | Split-Path -Leaf)).VMId -ProvisioningSchemeName $VM.CatalogName #TESTING
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Break
    }
    try {
        Write-Log -Message "$($VM.MachineName): Removing Account from Machine Catalog" -Level Info
        $null = Remove-AcctADAccount -IdentityPoolName $VM.CatalogName -ADAccountSid $VM.SID -RemovalOption None
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Break
    }   
    #remove account from machine catalog
    try {
        Write-Log -Message "$($VM.MachineName): Removing VM from Machine Catalog" -Level Info
        remove-BrokerMachine -MachineName $VM.MachineName
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Break
    }
    GetUpdatedCatalogAccountIdentityPool    
}

function GetCatalogAccountIdentityPool {
    $IdentityPool = try { #get details about the Identity Pool
        Write-Log -Message "Source Catalog: $($SourceCatalog) Getting Identity Pool information" -Level Info
        Get-AcctIdentityPool -IdentityPoolName $SourceCatalog -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Source Catalog: $($SourceCatalog) Cannot get information about associated Identity Pool. Not proceeding" -Level Warn
        StopIteration
        Exit 1
    }
}

function GetUpdatedCatalogAccountIdentityPool  {
    $UpdatedIdentityPool = try { #get details about the Identity Pool
        Get-AcctIdentityPool -IdentityPoolName $SourceCatalog -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Messagae "$($SourceCatalog): Cannot get updated associated identity Pool information " -Level Warn
        Break
    }
    
    if (!($UpdatedIdentityPool.OU)) { #incase this is the last machine being removed - reset the OU back to the inital OU
        try {
            Write-Log -Message "Setting OU for Identity Pool: $($IdentityPool.IdentityPoolName) back to Initial OU: $($IdentityPool.OU)" -Level Info
            Set-AcctIdentityPool -IdentityPoolName $IdentityPool.IdentityPoolName -OU $IdentityPool.OU -ErrorAction Stop
        }
        catch {
            Write-Log -Message $_ -Level Warn
        }
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

    $SourceCatalog = $EnvironmentDetails.SourceCatalog
    $TargetCatalog = $EnvironmentDetails.TargetCatalog
    $TargetDeliveryGroup = $EnvironmentDetails.TargetDeliveryGroup
    $PublishedName = $EnvironmentDetails.PublishedName
}

# ============================================================================
# Connect to Environment
# ============================================================================

LoadCitrixSnapins

TryForAuthentication

# ============================================================================
# Get Environment Details
# ============================================================================
Write-Log -Message "Working with Source Catalog: $($SourceCatalog)" -Level Info
Write-Log -Message "Working with Target Catalog: $($TargetCatalog)" -Level Info
Write-Log -Message "Working with Target Delivery Group: $($TargetDeliveryGroup)" -Level Info

#GetSourceCatalog
$Catalog = try {
    Write-Log -Message "Source Catalog: Getting details for $SourceCatalog" -Level Info
    Get-BrokerCatalog -Name $SourceCatalog -ErrorAction Stop
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
    Get-BrokerCatalog -Name $TargetCatalog -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -level Warn
    StopIteration
    Exit 1
}

CheckCatalogisManual

#GetTargetDeliveryGroup
$DeliveryGroup = try {
    Write-Log -Message "Target Delivery Group: Getting Detail for $TargetDeliveryGroup" -Level Info
    Get-BrokerDesktopGroup -name $TargetDeliveryGroup -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -level Warn
    StopIteration
    Exit 1
}  

#GetVMs
$VMS = try {
    Write-Log -Message "Source Catalog: Getting VMs from: $SourceCatalog" -Level Info
    Get-BrokerMachine -CatalogName $SourceCatalog -ErrorAction Stop
}
catch {
    Write-Log -Message $_ -level Warn
    StopIteration
    Exit 1
}  

# ============================================================================
# Execute the migration
# ============================================================================
$Count = ($VMs | Measure-Object).Count
$StartCount = 1

Write-Log -Message "There are $Count machines to process" -Level Info

foreach ($VM in $VMs) {
    if ($VM.ProvisioningType -eq "MCS") {
        Write-Log -Message "Processing machine $StartCount of $Count" -Level Info
        RemoveMCSProvisionedMachine
        AddVMToCatalog
        AddVMtoDeliveryGroup
        AddUsertoVM
        if ($OverridePublishedName.IsPresent) {
            $PublishedName = $PublishedName
            SetVMDisplayName
        }
        if ($SetPublishedNameToMachineName.IsPresent) {
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

StopIteration
Exit 0
#endregion

