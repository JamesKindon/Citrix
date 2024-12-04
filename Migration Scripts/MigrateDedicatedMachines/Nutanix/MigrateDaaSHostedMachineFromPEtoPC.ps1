<#
.SYNOPSIS
    This script will migrate a power-managed machine from a Prism Element based Hosting Connection, to a Citrix Managed PC Hosting Connection on Nutanix
.DESCRIPTION
    This script will is scoped to power-managed machines only, and does not support MCS or PVS based machines - these will be skipped.
.PARAMETER LogPath
    The path to the log file. Default is C:\Logs\MigrateDaaSHostedMachineFromPEtoPC.log
.PARAMETER LogRollover
    The number of days before the log file rolls over. Default is 5 days.
.PARAMETER Region
    The Citrix DaaS Tenant region. Default is US. Unlikely to need to be changed.
.PARAMETER CustomerID
    The Citrix DaaS Customer ID. Mandatory.
.PARAMETER ClientID
    The Citrix Cloud Secure Client ID. Can't be used with SecureClientFile.
.PARAMETER ClientSecret
    The Citrix Cloud Secure Client Secret. Can't be used with SecureClientFile.
.PARAMETER SecureClientFile
    The path to the Citrix Cloud Secure Client CSV. Can't be used with ClientSecret or ClientID.
.PARAMETER TargetMachineList
    An array of machines to target. Must be in the format of "Domain\MachineName". Can't be used with Catalogs.
.PARAMETER ExclusionList
    List of vm names to exclude. Must be in the format of "Domain\MachineName"
.PARAMETER TargetHostingConnectionName
    The Target Hosting Connection Name configured for Prism Central .
.PARAMETER ResetTargetHostingConnection
    Reset the target Hosting Connection.
.PARAMETER Catalogs
    An array of Catalogs to target all machines in.
.PARAMETER Whatif
    Will process in a whatif mode without actually altering anything
.EXAMPLE
    .\MigrateDaaSHostedMachineFromPEtoPC.ps1 -CustomerID "fake_cust_id" -SecureClientFile "C:\temp\secureclient.csv" -TargetHostingConnectionName "Nutanix-PC" -Catalogs "Catalog1","Catalog2" -Whatif
    This will migrate all machines in the specified Catalogs to the specified PC Hosting Connection in a planning mode.
.EXAMPLE
    .\MigrateDaaSHostedMachineFromPEtoPC.ps1 -CustomerID "fake_cust_id" -ClientID "fake_client_id" -ClientSecret "fake_client_secret" -TargetHostingConnectionName "Nutanix-PC" -TargetMachineList "Domain\Machine1","Domain\Machine2" -Whatif
    This will migrate the specified machines to the specified PC Hosting Connection in a whatif mode.
.EXAMPLE
    .\MigrateDaaSHostedMachineFromPEtoPC.ps1 -CustomerID "fake_cust_id" -SecureClientFile "C:\temp\secureclient.csv" -TargetHostingConnectionName "Nutanix-PC"  -Catalogs "Catalog1","Catalog2" -ExclusionList "Domain\Machine1" -ResetTargetHostingConnection
    This will migrate all machines in the specified Catalogs to the specified PC Hosting Connection, It will ecxlude the specified machine and reset the target Hosting Connection.
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\MigrateDaaSHostedMachineFromPEtoPC.log", # Where we log to

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # Number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [ValidateSet("AP-S", "EU", "US", "JP")]
    [string]$Region = "US", # The Citrix DaaS Tenant region
    
    [Parameter(Mandatory = $true)]
    [string]$CustomerID, # The Citrix DaaS Customer ID

    [Parameter(Mandatory = $false)]
    [string]$ClientID, # The Citrix Cloud Secure Client ID.

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret, # The Citrix Cloud Secure Client Secret.

    [Parameter(Mandatory = $false)]
    [string]$SecureClientFile, # Path to the Citrix Cloud Secure Client CSV.

    [Parameter(Mandatory = $false)]
    [Array]$TargetMachineList, # An array of machines to target.

    [Parameter(Mandatory = $false)]
    [array]$ExclusionList, # List of vm names to exclude.

    [Parameter(Mandatory = $true)]
    [String]$TargetHostingConnectionName, # The Target Hosting Connection Name pointing to the Target Nutanix Cluster.

    [Parameter(Mandatory = $false)]
    [Switch]$ResetTargetHostingConnection, # Reset the target Hosting Connection.

    [parameter(mandatory = $false)] # An array of Catalogs to switch ZoneID
    [array]$Catalogs,

    [Parameter(Mandatory = $false)]
    [switch]$Whatif # will process in a whatif mode without actually altering anythin

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

