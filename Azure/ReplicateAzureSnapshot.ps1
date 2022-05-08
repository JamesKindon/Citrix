<#
.SYNOPSIS
    Script designed to run via Azure Automation to replicate snapshots to another region or another subscription. Targeted but not limited to Citrix MCS use cases
.DESCRIPTION
    Script will, based on your input params, take snapshots from a source region and subscription and move it to a target region or subscription. The script offers a synchronisation model, selective sync model and can be filtered by Tagging
    The script is speficially limited to one Source and Target Resource Group and one regional job at a time. If you want multiple, then create multiple runbooks with appropriate params
    Script leverages the appropriate mechanism for migration, when going cross region this requires a storage account being created in the target, a copy into a container within the store account, and then a new snapshot created from that copied data
    The Script handles all creations, copies and cleanup tasks
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER SourceSubscriptionID
    The source subscription ID of where your snapshots live
.PARAMETER TargetSubscriptionID
    If moving cross subscription, this is the target Subscription ID for where your snapshots will sync to
.PARAMETER SourceResourceGroup
    The source Resource Group (name) of where your snapshots live
.PARAMETER TargetResourceGroup
    The target Resource Group (name) for where your snapshots will sync to
.PARAMETER TargetRegion
    If moving region, the target region for your snapshots
.PARAMETER SnapshotName
    Individual snapshot name to sync. Cannot be used with Sync or UseTagFiltering Params. 
    Leave as $null (default) if not using
.PARAMETER Mode
    Offers 3 models of operation
        - SameSubDifferentRegion = The same source Azure subscription but a different target region
        - DifferentSubSameRegion = A different Azure Subscription in the same region
        - DifferentSubDifferentRegion (default) = A different Azure Subscription in a differnt Azure Region
.PARAMETER Sync
    Modes: Sync, DontSync
    Sets the flag to compare source and destination Resource Group Snapshots. This is a sync job. If a deletion occurs in the source, it will be mirrored in the target. You have been warned. It will delete. You have been warned twice.
    Can be used in conjunction with UseTagFiltering
    Cannot be used with SnapshotName
    This will delete in the target. You have been warned 3 times.
.PARAMETER UseTagFiltering
    The recommended model for Sync. Requires setting a tag on snapshots in the source which are targeted for sync to the target. Ignores all other snaps
    Script defaults to looking for a tag of "SnapReplicate" with a value of "Replicate"
    Can be used in conjunction with Sync
    Cannot be used with SnapshotName
.PARAMETER isAzureRunbook
    The designed operational model for this runbook
    Set to true, assumes you are running with a system managed identity on the automation account
    Set to false, you will need to authenticate as per normal means in your local PowerShell session
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(

    [Parameter(Mandatory = $false)]
    [string]$isAzureRunbook = "true", #Set to true if using an Azure Runbook, this will move the authentication model to the Automation Account

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\ReplicateAzureSnapshot.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [string]$SourceSubscriptionID = "Source-Sub-ID",

    [Parameter(Mandatory = $false)]
    [string]$TargetSubscriptionID = "Target-Sub-ID",

    [Parameter(Mandatory = $false)]
    [string]$SourceResourceGroup = "Source-ResourceGroup-Name",

    [Parameter(Mandatory = $false)]
    [string]$TargetResourceGroup = "Target-ResourceGroup-Name",

    [Parameter(Mandatory = $false)]
    [string]$TargetRegion = "australiasoutheast",

    [Parameter(Mandatory = $false)]
    [array]$SnapshotName = $null,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("SameSubDifferentRegion", "DifferentSubSameRegion", "DifferentSubDifferentRegion")]
    [String]$Mode = "DifferentSubDifferentRegion",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Sync", "DontSync")]
    [String]$Sync = "Sync", # cleanup target Resource Group if snapshot deleted in source Resource Group

    [Parameter(Mandatory = $false)]
    [ValidateSet("True", "False")]
    [String]$UseTagFiltering = "True" # Use Tag Filtering to target Snapshots for Sync. If set to False, all snapshots in the source and target Resource Groups will be targeted. Tags are only used in source filtering. Be careful.

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
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
                Write-Output $Message # Altered from Write-Verbose to cater for Azure Runbook output
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
    } elseif ($StopWatch.Elapsed.TotalSeconds -lt 60) {
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.TotalSeconds) seconds to complete." -Level Info
    } elseif ($StopWatch.Elapsed.TotalSeconds -ge 60) {
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.TotalMinutes) minutes to complete." -Level Info
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

