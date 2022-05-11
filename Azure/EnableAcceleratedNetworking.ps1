<#
.SYNOPSIS
    Loops through a list of Azure Resource Groups and Subscriptions, searching for network interfaces that are not enabled for accelerated networking    
.DESCRIPTION
    The script is designed to run as an Azure Runbook, proactively looking for network interfaces and enabling accelerated networking if not attached
.NOTES
    Requires Az.Accounts, Az.Resources, Az.Compute, Az.Network Modules imported and available in automation account
    If $isAzureRunBook is set to false, it is assumed you are executing this code under the context of a user who is authenticated to Azure, and has sufficient access to the specified subscriptions
    This Script is desiged to compliment Citrix MCS deployments where on-demand provisioning is used, however is not limited to that use case
    WARNING: The only checks that are completed are those associated with the nic being attached to a machine, and the power state of that machine 
    WARNING: You need to ensure that the machine spec which consumes the NIC is capable of accelerated Networking else, you will not land in a happy place
    WARNING: You must specify the subscription ID and not the name
    26.10.2020 - James Kindon Initial Release
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
    [string]$RunBookAuthModel = "SystemIdentity", #try to avoind using runas accounts as per Microsoft updated guidance. Use a system managed identity instead

    [Parameter(Mandatory = $false)]
    [Array]$ResourceGroups = ("RG-TBD1","RG-TBD2"), #Array of Resource Groups to query

    [Parameter(Mandatory = $false)]
    [Array]$SubscriptionList = ("Sub-ID-TBD1","Sub-ID-TBD2"), #Array of Subscription ID's to query. Subscription ID. Not name

    [Parameter(Mandatory = $false)]
    [Array]$ExcludedNameList = ("") #Array of NIC names to NOT process, Supports wildcard name patterns

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

function ConvertNIC {
    try {
        Write-Output "Network Interface: Attempting to convert $($NIC.Name) accelerated networking state"
        $nic = Get-AzNetworkInterface -Name $NIC.Name -ErrorAction Stop
        foreach ($Name in $ExcludedNameList) {
            if ($NIC.Name -like $Name) {
                Write-Warning "$($NIC.Name) has been matched to an exclusion pattern of $Name. $($NIC.Name) will not be processed"
                $Global:TotalIgnoredCount ++
            }
            else {
                $nic.EnableAcceleratedNetworking = $true
                $nic | Set-AzNetworkInterface -ErrorAction Stop | Out-Null
                Write-Output "Network Interface: $($NIC.Name) successfully converted"
                $Global:TotalSuccessCount ++
            }
        }
    }
    catch {
        $ErrorMessage = $_

        if ($ErrorMessage.Exception -like "*ErrorCode: VMSizeIsNotPermittedToEnableAcceleratedNetworking*") {
            Write-Warning "Failed to enable accelerated networking. Machine may not be on a supported Sku"
        }
        else {
            Write-Output $ErrorMessage.Exception
        }
    
        $Global:TotalFailCount ++
    } 
}

function ProcessResourceGroups {
    foreach ($RG in $ResourceGroups) {
        try {
            $null = Get-AzResourceGroup -Name $RG -ErrorAction Stop
            
            $NICS = Get-AzNetworkInterface -ResourceGroupName $RG
            $AcceleratedNICS = $NICS | Where-Object { $_.EnableAcceleratedNetworking -eq "true" }
            $StandardNICS = $NICS | Where-Object { $_.EnableAcceleratedNetworking -ne "true" }
            $UnattachedStandardNICS = $NICS | Where-Object { $_.EnableAcceleratedNetworking -ne "true" -and $_.VirtualMachine -eq $null }
            $AttachedStandardNICS = $NICS | Where-Object { $_.EnableAcceleratedNetworking -ne "true" -and $_.VirtualMachine -ne $null }
            $UnattachedAcceleratedNICS = $NICS | Where-Object { $_.EnableAcceleratedNetworking -eq "true" -and $_.VirtualMachine -eq $null }
            $AttachedAcceleratedNICS = $NICS | Where-Object { $_.EnableAcceleratedNetworking -eq "true" -and $_.VirtualMachine -ne $null }

            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($NICS.Count) network interfaces"
            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($AcceleratedNICS.Count) accelerated Network interfaces"
            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($StandardNICS.Count) standard Network interfaces"      
            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($UnattachedStandardNICS.Count) unattached standard Network interfaces"           
            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($AttachedStandardNICS.Count) attached standard Network interfaces"           
            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($UnattachedAcceleratedNICS.Count) unattached accelerated Network interfaces"           
            Write-Output "Resource Group: $RG in Subscription: $($AzureContext.Name) contains $($AttachedAcceleratedNICS.Count) attached accelerated Network interfaces"           
            
            $ProcessCount = 0
            $ProcessCount = $ProcessCount += $UnattachedStandardNICS.Count
            $ProcessCount = $ProcessCount += $AttachedStandardNICS.Count

            Write-Output "Processing a total of $ProcessCount Network Interfaces"

            foreach ($NIC in $UnattachedStandardNICS) {
                ConvertNIC
            }
            
            foreach ($NIC in $AttachedStandardNICS) {
                #Check VM and Convert            
                $VM = Get-AzNetworkInterface -Name $NIC.Name -ResourceGroupName $NIC.ResourceGroupName | Select-Object @{Name = "VMName"; Expression = { $_.VirtualMachine.Id.tostring().substring($_.VirtualMachine.Id.tostring().lastindexof('/') + 1) } }
                $PowerState = (Get-AzVM -Name $VM.VMName -status).PowerState
                
                if ($PowerState -ne "VM deallocated") {
                    Write-Output "Network Interface: $($NIC.Name) is attached to $($VM.VMName). This VM is in a powerstate of $($PowerState) and will be ignored"
                    #Can't process this, VM isnt deallocated, NIC in use
                    $Global:TotalIgnoredCount ++
                }
                else {
                    Write-Output "Network Interface: $($NIC.Name) is attached to $($VM.VMName). This VM is in a powerstate of $($PowerState) and will be processed"
                    #Can process this
                    ConvertNIC
                }
            }            
        }
        catch {
            Write-Warning "$($_) Resource Group $($RG) not found in subscription: $($AzureContext.Name). Searching additional Subscriptions if specified"
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
Write-Output "Total: Successfully converted $Global:TotalSuccessCount network interfaces across $($SubscriptionList.Count) Subscriptions and $($ResourceGroups.Count) Resource Groups"
Write-Output "Total: Failed to convert $Global:TotalFailCount network interfaces across $($SubscriptionList.Count) Subscriptions and $($ResourceGroups.Count) Resource Groups"
Write-Output "Total: Ignored $Global:TotalIgnoredCount network interfaces across $($SubscriptionList.Count) Subscriptions and $($ResourceGroups.Count) Resource Groups"

Stop-Stopwatch
Write-Output "Script Completed"
Exit 0
#endregion