function Get-CCAccessToken {
    param (
        [string]$ClientID,
        [string]$ClientSecret
    )
    $TokenURL = "https://$($CloudUrl)/cctrustoauth2/root/tokens/clients"
    $Body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientID
        client_secret = $ClientSecret
    }
    $Response = Invoke-WebRequest $tokenUrl -Method POST -Body $Body -UseBasicParsing
    $AccessToken = $Response.Content | ConvertFrom-Json
    return $AccessToken.access_token
}

function Get-CCSiteID {
    param (
        [Parameter(Mandatory = $true)]
        [string] $AccessToken,
        [Parameter(Mandatory = $true)]
        [string] $CustomerID
    )
    $RequestUri = "https://$($CloudUrl)/cvadapis/me"
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$AccessToken";
        "Citrix-CustomerId" = $CustomerID;
    }
    $Response = Invoke-RestMethod -Uri $RequestUri -Method GET -Headers $Headers
    return $Response.Customers.Sites.Id
}

function ValidateCitrixCloud {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers

    )

    try {
        Write-Log -Message "[Cloud Site Handling] Testing Site Access" -Level Info
        #----------------------------------------------------------------------------------------------------------------------------
        # Set API call detail
        #----------------------------------------------------------------------------------------------------------------------------
        $Method = "Get"
        $RequestUri = "https://$($CloudUrl)/cvadapis/Sites/cloudxdsite"
        #----------------------------------------------------------------------------------------------------------------------------
        $cloud_site = Invoke-RestMethod -Method $Method -Headers $headers -Uri $RequestUri -ErrorAction Stop
        Write-Log -Message "[Cloud Site Handling] Retreived Cloud Site details for $($cloud_site.Name)" -Level Info
    }
    catch {
        Write-Log -Message "[Cloud Site Handling] Failed to retrieve cloud site details" -Level Warn
        Write-Log -Message $_ -Level Warn
        StopIteration
        Exit 1
    }
}

function Get-CVADVMListAPI {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $false)][string]$Catalog
    )

    $BrokerVMsTotal = [System.Collections.ArrayList] @()
    $ContinuationToken = $null

    do {
        #----------------------------------------------------------------------------------------------------------------------------
        # Set API call detail
        #----------------------------------------------------------------------------------------------------------------------------
        $Method = "Get"
        if ($Catalog) {
            $RequestUri = "https://$DDC/cvad/manage/MachineCatalogs/$($Catalog)/Machines?limit=1000"
            if ($ContinuationToken) {
                $RequestUri += "&continuationToken=$($ContinuationToken)"
            }
        } else {
            $RequestUri = "https://$DDC/cvad/manage/Machines?limit=1000"
            if ($ContinuationToken) {
                $RequestUri += "&continuationToken=$($ContinuationToken)"
            }
        }
        #----------------------------------------------------------------------------------------------------------------------------
        try {
            if (-not $ContinuationToken) {
                Write-Log -Message "[CVAD Machines] Getting Broker VMs from $($DDC)" -Level Info
            } else {
                Write-Log -Message "[CVAD Machines] Getting additional Broker VMs from $($DDC) with continuation token" -Level Info
            }
            
            $BrokerVMs = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
            $BrokerVMsTotal.AddRange($BrokerVMs.Items)
    
            if ($BrokerVMs.ContinuationToken) {
                $ContinuationToken = $BrokerVMs.ContinuationToken
            } else {
                $ContinuationToken = $null
            }
        }
        catch {
            Write-Log -Message $_ -Level Warn
            Break
        }
    } while ($ContinuationToken)

    # Return the list of VMs
    if ($BrokerVMsTotal.Count -gt 0) {
        Write-Log -Message "[CVAD Machines] Retrieved $($BrokerVMsTotal.Count) machines from $($DDC)" -Level Info
        return $BrokerVMsTotal
    } else {
        Write-Log -Message "[CVAD Machines] No machines returned from $($DDC)" -Level Warn
        return $null
    }

}