function SelectTargetSubscription {
    Write-Log -Message "Setting target Azure Subscription to $($TargetSubscriptionID)" -Level Info
    Set-AzContext -Subscription $TargetSubscriptionID | Out-Null
}

function SelectSourceSubscription {
    Write-Log -Message "Setting source Azure Subscription to $($SourceSubscriptionID)" -Level Info
    Set-AzContext -Subscription $SourceSubscriptionID | Out-Null
}

function GetTargetSubscriptionSnapshots {
    Write-Log -Message "Getting Snapshots in target Subscription in Resource Group: $($TargetResourceGroup)" -Level Info
    $Global:TargetSnapshots = Get-AzSnapShot -ResourceGroupName $TargetResourceGroup
    Write-Log -Message "There are $(($TargetSnapshots).Count) snapshots in the target Resource Group: $TargetResourceGroup" -Level Info    
}

function GetSourceSubscriptionSnapshots {
    if ($null -ne $SnapshotName) {
        Write-Log -Message "Snapshot Names have been specified. Script will only process defined snapshot names" -Level Info
        $Global:SourceSnapshots = $SnapshotName
        $Global:SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup | Where-Object {$_.Name -like $SourceSnapshots}
    }
    elseif ($UseTagFiltering -eq "True") {
        Write-Log -Message "Getting Snapshots in source Subscription in Resource Group: $($SourceResourceGroup) with Tag: $($Tag) with value: $($ReplicateTrigger)" -Level Info
        $Global:SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup | Where-Object { $_.Tags.Keys -eq $Tag -and $_.Tags.Values -contains $ReplicateTrigger }
    } 
    else {
        Write-Log -Message "Getting Snapshots in source Subscription in Resource Group: $($SourceResourceGroup)" -Level Info
        $Global:SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup
    }
    Write-Log -Message "There are $(($SourceSnapshots).Count) snapshots in the source Resource Group: $($SourceResourceGroup) targeted for replication"
}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
# Set Variables
$Tag = "SnapReplicate"
$ReplicateTrigger = "Replicate"
#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

# Check to see if flagged as a runbook, if true, process accordingly
if ($isAzureRunbook -eq "true") {
    try {
        Write-Log -Message "Logging in to Azure..." -Level Info
        #https://docs.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation#authenticate-access-with-system-assigned-managed-identity
        # Ensures you do not inherit an AzContext in your runbook
        Disable-AzContextAutosave -Scope Process
    
        # Connect to Azure with system-assigned managed identity
        $AzureContext = (Connect-AzAccount -Identity).context
    
        # set and store context
        $AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext -ErrorAction Stop
    
        Write-Log -Message "Authenticated" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Failed to Authenticate. Exit Script." -Level Warn
        StopIteration
        Exit 1
    }
}
else {
    # Check for Auth 
    $AuthTest = Get-AzSubscription -ErrorAction SilentlyContinue
    if (-not($AuthTest)) {
        Connect-AzAccount
    }
}

#----------------------------------------------------------------------------
# Output operational data
#----------------------------------------------------------------------------
#region OpData
if ($Sync -eq "Sync") {
    Write-Log -Message "Sync mode is enabled. Comparing source and target Resource Groups. Deleting Snaphots in target if removed or filtered from the source list" -Level Info
}

if ($UseTagFiltering -eq "True") {
    Write-Log -Message "Tag Filtering is enabled. Filtering source snapshots via specified Tag: $($Tag) with value: $($ReplicateTrigger)" -Level Info
}

