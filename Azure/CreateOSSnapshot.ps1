 
<#
.SYNOPSIS
    Creates on OS Disk snapshot for Citrix MCS use based on a provided VM name
.DESCRIPTION
    Creates on OS Disk snapshot for Citrix MCS use
.PARAMETER VMName
    VM to get the OS Disk from
.PARAMETER ResourceGroup
    Resource Group of the VM
.PARAMETER OSType
    Windows or Linux - Default is Windows
.PARAMETER CreateOption
    Snapshot Create option - Default is Copy
.PARAMETER DateFormat
    Date Format used for the Snap - Default is hhmm_dd-MM-yyyy
.PARAMETER TargetResourceGroup
    Store the Snapshot in a different resource group to the VM. Default is to use the VM Resource Group 
.EXAMPLE
    .\CreateOSSnapshot.ps1 -VMName Bob -ResourceGroup RG-Bob
.EXAMPLE
    .\CreateOSSnapshot.ps1 -VMName Bob -ResourceGroup RG-Bob -TargetResourceGroup RG-AlternateRG
.NOTES
#>
#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$VMName,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$OSType = "Windows",

    [Parameter(Mandatory = $false)]
    [string]$CreateOption = "Copy",

    [Parameter(Mandatory = $false)]
    [string]$DateFormat = "hhmm_dd-MM-yyyy",

    [Parameter(Mandatory = $false)]
    [string]$TargetResourceGroup
)
#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================

function SnapOSDisk {
    try {
        Write-Output "Taking Snapshot of $($VMName) OS Disk"
        New-AzSnapshot -ResourceGroupName $SnapResourceGroup -SnapshotName $SnapShotName -Snapshot $OSDiskSnapshotConfig -ErrorAction Stop
    }
    catch {
        $_
        Exit 1
    }    
}
#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
Write-Output "Getting VM Details for $($VMName)"
$VM = Get-AzVM -Name $VMName -ResourceGroupName $ResourceGroup

if (!($TargetResourceGroup)) {
    $SnapResourceGroup = $VM.ResourceGroupName
}
else {
    $SnapResourceGroup = $TargetResourceGroup
}

$SnapshotDisk = $VM.StorageProfile
$OSDiskSnapshotConfig = New-AzSnapshotConfig -SourceUri $SnapshotDisk.OsDisk.ManagedDisk.id -CreateOption $CreateOption -Location $VM.Location -OsType $OSType
$SnapShotName = "snap_$($VM.Name)_$(Get-Date -Format $DateFormat)"

$VMPowerState = (Get-AzVM -Name $VM.Name -Status).PowerState

if ($VMPowerState -eq "VM Running") {
    Write-Output "$($VM.Name) is Running and should be shutdown before snapshots are taken"

    $ShutdownConfirmation = Read-Host "Shutdown VM $($VM.Name)? Y, N or Q (Quit)"
    while ("Y", "N", "Q" -notcontains $ShutdownConfirmation) {
        $ShutdownConfirmation = Read-Host "Enter Y, N or Q (Quit)"
    }
    if ($ShutdownConfirmation -eq "Y") {
        Write-Output "Shutdown confirmation received. Proceeding with shutdown"
        try {
            Stop-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -ErrorAction Stop
            SnapOSDisk
        }
        catch {
            Write-Output $_
            Exit 1
        }
    }
    if ($ShutdownConfirmation -eq "N") { 
        Write-Output "Shutdown confirmation not confirmed. Exiting Script"
        exit 0
    }
    if ($ShutdownConfirmation -eq "Q") {
        Write-Output "Quit Selected. Exiting Script"
        exit 0
    }
}
else {
    SnapOSDisk
}

#endregion