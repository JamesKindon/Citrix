<#
.SYNOPSIS
    Loops through a list of Azure subscriptions searching for Citrix Identity Disks and attempts to convert them to the specified Disk Sku
.DESCRIPTION
    The script is designed to run as an Azure Runbook, proactively looking for cost savings by converting identity disks (often at premium) to a cheaper Sku (Standard SSD for example)
.NOTES
    Ensure that the automation account executing the runbook has appropriate access to the list of subscriptions (Contributor)
    Requires Az.Accounts, Az.Resources, Az.Compute Modules imported and available in automation account
    If $isAzureRunBook is set to false, it is assumed you are executing this code under the context of a user who is authenticated to Azure, and has sufficient access to the specified subscriptions
    19.10.2020 - James Kindon - Initial Release
    25.10.2020 - James Kindon - Added Resource Group targeting
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$isAzureRunbook = "true", #Set to true if using an Azure Runbook, this will move the authentication model to the Automation Account

    [Parameter(Mandatory = $false)]
    [ValidateSet("SystemIdentity","RunAs")]
    [string]$RunBookAuthModel = "SystemIdentity", #try to avoid using runas accounts as per Microsoft updated guidance. Use a system managed identity instead

    [Parameter(Mandatory = $false)]
    [string]$DiskNameFilter = "*-IdentityDisk-*", #Disk name filter to match
    
    [Parameter(Mandatory = $false)]
    [string]$DiskSearchSku = "Premium_LRS", #The Source Sku for disks. StandardSSD_LRS, Premium_LRS, Standard_LRS

    [Parameter(Mandatory = $false)]
    [string]$DiskTargetSku = "StandardSSD_LRS", #The Target Sku for disks. StandardSSD_LRS, Premium_LRS, Standard_LRS

    [Parameter(Mandatory = $false)]
    [Array]$SubscriptionList = ("Sub-TBD1","Sub-TBD2"), #Array of Subscription ID's to query. Subscription ID. Not name

    [Parameter(Mandatory = $false)]
    [Array]$ResourceGroups = ("") #Array of Resource Groups to query, only used to limit scope as required. Leave empty ("") to target subscription

)
#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================
function ConvertIdentityDisks {
    if ($ResourceGroups -ne "") {
        $IdentityDisks = Get-AzDisk -ResourceGroupName $RG.ResourceGroupName | Where-Object { $_.Name -like $DiskNameFilter }
    }
    else {
        $IdentityDisks = Get-AzDisk | Where-Object { $_.Name -like $DiskNameFilter }
    }
    
    Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($IdentityDisks.Count) Disks found matching name filter: $($DiskNameFilter)"
    $Global:TotalDiskCount += $IdentityDisks.Count

    $TargetedDisks = $IdentityDisks | Where-Object { $_.Sku.Name -eq $DiskSearchSku }
    Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($TargetedDisks.Count) Disks found matching Sku: $($DiskSearchSku)"
    $Global:TotalConversionDiskCount += $TargetedDisks.Count

    $UnattachedDisks = $TargetedDisks | Where-Object { $_.DiskState -eq "unattached" -or $_.DiskState -eq "reserved" }
    Write-Output "Subscription $Subscription ($($AzureContext.Name)): There are $($UnattachedDisks.Count) Disks unattached which can be converted"
    $Global:TotalUnattachedDiskCount += $UnattachedDisks.Count

    $AttachedDisks = $TargetedDisks | Where-Object { $_.DiskState -eq "attached" }
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

function ProcessResourceGroups {
    if ($ResourceGroups -ne "") {
        foreach ($RG in $ResourceGroups) {
            try {
                Write-Output "Subscription $Subscription ($($AzureContext.Name)): Processing Resource Group: $RG"
                $RG = Get-AzResourceGroup -Name $RG -ErrorAction Stop
                #Process Disks
                ConvertIdentityDisks
            }
            catch {
                Write-Warning "$($_) Resource Group: $($RG) not found in subscription: $($AzureContext.Name). Searching additional Subscriptions if specified"
            }
        }
    }
    else {
        #Process all disks
        ConvertIdentityDisks
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
Write-Output "Input: Setting target Sku for disks to: $DiskTargetSku"
Write-Output "Input: Searching across $($SubscriptionList.Count) Subscriptions"
if ($Resourcegroups -ne "") {
    Write-Output "Input: Searching across $($ResourceGroups.Count) Resource Groups"
}
else {
    Write-Output "Input: Resource Group filtering not applied"
}

$Global:TotalDiskCount = 0 #Total disk count across all Subscriptions matching name criteria
$Global:TotalConversionDiskCount = 0 #Total disk count matching the conversion critera
$Global:TotalSuccessCount = 0 #Total success count across all Subscriptions
$Global:TotalFailCount = 0 #Total fail count across all Subscriptions
$Global:TotalUnattachedDiskCount = 0 #Total number of unattached disks 
$Global:TotalAttachedDiskCount = 0 #Total number of attached disks


#region Authentication
# Check to see if flagged as a runbook, if true, process accordingly

#----------------------------------------------------------------------------
# Handle Authentication - Runbook legacy, Modern or none
#----------------------------------------------------------------------------
if ($isAzureRunbook -eq "true" -and $RunBookAuthModel -eq "RunAs") {
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
elseif ($isAzureRunbook -eq "true" -and $RunBookAuthModel -eq "SystemIdentity") {
    try {
        Write-Output "Logging in to Azure..."
        #https://docs.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation#authenticate-access-with-system-assigned-managed-identity
        # Ensures you do not inherit an AzContext in your runbook
        Disable-AzContextAutosave -Scope Process
    
        # Connect to Azure with system-assigned managed identity
        $AzureContext = (Connect-AzAccount -Identity).context
    
        # set and store context
        $AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext -ErrorAction Stop
    
        Write-Output "Authenticated"
    }
    catch {
        Write-Warning $_
        Write-Warning "Failed to Authenticate. Exit Script."
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
#endregion

# loop through subscriptions
foreach ($Subscription in $SubscriptionList) {
    try {
        Write-Output "Setting Azure Context to $Subscription"
        $AzureContext = Get-AzSubscription -SubscriptionId $Subscription
        $null = Set-AzContext $AzureContext
        Write-Output "Set Azure Context to $($AzureContext.SubscriptionId) ($($AzureContext.Name))"
        ProcessResourceGroups
    }
    catch {
        Write-Warning "Failed to set Azure Context"
        Write-Warning $_
        Break
    }
}

Write-Output "Total: Processed $($SubscriptionList.Count) Subscriptions"
if ($ResourceGroups -ne "") {
    Write-Output "Total: Processed $($ResourceGroups.Count) Resource Groups"
}
Write-Output "Total: There were a total of $TotalDiskCount disks across $($SubscriptionList.Count) Subscriptions which match the specified name criteria"
Write-Output "Total: There were a total of $TotalConversionDiskCount disks across $($SubscriptionList.Count) Subscriptions which match the conversion criteria"
Write-Output "Total: There were a total of $TotalUnattachedDiskCount disks across $($SubscriptionList.Count) Subscriptions which were capable of being converted"
Write-Output "Total: There were a total of $TotalAttachedDiskCount disks across $($SubscriptionList.Count) Subscriptions which were capable but were in use"
Write-Output "Total: Successfully converted $TotalSuccessCount disks across $($SubscriptionList.Count) Subscriptions"
Write-Output "Total: Failed to convert $TotalFailCount disks across $($SubscriptionList.Count) Subscriptions"

Stop-Stopwatch
Write-Output "Script Completed"
Exit 0
#endregion