if ($null -ne $SnapshotName -and $Sync -eq "Sync") {
    Write-Log -Message "Sync Mode cannot be used when combined with SnapshotName. Ensure Sync is set to DontSync" -Level Warn
    Write-Log -Message "Specified Parameters not supported together. Exit Script" -Level Warn
    StopIteration
    Exit 1
}

if ($null -ne $SnapshotName -and $UseTagFiltering -eq "True") {
    Write-Log -Message "Tag filtering cannot be used when combined with SnapshotName. Ensure UseTagFiltering is set to False" -Level Warn
    Write-Log -Message "Specified Parameters not supported together. Exit Script" -Level Warn
    StopIteration
    Exit 1
}

if ($mode -eq "DifferentSubSameRegion") {
    Write-Log -Message "Mode: DifferentSubSameRegion is selected. Copying snapshots to the same region in a different subscripion" -Level Info
}
if ($mode -eq "DifferentSubDifferentRegion"){
    Write-Log -Message "Mode: DifferentSubDifferentRegion is selected. Copying snapshots to a different region in a different subscripion" -Level Info
}
if ($mode -eq "SameSubDifferentRegion"){
    Write-Log -Message "Mode: SameSubDifferentRegion is selected. Copying snapshots to a different region in the same subscripion" -Level Info
}

Write-Log -Message "Source Subscription is: $($SourceSubscriptionID)" -Level Info
if ($null -ne $TargetSubscriptionID -and $mode -ne "SameSubDifferentRegion") { Write-Log -Message "Target Subscription is: $($TargetSubscriptionID)" -Level Info }
Write-Log -Message "Source Resource Group is: $($SourceResourceGroup)" -Level Info
Write-Log -Message "Target Resource Group is: $($TargetResourceGroup)" -Level Info
if ($null -ne $SnapshotName) { Write-Log -Message "Provided Snapshot name is: $($SnapshotName)" -Level Info }
if ($null -ne $TargetRegion -and $mode -ne "DifferentSubSameRegion") { Write-Log -Message "Target Region is: $($TargetRegion)" -Level Info }
#endregion

SelectSourceSubscription

GetSourceSubscriptionSnapshots

#----------------------------------------------------------------------------
# Different Subscription Same Region
#----------------------------------------------------------------------------
if ($mode -eq "DifferentSubSameRegion") {

    SelectTargetSubscription

    GetTargetSubscriptionSnapshots

    if ($null -ne $SourceSnapshots) {
        foreach ($Snapshot in $SourceSnapshots) {
            if ($snapshot.Name -in $TargetSnapshots.Name) {
                Write-Log -Message "$($snapshot.Name) already exists in the target Subscription" -Level Info
            }
            else {
                if ($null -ne $snapshot.Name) {
                    Write-Log -Message "$($snapshot.Name) added to processing list" -Level Info
                    try {
                        Write-Log -Message "Copying snapshot $($Snapshot.Name) in source Resource Group: $($SourceResourceGroup) in source Subscription $($SourceSubscriptionID) as $($Snapshot.Name) in target Resource Group $($TargetResourceGroup) in target Subscription: $($TargetSubscriptionID)" -Level Info
                        # Create Snapshot config from source snapshot in Target Subscription
                        $SnapshotConfig = New-AzSnapshotConfig -OsType $SnapShot.OsType -Location $SnapShot.Location -CreateOption Copy -SourceResourceId $Snapshot.Id
                        # Create new Snapshot in Target Subcscription
                        $NewSnap = New-AzSnapshot -ResourceGroupName $TargetResourceGroup -SnapshotName $Snapshot.Name -Snapshot $SnapshotConfig -ErrorAction Stop
                        Write-Log -Message "Successfully copied snapshot $($Snapshot.Name)" -Level Info
                    }
                    catch {
                        Write-Log -Message $_ -Level Warn
                    }
                }
                else {
                    Write-Log -Message "Specified snapshot not found. Check input name" -Level Warn
                    Break
                }
            }        
        }
    }
    else {
        Write-Log -Message "There are no snapshots for replication" -Level Info
    }
}