function Get-CVADHostingConnectionDetail {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$HostingConnectionID
    )

    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$DDC/cvad/manage/hypervisors/$HostingConnectionID"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $HostingConnectionDetail = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    Return $HostingConnectionDetail

}

function Get-CVADHostingConnectionTarget {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$HostingConnectionName
    )

    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$DDC/cvad/manage/hypervisors/$HostingConnectionName"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $HostingConnectionDetail = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    Return $HostingConnectionDetail
}

function Set-CVADMachineHostingConnection {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$CitrixMachineId,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$TargetHostingConnectionName
    )

    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "PATCH"
    $RequestUri = "https://$($DDC)/cvadapis/$SiteID/Machines/$($CitrixMachineId)"
    
    $PayloadContent = @{
        HypervisorConnection = $TargetHostingConnectionName
    }
    $Payload = (ConvertTo-Json $PayloadContent)
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $UpdateMachineHostingConnection = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -Body $Payload -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop -ContentType "application/json"
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    return $UpdateMachineHostingConnection
}

function Get-CVADMachineOnTargetHostingConnection {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$HostingConnectionName,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$machineName
    )

    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$DDC/cvad/manage/hypervisors/$HostingConnectionName/allResources?path=VirtualMachines.folder/$($machineName).vm&?noCache=true"
    #----------------------------------------------------------------------------------------------------------------------------

    try {
        $MachineAvailableOnHosting = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    return $MachineAvailableOnHosting
}

function Get-CVADMachineDetail {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true, ParameterSetName = "ById")][string]$CitrixMachineId,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true, ParameterSetName = "ByName")][string]$CitrixMachineName
    )

    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    if ($CitrixMachineId) {
        $RequestUri = "https://$DDC/cvad/manage/Machines/$($CitrixMachineId)"
    } elseif ($CitrixMachineName) {
        $RequestUri = "https://$DDC/cvad/manage/Machines/$($CitrixMachineName)"
    }
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $MachineDetail = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    return $MachineDetail
}

function Get-CVADCatalogDetails {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$Catalog
    )

    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$DDC/cvad/manage/MachineCatalogs/$Catalog"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $CatalogDetail = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    return $CatalogDetail
}

function Set-CVADHostingConnectionReset {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][Hashtable]$Headers,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$TargetHostingConnectionName
    )
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "POST"
    #$RequestUri = "https://$DDC/cvad/manage/hypervisors/$HostingConnectionName/`$resetConnection"
    $RequestUri = "https://$($DDC)/cvadapis/$SiteID/hypervisors/$($TargetHostingConnectionName)/`$resetConnection"
    $Payload = $null
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $HostingReset = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -ContentType "application/json"  -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
$SupportedSourceHypervisorPluginTypes = @("AcropolisFactory")
#endregion Variables

#Region Execute
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
Write-Log -Message "[Script Params] Citrix Cloud Region = $($Region)" -Level Info
Write-Log -Message "[Script Params] Citrix Cloud CustomerID = $($CustomerID)" -Level Info
Write-Log -Message "[Script Params] Citrix Cloud ClientID = $($ClientID)" -Level Info
Write-Log -Message "[Script Params] Citrix Cloud SecureClientFile = $($SecureClientFile)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Machine List = $($TargetMachineList)" -Level Info
Write-Log -Message "[Script Params] Citrix Target Hosting Connection Name = $($TargetHostingConnectionName)" -Level Info
Write-Log -Message "[Script Params] Citrix Reset Target Hosting Connection = $($ResetTargetHostingConnection)" -Level Info
Write-Log -Message "[Script Params] Citrix Supported Hypervisor Plugin Types = $($SupportedSourceHypervisorPluginTypes)" -Level Info
Write-Log -Message "[Script Params] Citrix Catalogs to query machines = $($Catalogs)" -Level Info
Write-Log -Message "[Script Params] VM ExclusionList = $($ExclusionList)" -Level Info
#endregion script parameter reporting

#check PoSH version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Log -Message "This script requires PowerShell 7 or later. Please upgrade your PowerShell version." -Level Error
    StopIteration
    Exit 1
}

