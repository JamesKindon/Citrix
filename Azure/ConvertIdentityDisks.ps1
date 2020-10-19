<#
.SYNOPSIS
    Loops through a list of Azure subscriptions searching for Citrix Identity Disks and attempts to convert them to the specified Disk Sku
.DESCRIPTION
    The script is designed to run as an Azure Runbook, proactively looking for cost savings by converting identity disks (often at premium) to a cheaper Sku (Standard SSD for example)
.NOTES
    Ensure that the automation account executing the runbook has appropriate access to the list of subscriptions (Contributor)
    Requires Az.Accounts, Az.Compute Modules imported and available in automation account
    If $isAzureRunBook is set to false, it is assumed you are executing this code under the context of a user who is authenticated to Azure, and has sufficient access to the specified subscriptions
    19.10.2020 - James Kindon Initial Release
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$isAzureRunbook = "true", #Set to true if using an Azure Runbook, this will move the authentication model to the Automation Account

    [Parameter(Mandatory = $false)]
    [string]$DiskNameFilter = "*-IdentityDisk-*", #Disk name filter to match
    
    [Parameter(Mandatory = $false)]
    [string]$DiskSearchSku = "Premium_LRS", #The Source Sku for disks. StandardSSD_LRS, Premium_LRS, Standard_LRS

    [Parameter(Mandatory = $false)]
    [string]$DiskTargetSku = "StandardSSD_LRS", #The Target Sku for disks. StandardSSD_LRS, Premium_LRS, Standard_LRS

    [Parameter(Mandatory = $false)]
    [Array]$SubscriptionList = ("SubID-1","SubID-2") #Array of Subscription ID's to query. Subscription ID. Not name

)
#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================
function ConvertIdentityDisks {
    $IdentityDisks = Get-AzDisk | Where-Object { $_.Name -like $DiskNameFilter }

    Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($IdentityDisks.Count) Disks found matching name filter: $($DiskNameFilter)"

    $TargetedDisks = $IdentityDisks | Where-Object { $_.Sku.Name -eq $DiskSearchSku }
    Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($TargetedDisks.Count) Disks found matching Sku: $($DiskSearchSku)"

    $UnattachedDisks = $TargetedDisks | Where-Object { $_.DiskState -eq "unattached" }
    Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($UnattachedDisks.Count) Disks unattached which can be converted"
    $Global:TotalUnattachedDiskCount += $UnattachedDisks.Count

    $AttachedDisks = $TargetedDisks | Where-Object { $_.DiskState -eq "reserved" }
    if ($AttachedDisks.Count -gt 0) {
        Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($AttachedDisks.Count) Disks attached which cannot be converted"
        $Global:TotalAttachedDiskCount += $AttachedDisks.Count
    }

    $StartCount = 1
    $FailCount = 0

    if ($UnattachedDisks.Count -gt 0) {
        Write-Output "Processing $($UnattachedDisks.Count) Disks"
        foreach ($Disk in $UnattachedDisks) {
            Write-Output "Subscription $Subscription ($($AzureContext.Name)): Processing Disk $StartCount of $($UnattachedDisks.Count): $($Disk.Name)"
            try {
                $null = New-AzDiskUpdateConfig -SkuName $DiskTargetSku | Update-AzDisk -ResourceGroupName $Disk.ResourceGroupName -DiskName $Disk.Name -ErrorAction Stop
                Write-Output "Subscription $Subscription ($($AzureContext.Name)): Successfully converted Disk $($Disk.Name) from $($Disk.Sku.Name) to $($DiskTargetSku)"
                $StartCount ++
                $Global:TotalSuccessCount ++
            }
            catch {
                Write-Warning "Subscription $Subscription ($($AzureContext.Name)): Failed to alter Disk: $($Disk.Name)"
                Write-Warning $_
                $FailCount ++
                $Global:TotalFailCount ++
            }
        }
    }
    else {
        Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are no disks to process"
    }

    if ($StartCount -gt 1) {
        $SuccessCount = $StartCount - 1
        Write-Output "Subscription $Subscription ($($AzureContext.Name)): Successfully converted $($SuccessCount) Disks"
    }
    if ($FailCount -gt 0) {
        Write-Output "Subscription $Subscription ($($AzureContext.Name)): Failed to convert $($FailCount) Disks"
    }
}