#----------------------------------------------------------------------------
# Different Subscription Different Region
#----------------------------------------------------------------------------
if ($mode -eq "DifferentSubDifferentRegion") {

    SelectTargetSubscription

    GetTargetSubscriptionSnapshots

    #----------------------------------------------------------------------------
    # Remove snapshot from $SourceSnapshots if already exists in target
    #----------------------------------------------------------------------------
    $NewSourceSnaps = @()

    foreach ($Snapshot in $SourceSnapshots) {
        if ($Snapshot.Name -in $TargetSnapshots.Name) {
            Write-Log -Message "$($snapshot.Name) already exists in the target Subscription. Removing from processing" -Level Info
        }
        else {
            if ($null -ne $snapshot.Name) {
                Write-Log -Message "$($snapshot.Name) added to processing list" -Level Info
                $NewSourceSnaps = $NewSourceSnaps += $Snapshot    
            }
            else {
                Write-Log -Message "Specified snapshot not found. Check input name" -Level Warn
            }
        }
    }

    $SourceSnapshots = $NewSourceSnaps
    Write-Log -Message "There are now $(($SourceSnapShots).Count) snapshots in the source Resource Group: $($SourceResourceGroup) for replication"

    if ($SourceSnapshots.Count -gt 0) {

        #region storage accounts
        #----------------------------------------------------------------------------
        # Handle Storage Accounts
        #----------------------------------------------------------------------------
        Write-Log -Message "Setting storage account details" -Level Info
        $StorageAccountName = "rep" + [system.guid]::NewGuid().tostring().replace('-', '').substring(1, 18)
        Write-Log -Message "Storage account name is: $($StorageAccountName)" -Level Info

        try {
            # Create the context for the storage account which will be used to copy the snapshot to the storage account 
            Write-Log -Message "Attempting to create storage account: $($StorageAccountName)" -Level Info
            $StorageAccount = New-AzStorageAccount -ResourceGroupName $TargetResourceGroup -Name $StorageAccountName -SkuName "Standard_LRS" -Location $TargetRegion -ErrorAction Stop
            $DestinationContext = $StorageAccount.Context

            Write-Log -Message "Attempting to create storage account container: $($StorageAccountName)" -Level Info
            $Container = New-AzStorageContainer -Name $StorageAccountName -Permission "Container" -Context $DestinationContext -ErrorAction Stop
            Write-Log -Message "Successfully created storage account: $($StorageAccountName) and container: $($StorageAccountName)" -Level Info
        }
        catch {
            Write-Log -Message "Failed to create storage account for transfer. Exit script" -Level Warn
            Write-Log -Message $_ -Level Warn
            StopIteration
            Exit 1
        }
        #endregion

        #region replicate snapshots
        foreach ($Snapshot in $SourceSnapshots) {
            try {
                SelectSourceSubscription

                Write-Log -Message "Copying snapshot $($Snapshot.Name) in source Resource Group: $($SourceResourceGroup) in source Subscription $($SourceSubscriptionID) as $($Snapshot.Name) in target Resource Group $($TargetResourceGroup) in target Subscription: $($TargetSubscriptionID)" -Level Info
                
                #----------------------------------------------------------------------------
                # Create a Shared Access Signature (SAS) for the source snapshot
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Attempting to create and retrieve SAS URI for snapshot $($Snapshot.Name)" -Level Info
                    $SnapSasUrl = Grant-AzSnapShotAccess -ResourceGroupName $SourceResourceGroup -SnapshotName $Snapshot.Name -DurationInSecond 3600 -Access Read -ErrorAction Stop
                    Write-Log -Message "Successfully created SAS URI for snapshot $($Snapshot.Name)"
                }
                catch {
                    Write-Log -Message $_ -Level Warn
                    Break
                }
                    
                SelectTargetSubscription

                #----------------------------------------------------------------------------
                # Copy the Snapshot to the storage account
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Attempting snapshot transfer for: $($Snapshot.Name) to storage account container" -Level Info
                    Start-AzStorageBlobCopy -AbsoluteUri $snapSasUrl.AccessSAS -DestContainer $Container.Name -DestContext $DestinationContext -DestBlob $Snapshot.Name -ErrorAction Stop | Out-null
                    $Sleep = "30"
                    while (($State = Get-AzStorageBlobCopyState -Container $Container.Name -Blob $Snapshot.Name -Context $DestinationContext -WaitForComplete).Status -ne "Success") { 
                        Write-Log -Message "Copy status is $($State.Status), Bytes copied: $($State.BytesCopied) of: $($State.TotalBytes). Sleeping for $($Sleep) seconds" -Level Info
                        Start-Sleep -Seconds $Sleep 
                    }
                    Write-Log -Message "Copy status is $($State.Status). Snapshot transfer to storage account container complete" -Level Info
                }
                catch {
                    Write-Log -Message "Failed to transfer snapshot: $($Snapshot.Name)" -Level Warn
                    Write-Log -Message $_ -Level Warn
                    Break
                }

                #----------------------------------------------------------------------------
                # Get the full URI to the blob
                #----------------------------------------------------------------------------
                $osDiskVhdUri = ($DestinationContext.BlobEndPoint + $Container.Name + "/" + $Snapshot.Name)

                #----------------------------------------------------------------------------
                # Build up the snapshot configuration, using the target storage account's resource ID
                #----------------------------------------------------------------------------
                $SnapshotConfig = New-AzSnapshotConfig -AccountType $Snapshot.Sku.Name -OsType $SnapShot.OsType -Location $TargetRegion -CreateOption "Import" -SourceUri $osDiskVhdUri -StorageAccountId $StorageAccount.Id

                #----------------------------------------------------------------------------
                # Create the new snapshot in the target region
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Copying snapshot $($Snapshot.Name) in source Resource Group: $($SourceResourceGroup) in source Subscription $($SourceSubscriptionID) as $($Snapshot.Name) in target Resource Group $($TargetResourceGroup) in target Subscription: $($TargetSubscriptionID)" -Level Info
                    $NewSnap = New-AzSnapshot -ResourceGroupName $TargetResourceGroup -SnapshotName $Snapshot.Name -Snapshot $SnapshotConfig -ErrorAction Stop
                    Write-Log -Message "Successfully copied snapshot $($Snapshot.Name)" -Level Info
                }
                catch {
                    Write-Log -Message $_ -Level Warn
                }

                #----------------------------------------------------------------------------
                # Revoke SAS token
                #----------------------------------------------------------------------------
                SelectSourceSubscription

                try {
                    Write-Log -Message "Attempting to revoke snapshot access for snapshot $($Snapshot.Name)" -Level Info
                    Revoke-AzSnapShotAccess -ResourceGroupName $SourceResourceGroup -SnapshotName $Snapshot.Name | Out-Null
                    Write-Log -Message "Successfully revoked snapshot access for snapshot $($Snapshot.Name)" -Level Info
                }
                catch {
                    Write-Log -Message "Failed to remove SAS Token" -Level Warn
                    Write-Log -Message $_ -Level Warn
                    StopIteration
                    Exit 1
                }

            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }
        #endregion

        #region cleanup storage account
        #---------------------------------------------------------------------------
        # Cleanup Storage Account
        #---------------------------------------------------------------------------
        SelectTargetSubscription

        try {
            Write-Log -Message "Attempting to remove storage container: $($Container.Name)" -Level Info
            $Container | Remove-AzStorageContainer -Force -ErrorAction Stop
            Write-Log -Message "Attempting to remove storage account: $($StorageAccount.StorageAccountName)" -Level Info
            $StorageAccount | Remove-AzStorageAccount -Force -ErrorAction Stop
            Write-Log -Message "Successfully: removed storage account: $($StorageAccount.StorageAccountName)" -Level Info
        }
        catch {
            Write-Log -Message "Failed to remove storage account: $($StorageAccount.StorageAccountName)" -Level Warn
            Write-Log -Message $_ -Level Warn
        }
        #endregion
    }
    else {
        Write-Log -Message "There are no snaphots matching the replication criteria" -Level Info
    }
}