#region Param Validation
if (!($SecureClientFile) -and !($ClientID)) {
    Write-Log -Message "[PARAM ERROR]: You must specify either SecureClientFile or ClientID parameters to continue" -Level Warn
    StopIteration
    Exit 0
}
if ($SecureClientFile -and ($ClientID -or $ClientSecret)) {
    Write-Log -Message "[PARAM ERROR]: You cannot specify both SecureClientFile and ClientID or ClientSecret together. Invalid parameter options" -Level Warn
    StopIteration
    Exit 0
}
if ($TargetMachineList -and $Catalogs) {
    Write-Log -Message "[PARAM ERROR]: You cannot specify both TargetMachineList and Catalogs together. Invalid parameter options" -Level Warn
    StopIteration
    Exit 0
}
if ($TargetMachineList -and $Catalogs) {
    Write-Log -Message "[PARAM ERROR]: You cannot specify both TargetMachineList and Catalogs together. Invalid parameter options" -Level Warn
    StopIteration
    Exit 0
}
#endregion Param Validation

#region Citrix Cloud Setup
#------------------------------------------------------------
# Set Cloud API URL based on Region
#------------------------------------------------------------
switch ($Region) {
    'AP-S' { 
        $CloudUrl = "api.cloud.com"
    }
    'EU' {
        $CloudUrl = "api.cloud.com"
    }
    'US' {
        $CloudUrl = "api.cloud.com"
    }
    'JP' {
        $CloudUrl = "api.citrixcloud.jp"
    }
}

Write-Log -Message "[Citrix Cloud] Resource URL is $($CloudUrl)" -Level Info

#endregion Citrix Cloud Setup

#region Citrix Auth
#------------------------------------------------------------
# Handle Secure Client CSV Input
#------------------------------------------------------------
if ($SecureClientFile) {
    Write-Log -Message "[Citrix Cloud] Importing Secure Client: $($SecureClientFile)" -Level Info
    try {
        $SecureClient = Import-Csv -Path $SecureClientFile -ErrorAction Stop
        $ClientID = $SecureClient.ID
        $ClientSecret = $SecureClient.Secret
    }
    catch {
        Write-Log -Message "[Citrix Cloud] Failed to import Secure Client File" -Level Warn
        Exit 1
        StopIteration
    }
}

#------------------------------------------------------------
# Authenticate against Citrix Cloud DaaS and grab Site info
#------------------------------------------------------------
Write-Log -Message "[Citrix Cloud] Creating Citrix Cloud acccess token" -Level Info
$AccessToken = Get-CCAccessToken -ClientID $ClientID -ClientSecret $ClientSecret

Write-Log -Message "[Citrix Cloud] Getting Citrix Cloud Site ID" -Level Info
$SiteID = Get-CCSiteID -CustomerID $CustomerID -AccessToken $AccessToken 
Write-Log -Message "[Citrix Cloud] Citrix Cloud Site ID is: $($SiteID)" -Level Info

#------------------------------------------------------------
# Set Auth Headers for Citrix DaaS API calls
#------------------------------------------------------------
$daas_headers = @{
    Authorization       = "CwsAuth Bearer=$($AccessToken)"
    'Citrix-CustomerId' = $CustomerID
    Accept              = 'application/json'
    'Citrix-InstanceId'   = $SiteID
}
#endregion Citrix Auth

ValidateCitrixCloud -Headers $daas_headers

#region validate the target hosting connection
#------------------------------------------------------------
#Validate the target hosting connection
#------------------------------------------------------------
Write-Log -Message "[Target Hosting Connection] Validating Target Hosting Connection" -Level Info
if ( (Get-CVADHostingConnectionTarget -DDC $CloudUrl -Headers $daas_headers -HostingConnectionName $TargetHostingConnectionName).PluginId -ne "AcropolisPCFactory") {
    Write-Log -Message "[Target Hosting Connection] Target Hosting Connection is not of type AcropolisPCFactory" -Level Warn
    StopIteration
    Exit 0
} else {
    Write-Log -Message "[Target Hosting Connection] Target Hosting Connection is of type AcropolisPCFactory" -Level Info
}
#endregion validate the target hosting connection

#region Citrix Cloud Info Gathering

#region Get VM list - Citrix API
#------------------------------------------------------------------------------------------
$CitrixVMMasterList = [System.Collections.ArrayList] @()