function Start-Stopwatch {
    Write-Output "Starting Timer"
    $Global:StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
}

function Stop-Stopwatch {
    Write-Output "Stopping Timer"
    $StopWatch.Stop()
    if ($StopWatch.Elapsed.TotalSeconds -le 1) {
        Write-Output "Script processing took $($StopWatch.Elapsed.TotalMilliseconds) ms to complete."
    }
    else {
        Write-Output "Script processing took $($StopWatch.Elapsed.TotalSeconds) seconds to complete."
    }
}

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
Start-Stopwatch

Write-Output "Input: Searching for disks with naming pattern: $DiskNameFilter"
Write-Output "Input: Searching for disks with Sku: $DiskSearchSku"
Write-Output "Input: Setting target Sku for disks to: DiskTargetSku"
Write-Output "Input: Searching across $($SubscriptionList.Count) Subscriptions"

$Global:TotalSuccessCount = 0 #Total success count across all Subscriptions
$Global:TotalFailCount = 0 #Total fail count across all Subscriptions
$Global:TotalUnattachedDiskCount = 0 #Total number of unattached disks 
$Global:TotalAttachedDiskCount = 0 #Total number of attached disks

# Check to see if flagged as a runbook, if true, process accordingly
if ($isAzureRunbook -eq "true") {
    # https://docs.microsoft.com/en-us/azure/automation/learn/automation-tutorial-runbook-textual-powershell#step-5---add-authentication-to-manage-azure-resources
    # Ensures you do not inherit an AzContext in your runbook
    Disable-AzContextAutosave –Scope Process

    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    write-output "Logging in to Azure..."

    # Wrap authentication in retry logic for transient network failures
    $logonAttempt = 0
    try {
        while (!($connectionResult) -and ($logonAttempt -le 10)) {
            $LogonAttempt++
            # Logging in to Azure...
            $connectionResult = Connect-AzAccount `
                -ServicePrincipal `
                -Tenant $connection.TenantID `
                -ApplicationId $connection.ApplicationID `
                -CertificateThumbprint $connection.CertificateThumbprint
    
            Start-Sleep -Seconds 30
        }    
    }
    catch {
        if (!$connection) {
            $ErrorMessage = "Connection $connection not found."
            throw $ErrorMessage
        }
        else {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }    
}

# loop through subscriptions
foreach ($Subscription in $SubscriptionList) {
    try {
        Write-Output "Setting Azure Context to $Subscription"
        $AzureContext = Get-AzSubscription -SubscriptionId $Subscription
        $null = Set-AzContext $AzureContext
        Write-Output "Set Azure Context to $($AzureContext.SubscriptionId) ($($AzureContext.Name))"
        ConvertIdentityDisks    
    }
    catch {
        Write-Warning "Failed to set Azure Context"
        Write-Warning $_
        Break
    }
}

Write-Output "Total: Processed $($SubscriptionList.Count) Subscriptions"
Write-Output "Total: There were a total of $TotalUnattachedDiskCount disks across $($SubscriptionList.Count) Subscriptions which were capable of being converted"
Write-Output "Total: There were a total of $TotalAttachedDiskCount disks across $($SubscriptionList.Count) Subscriptions which were capable but could not be converted"
Write-Output "Total: Successfully converted $TotalSuccessCount disks across $($SubscriptionList.Count) Subscriptions"
Write-Output "Total: Failed to convert $TotalFailCount disks across $($SubscriptionList.Count) Subscriptions"

Stop-Stopwatch
Write-Output "Script Completed"
Exit 0
#endregion
