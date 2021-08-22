<#
.SYNOPSIS
    Loops through a list of Azure Resource Groups and Subscriptions, grabs the virtual machines and assigns a UserAssigned managed identity   
.DESCRIPTION
    The script is designed to run as an Azure Runbook. Given the use scenario, you may need to have multiple schedules defined (to allow more iterations to catch machines prior to user load)
.NOTES
    Requires Az.Accounts, Az.Resources, Az.Compute, Modules imported and available in automation account
    If $isAzureRunBook is set to false, it is assumed you are executing this code under the context of a user who is authenticated to Azure, and has sufficient access to the specified subscriptions
    This Script is desiged to compliment Citrix MCS deployments where on-demand provisioning is used, however is not limited to that use case

    12.08.2021 - James Kindon Initial Release
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$isAzureRunbook = "true", #Set to true if using an Azure Runbook, this will move the authentication model to the Automation Account

    [Parameter(Mandatory = $false)]
    [Array]$ResourceGroups = ("RG-TBD1","RG-TBD2"), #Array of Resource Groups to query

    [Parameter(Mandatory = $false)]
    [Array]$SubscriptionList = ("Sub-TBD1","Sub-TBD2"), #Array of Subscription ID's to query. Subscription ID. Not name

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityID = "/subscriptions/--SUB-ID-Here--/resourceGroups/--RG-HERE--/providers/Microsoft.ManagedIdentity/userAssignedIdentities/MI-Kindon-Demo", #Managed Identity ID

    [Parameter(Mandatory = $false)]
    [string] $IdentityType = "UserAssigned",

    [Parameter(Mandatory = $false)]
    [Array]$ExcludedVMList = ("") #Array of VM names to NOT process

)
#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================
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

function AssignManagedIdentity {
    foreach ($Name in $ExcludedVMList) {
        if ($VM.Name -like $Name) {
            Write-Warning "$($VM.Name) has been matched to an exclusion pattern of $Name. $($VM.Name) will not be processed"
            $Global:TotalIgnoredCount ++
        }
        else {
            try {
                $null = Update-AzVM -VM $VM -ResourceGroupName $RG -IdentityType $IdentityType -IdentityID $ManagedIdentityID -ErrorAction Stop
                Write-Output "VM: $($VM.Name) successfully assigned managed identity: $(Split-Path -leaf $ManagedIdentityID)"
                $Global:TotalSuccessCount ++
            }
            catch {
                Write-Warning "$($_)"
                $Global:TotalFailCount ++
            }
        }
    }
} 

function ProcessResourceGroups {
    foreach ($RG in $ResourceGroups) {
        try {
            $null = Get-AzResourceGroup -Name $RG -ErrorAction Stop
            Write-Output "Subscription $Subscription ($($AzureContext.Name)): Processing Resource Group: $RG"

            $VMs = Get-AzVM -ResourceGroupName $RG -ErrorAction Stop
            if ($null -ne $VMs) {
                Write-Output "Processing $($VMs.Count) VMs"
                foreach ($VM in $VMs) {
                    $VM = Get-AzVM -ResourceGroupName $RG -Name $VM.Name

                    if ($VM.Identity.UserAssignedIdentities.Keys -Contains $ManagedIdentityID) {
                        Write-Output "VM: $($VM.Name) has the correct managed identity. No action required"
                        $Global:TotalIgnoredCount ++ 
                    }
                    else {
                        Write-Output "VM: $($VM.Name) does not have the correct managed identity. Processing"
                        AssignManagedIdentity
                    }
                }
            }
            else {
                Write-Output "There are no VMs found in Resource Group: $($RG). Skipping"
            }
        }
        catch {
            Write-Warning "$($_) Resource Group: $($RG) not found in subscription: $($AzureContext.Name). Searching additional Subscriptions if specified"
        }
    }
}

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
Start-Stopwatch

Write-Output "Input: Searching across $($SubscriptionList.Count) Subscriptions"
Write-Output "Input: Searching across $($ResourceGroups.Count) Resource Groups"

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

$Global:TotalSuccessCount = 0
$Global:TotalFailCount = 0
$Global:TotalIgnoredCount = 0

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
Write-Output "Total: Processed $($ResourceGroups.Count) Resource Groups"
Write-Output "Total: Successfully assigned managed identities to $Global:TotalSuccessCount machines across $($SubscriptionList.Count) Subscriptions and $($ResourceGroups.Count) Resource Groups"
Write-Output "Total: Failed to assign managed identities to $Global:TotalFailCount VMs across $($SubscriptionList.Count) Subscriptions and $($ResourceGroups.Count) Resource Groups"
Write-Output "Total: Ignored $Global:TotalIgnoredCount virtual machines across $($SubscriptionList.Count) Subscriptions and $($ResourceGroups.Count) Resource Groups"

Stop-Stopwatch
Write-Output "Script Completed"
Exit 0
#endregion