#----------------------------------------------------------------------------
# Same Subscription Different Region
#----------------------------------------------------------------------------
if ($mode -eq "SameSubDifferentRegion") {

    GetTargetSubscriptionSnapshots

    #----------------------------------------------------------------------------
    # Remove snapshot from $SourceSnapshots if already exists in target
    #----------------------------------------------------------------------------
    $NewSourceSnaps = @()

    foreach ($Snapshot in $SourceSnapshots) {
        if ($Snapshot.Name -in $TargetSnapshots.Name) {
            Write-Log -Message "$($snapshot.Name) already exists in the target Subscription. Removing from processing" -Level Info
        }
        else {
            if ($null -ne $snapshot.Name) {
                Write-Log -Message "$($snapshot.Name) added to processing list" -Level Info
                $NewSourceSnaps = $NewSourceSnaps += $Snapshot    
            }
            else {
                Write-Log -Message "Specified snapshot not found. Check input name" -Level Warn
            }
        }
    }

    $SourceSnapshots = $NewSourceSnaps
    Write-Log -Message "There are now $(($SourceSnapShots).Count) snapshots in the source Resource Group: $($SourceResourceGroup) for replication" -Level Info

    if ($SourceSnapshots.Count -gt 0) {

        #region storage accounts
        #----------------------------------------------------------------------------
        # Handle Storage Accounts
        #----------------------------------------------------------------------------
        Write-Log -Message "Setting storage account details" -Level Info
        $StorageAccountName = "rep" + [system.guid]::NewGuid().tostring().replace('-', '').substring(1, 18)
        Write-Log -Message "Storage account name is: $($StorageAccountName)" -Level Info

        try {
            #----------------------------------------------------------------------------
            # Create the context for the storage account which will be used to copy the snapshot to the storage account
            #----------------------------------------------------------------------------
            Write-Log -Message "Attempting to create storage account: $($StorageAccountName)" -Level Info
            $StorageAccount = New-AzStorageAccount -ResourceGroupName $TargetResourceGroup -Name $StorageAccountName -SkuName "Standard_LRS" -Location $TargetRegion -ErrorAction Stop
            $DestinationContext = $StorageAccount.Context

            Write-Log -Message "Attempting to create storage account container: $($StorageAccountName)" -Level Info
            $Container = New-AzStorageContainer -Name $StorageAccountName -Permission "Container" -Context $DestinationContext -ErrorAction Stop
            Write-Log -Message "Successfully: created storage account: $($StorageAccountName) and container: $($StorageAccountName)" -Level Info
        }
        catch {
            Write-Log -Message "Failed to create storage account for transfer. Exit script" -Level Warn
            Write-Log -Message $_ -Level Warn
            StopIteration
            Exit 1
        }
        #endregion

        #region replicate snapshots
        foreach ($Snapshot in $SourceSnapshots) {
            try {

                Write-Log -Message "Copying snapshot $($Snapshot.Name) in source Resource Group: $($SourceResourceGroup) in source Subscription $($SourceSubscriptionID) as $($Snapshot.Name) in target Resource Group $($TargetResourceGroup)" -Level Info
                
                #----------------------------------------------------------------------------
                # Create a Shared Access Signature (SAS) for the source snapshot
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Attempting to create and retrieve SAS URI for snapshot $($Snapshot.Name)" -Level Info
                    $SnapSasUrl = Grant-AzSnapShotAccess -ResourceGroupName $SourceResourceGroup -SnapshotName $Snapshot.Name -DurationInSecond 3600 -Access Read -ErrorAction Stop
                    Write-Log -Message "Successfully created SAS URI for snapshot $($Snapshot.Name)"
                }
                catch {
                    Write-Log -Message $_ -Level Warn
                    Break
                }

                #----------------------------------------------------------------------------
                # Copy the Snapshot to the storage account
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Attempting snapshot transfer for: $($Snapshot.Name) to storage account container" -Level Info
                    Start-AzStorageBlobCopy -AbsoluteUri $snapSasUrl.AccessSAS -DestContainer $Container.Name -DestContext $DestinationContext -DestBlob $Snapshot.Name -ErrorAction Stop | Out-null
                    $Sleep = "30"
                    while (($State = Get-AzStorageBlobCopyState -Container $Container.Name -Blob $Snapshot.Name -Context $DestinationContext -WaitForComplete).Status -ne "Success") { 
                        Write-Log -Message "Copy status is $($State.Status), Bytes copied: $($State.BytesCopied) of: $($State.TotalBytes). Sleeping for $($Sleep) seconds" -Level Info
                        Start-Sleep -Seconds $Sleep 
                    }
                    Write-Log -Message "Copy status is $($State.Status). Snapshot transfer to storage account container complete" -Level Info
                }
                catch {
                    Write-Log -Message "Failed to transfer snapshot: $($Snapshot.Name)" -Level Warn
                    Write-Log -Message $_ -Level Warn
                    Break
                }

                #----------------------------------------------------------------------------
                # Get the full URI to the blob
                #----------------------------------------------------------------------------
                $osDiskVhdUri = ($DestinationContext.BlobEndPoint + $Container.Name + "/" + $Snapshot.Name)

                #----------------------------------------------------------------------------
                # Build up the snapshot configuration, using the target storage account's resource ID
                #----------------------------------------------------------------------------
                $SnapshotConfig = New-AzSnapshotConfig -AccountType $Snapshot.Sku.Name -OsType $SnapShot.OsType -Location $TargetRegion -CreateOption "Import" -SourceUri $osDiskVhdUri -StorageAccountId $StorageAccount.Id
                
                #----------------------------------------------------------------------------
                # Create the new snapshot in the target region
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Copying snapshot $($Snapshot.Name) in source Resource Group: $($SourceResourceGroup) in source Subscription $($SourceSubscriptionID) as $($Snapshot.Name) in target Resource Group $($TargetResourceGroup)" -Level Info
                    $NewSnap = New-AzSnapshot -ResourceGroupName $TargetResourceGroup -SnapshotName $Snapshot.Name -Snapshot $SnapshotConfig -ErrorAction Stop
                    Write-Log -Message "Successfully copied snapshot $($Snapshot.Name)" -Level Info
                }
                catch {
                    Write-Log -Message $_ -Level Warn
                }

                #----------------------------------------------------------------------------
                # Revoke SAS token
                #----------------------------------------------------------------------------
                try {
                    Write-Log -Message "Attempting to revoke snapshot access for snapshot $($Snapshot.Name)" -Level Info
                    Revoke-AzSnapShotAccess -ResourceGroupName $SourceResourceGroup -SnapshotName $Snapshot.Name | Out-Null
                    Write-Log -Message "Successfully revoked snapshot access for snapshot $($Snapshot.Name)" -Level Info
                }
                catch {
                    Write-Log -Message "Failed to remove SAS Token" -Level Warn
                    Write-Log -Message $_ -Level Warn
                    StopIteration
                    Exit 1
                }
            }
            catch {
                Write-Log -Message $_ -Level Warn
            }
        }
        #endregion

        #region cleanup storage account
        #---------------------------------------------------------------------------
        # Cleanup Storage Account
        #---------------------------------------------------------------------------
        try {
            Write-Log -Message "Attempting to remove storage container: $($Container.Name)" -Level Info
            $Container | Remove-AzStorageContainer -Force -ErrorAction Stop
            Write-Log -Message "Attempting to remove storage account: $($StorageAccount.StorageAccountName)" -Level Info
            $StorageAccount | Remove-AzStorageAccount -Force -ErrorAction Stop
            Write-Log -Message "Successfully: removed storage account: $($StorageAccount.StorageAccountName)" -Level Info
        }
        catch {
            Write-Log -Message "Failed to remove storage account: $($StorageAccount.StorageAccountName)" -Level Warn
            Write-Log -Message $_ -Level Warn
        }
        #endregion
    }
    else {
        Write-Log -Message "There are no Snaphots matching the replication criteria" -Level Info
    }
}