if ($Catalogs) {
    foreach ($Catalog in $Catalogs) {
        # Need to go and get a Catalog Function here so we can validate it is not an MCS or PVS Catalog
        Write-Log -Message "[Catalog Validation] Validating Catalog $($Catalog)" -Level Info
        $CatalogDetails = Get-CVADCatalogDetails -DDC $CloudUrl -Headers $daas_headers -Catalog $Catalog
        if ($null -eq $CatalogDetails) {
            Write-Log -Message "[Catalog Validation] Catalog $($Catalog) not found" -Level Warn
            Continue
        } else {
            if ($CatalogDetails.ProvisioningType -ne "Manual") {
                Write-Log -Message "[Catalog Validation] Catalog $($Catalog) is not a Manual Catalog and is of type $($CatalogDetails.ProvisioningType)" -Level Warn
                continue
            } else {
                Write-Log -Message "[Catalog Validation] Catalog $($Catalog) is a Manual Catalog. Processing" -Level Info
                $CitrixMachines = Get-CVADVMListAPI -DDC $CloudUrl -Headers $daas_headers -Catalog $Catalog
            }
        }
    }
} else {
    $CitrixMachines = [System.Collections.ArrayList] @()
    foreach ($Machine in $TargetMachineList | Where-Object {$_ -notin $ExclusionList}) {
        if ($Machine -like "*\*") { 
            Write-Log -Message "[VM Retrieval $($Machine)] Retrieving VM details" -Level Info
            $machineQueryName = $Machine -replace "\\","|" 
            $machineDetail = Get-CVADMachineDetail -DDC $CloudUrl -Headers $daas_headers -CitrixMachineName $machineQueryName
            if ($machineDetail.ProvisioningType -ne "Manual") {
                Write-Log -Message "[VM Retrieval $($Machine)] Machine is not a Manual Machine and is of type $($machineDetail.ProvisioningType)" -Level Warn
                Continue
            } else {
                [void]$CitrixMachines.Add($machineDetail)
            }

        } else { 
            Write-Log -Message "[VM Retrieval $($Machine)] Machine name is not in the correct format" -Level Warn 
            Continue
        }
    }
}

if ($null -eq $CitrixMachines) {
    Write-Log -Message "No suitable Citrix Machines found" -Level Warn
    StopIteration
    Exit 0
}

$CitrixVMMasterList.AddRange($CitrixMachines)
#endregion Get VM list - Citrix API

#region validate hosting connections
$HostingConnectionMasterListDetails = $CitrixVMMasterList.Hosting.HypervisorConnection | Sort-Object -Property Id -Unique

$HostingConnectionValidatedList = [System.Collections.ArrayList] @()
$HostingConnectionInvalidList = [System.Collections.ArrayList] @()

foreach ($HostingConnection in $HostingConnectionMasterListDetails) {
    Write-Log -Message "[Hosting Validation] Validating Hosting Connection $($HostingConnection.Name)" -Level Info
    $HostingConnectionDetail = Get-CVADHostingConnectionDetail -DDC $CloudUrl -Headers $daas_headers -HostingConnectionID $HostingConnection.Id

    if ($HostingConnectionDetail.PluginId -in $SupportedSourceHypervisorPluginTypes) {
        Write-Log -Message "[Hosting Validation] Hosting Connection $($HostingConnection.Name) is supported for source machines" -Level Info
        [void]$HostingConnectionValidatedList.Add($HostingConnectionDetail)
    } else {
        Write-Log -Message "[Hosting Validation] Hosting Connection $($HostingConnection.Name) is not supported for source machines" -Level Warn
        [void]$HostingConnectionInvalidList.Add($HostingConnectionDetail)
    }
}
#endregion validate hosting connections

#endregion Citrix Cloud Info Gathering

#region Process the VMs

$VMUpdateSuccessCount = 0
$VMUpdateFailCount = 0
$VMProcessCount = 1

foreach ($VM in $CitrixVMMasterList) {
    Write-Log -message "[VM Validation] Processing VM $($VMProcessCount) of $($CitrixVMMasterList.Count): $($VM.Name)" -Level Info

    if ($VM.Name -in $ExclusionList) {
        Write-Log -Message "[$($VM.Name)] VM is in the exclusion list. Not processing" -Level Info
        $VMProcessCount ++
        Continue
    } else {
        if ($VM.Hosting.HypervisorConnection.Id -in $HostingConnectionValidatedList.Id) {
            Write-Log -Message "[$($VM.Name)] Is on a supported source hosting connection" -Level Info
            # Now go and check that the target hosting connection can see the VM
            if ($null -ne $VM.Hosting.HostedMachineName) { $machineQueryName = $VM.Hosting.HostedMachineName } else { $machineQueryName = $VM.Name -split '\\' | Select-Object -Last 1 }
    
            Write-Log -Message "[$($VM.Name)] Checking if VM is available on the target hosting connection" -Level Info
            $MachineAvailableOnHosting = Get-CVADMachineOnTargetHostingConnection -DDC $CloudUrl -Headers $daas_headers -HostingConnectionName $TargetHostingConnectionName -machineName $machineQueryName
    
            if ([string]::IsNullOrEmpty($MachineAvailableOnHosting)){
                Write-Log -Message "[$($VM.Name)] Is not visible via the target hosting connection" -Level Warn
                $VMUpdateFailCount ++
                $VMProcessCount ++
                Continue
            } else {
                # VM is valid and found via lookup
                if ($Whatif) {
                    # We are in whatif ode
                    Write-Log -Message "[WHATIF] [$($VM.Name)] Would update hosting connection to $($TargetHostingConnectionName)" -Level Info
                    $VMUpdateSuccessCount ++
                    $VMProcessCount ++
                } else {
                    # We are processing
                    Write-Log -Message "[$($VM.Name)] Updating hosting connection to $($TargetHostingConnectionName)" -Level Info
                    $null = Set-CVADMachineHostingConnection -DDC $CloudUrl -Headers $daas_headers -CitrixMachineId $VM.Id -TargetHostingConnectionName $TargetHostingConnectionName
                    # Now to validate as the above returns no output
                    if ((Get-CVADMachineDetail -DDC $CloudUrl -Headers $daas_headers -CitrixMachineId $VM.Id).Hosting.HypervisorConnection.name -eq $TargetHostingConnectionName) {
                        Write-Log -Message "[$($VM.Name)] Updated to the target hosting connection" -Level Info
                        $VMUpdateSuccessCount ++
                        $VMProcessCount ++
                    } else {
                        Write-Log -Message "[$($VM.Name)] Failed to update to the target hosting connection" -Level Warn
                    }
                }
            }
        } else {
            Write-Log -Message "[VM $($VM.Name)] Is not on a supported source hosting connection" -Level Warn
            $VMUpdateFailCount ++
            $VMProcessCount ++
        }
    }
}
#endregion Process the VMs

#region Hosting Connection Reset
#------------------------------------------------------------
# Reset the Citrix Hosting Connection to update power states (there is a 5-10 minute sync otherwise)
#------------------------------------------------------------
if ($ResetTargetHostingConnection) {
    if ($CitrixVMMasterList.Count  -gt 0 -and $VMUpdateSuccessCount -gt 0){
        if ($Whatif) {
            # We are in whatif mode
            Write-Log -Message "[WHATIF] [Citrix Hosting] Would reset Citrix Hosting Connection: $($TargetHostingConnectionName)" -Level Info
        } else {
            # We are processing
            Write-Log -Message "[Citrix Hosting] Resetting Citrix Hosting Connection: $($TargetHostingConnectionName)" -Level Info
            Set-CVADHostingConnectionReset -DDC $CloudUrl -Headers $daas_headers -TargetHostingConnectionName $TargetHostingConnectionName
        }
    } else {
        Write-Log -Message "[Citrix Hosting] No machines were altered so Hosting Connection has not been reset" -Level Info
    }
}
#endregion Hosting Connection Reset

#region Script Reporting
if ($Whatif) {
    # We are in whatif mode
    Write-Log -Message "[Script Report] Script is in Whatif mode. No changes have been made" -Level Info
} else {
    # We are processing
    if ($VMUpdateSuccessCount -gt 0) { Write-Log -Message "[Script Report] Successfully updated $($VMUpdateSuccessCount) Machines" -Level Info }
    if ($VMUpdateFailCount -gt 0) { Write-Log -message "[Script Report] Failed to update $($VMUpdateFailCount) Machines" -Level Warn }
}
#endregion Script Reporting

StopIteration
Exit 0
#endregion