#---------------------------------------------------------------------------
#Sync Mode
#---------------------------------------------------------------------------
if ($Sync -eq "Sync") {

    if ($mode -eq "SameSubDifferentRegion") {
        if ($UseTagFiltering -eq "True") {
            Write-Log -Message "Getting Snapshots in source Subscription in Resource Group: $($SourceResourceGroup) with Tag: $($Tag) with value: $($ReplicateTrigger)" -Level Info
            $SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup | Where-Object { $_.Tags.Keys -eq $Tag -and $_.Tags.Values -contains $ReplicateTrigger }
        } 
        else {
            Write-Log -Message "Getting Snapshots in source Subscription in Resource Group: $($SourceResourceGroup)" -Level Info
            $SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup
        }
        Write-Log -Message "There are $(($SourceSnapshots).Count) snapshots in the source Resource Group: $($SourceResourceGroup) targeted for replication"

        GetTargetSubscriptionSnapshots

        foreach ($Snapshot in $TargetSnapshots) {
            if ($Snapshot.Name -notin $SourceSnapshots.Name) {
                Write-Log -Message "$($Snapshot.Name) does not exist in the source Resource Group and is targeted for deletion in the target" -Level Info
                try {
                    Write-Log -Message "Deleting snapshot $($Snapshot.Name) from the target Resource Group" -Level Info
                    Remove-AzSnapshot -ResourceGroupName $TargetResourceGroup -SnapshotName $Snapshot.Name -Force | Out-Null
                    Write-Log -Message "Successfully deleted snapshot $($Snapshot.Name)" -Level Info
                }
                catch {
                    Write-Log -Message $_ -Level Warn
                    Write-Log -Message "Failed to delete snapshot: $($Snapshot.Name)" -Level Warn
                }
            }
            else {
                Write-Log -Message "$($Snapshot.Name) exists in both source and destination" -Level Info
            }
        }
    }
    elseif ($mode -eq "DifferentSubSameRegion" -or $mode -eq "DifferentSubDifferentRegion") {

        SelectSourceSubscription

        #GetSourceSubscriptionSnapshots

        if ($UseTagFiltering -eq "True") {
            Write-Log -Message "Getting Snapshots in source Subscription in Resource Group: $($SourceResourceGroup) with Tag: $($Tag) with value: $($ReplicateTrigger)" -Level Info
            $SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup | Where-Object { $_.Tags.Keys -eq $Tag -and $_.Tags.Values -contains $ReplicateTrigger }
        } 
        else {
            Write-Log -Message "Getting Snapshots in source Subscription in Resource Group: $($SourceResourceGroup)" -Level Info
            $SourceSnapshots = Get-AzSnapShot -ResourceGroupName $SourceResourceGroup
        }
        Write-Log -Message "There are $(($SourceSnapshots).Count) snapshots in the source Resource Group: $($SourceResourceGroup) targeted for replication"

        SelectTargetSubscription

        GetTargetSubscriptionSnapshots

        foreach ($Snapshot in $TargetSnapshots) {
            if ($Snapshot.Name -notin $SourceSnapshots.Name) {
                Write-Log -Message "$($Snapshot.Name) does not exist in the source Resource Group and is targeted for deletion in the target" -Level Info
                try {
                    Write-Log -Message "Deleting snapshot $($Snapshot.Name) from the target Resource Group" -Level Info
                    Remove-AzSnapshot -ResourceGroupName $TargetResourceGroup -SnapshotName $Snapshot.Name -Force | Out-Null
                    Write-Log -Message "Successfully deleted snapshot $($Snapshot.Name)" -Level Info
                }
                catch {
                    Write-Log -Message $_ -Level Warn
                    Write-Log -Message "Failed to delete snapshot: $($Snapshot.Name)" -Level Warn
                }
            }
            else {
                Write-Log -Message "$($Snapshot.Name) exists in both source and destination" -Level Info
            }
        }
    }
}

StopIteration
Exit 0
#endregion