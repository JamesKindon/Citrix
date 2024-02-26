<#
.SYNOPSIS
    Quick update script designed to update an MCS provisioned Catalog, or set of Catalogs, based on a provided image
.DESCRIPTION
    Provide an Image, a list of Catalogs, and the script will update the ProvScheme ready for the next reboot cycle
.PARAMETER LogPath
    Logpath output for all operations. Default path is C:\Logs\QuickCatalogUpdate.log
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5.
.PARAMETER Platform
    Either Citrix DaaS or Citrix VAD. DaaS and CVAD are acceptable inputs.
.PARAMETER Image
    The name of the snapshot (for PE) or template (for PC) to update the Catalog ProvScheme with.
.PARAMETER Catalogs
    An array of Catalogs to process
.PARAMETER DDC
    If processing in CVAD mode, the Delivery Controller to target.
.PARAMETER CVADUser
    If processing in CVAD mode, the Domain username with permissions to action the update. This is used to Auth to CVAD API
.PARAMETER CVADPass
    If processing in CVAD mode, the Domain password for the DomainUserName account
.PARAMETER Region
    If processing in DaaS mode. The Citrix Cloud DaaS Tenant Region. Either AP-S (Asia Pacific), US (USA), EU (Europe) or JP (Japan)
.PARAMETER CustomerID
    If processing in DaaS mode. The Citrix Cloud Customer ID
.PARAMETER SecureClientFile
    If processing in DaaS mode. Path to the Citrix Cloud Secure Client CSV. Cannot be used with ClientID or ClientSecret parameters.
.PARAMETER ClientID
    If processing in DaaS mode. The Citrix Cloud Secure Client ID. Cannot be used with the SecureClientFile Parameter. Must be combined with the ClientSecret parameter.
.PARAMETER ClientSecret
    If processing in DaaS mode. The Citrix Cloud Secure Client Secret. Cannot be used with the SecureClientFile Parameter. Must be used with the ClientID parameter.
.PARAMETER noprompt
    Silently continue without parameter confirmation.
.EXAMPLE
    .\QuickCatalogUpdate.ps1 -Platform "DaaS" -Region "US" -CustomerID "fakecustID" -SecureClientFile "C:\SecureFolder\secureclient.csv" -Catalogs "Catalog1","Catalog2","Catalog3" -Image "nutanix_snapshot_name" -noprompt
.EXAMPLE
    .\QuickCatalogUpdate.ps1 -Platform "CVAD" -DDC "DDC01" -Catalogs "Catalog1","Catalog2","Catalog3" -Image "nutanix_snapshot_name" -CVADUser "user@domain.com" -CVADPass "f@k3_Passw0rd" -noprompt
.NOTES
    V1: Only supports Nutanix Hosting Connections. Easy to extend the capability if required.
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\QuickCatalogUpdate.log", # Where we log to

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # Number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [ValidateSet("CVAD","DaaS")]
    [String]$Platform,

    [Parameter(Mandatory = $false)]
    [string]$Image,

    [Parameter(Mandatory = $false)] 
    [Array]$Catalogs,

    [Parameter(Mandatory = $false)]
    [string]$DDC, 

    [Parameter(Mandatory = $false)]
    [ValidateSet("AP-J","US","EU","JP")]
    [String]$Region = "US",

    [Parameter(Mandatory = $false)]
    [string]$CustomerID, 

    [Parameter(Mandatory = $false)]
    [string]$SecureClientFile,

    [Parameter(Mandatory = $false)] 
    [string]$ClientID, 

    [Parameter(Mandatory = $false)] 
    [string]$ClientSecret, 

    [Parameter(Mandatory = $false)]
    [string]$CVADUser, 

    [Parameter(Mandatory = $false)]
    [string]$CVADPass,

    [Parameter(Mandatory = $false)]
    [switch]$noprompt

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

function Get-CVADAuthDetails {
    [CmdletBinding()]
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DDC,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$EncodedAdminCredential
        #[Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$DomainAdminCredential
    )
    #--------------------------------------------
    # Get the CVAD Access Token
    #--------------------------------------------
    Write-Log -Message "Retrieving CVAD Access Token" -Level Info
    $TokenURL = "https://$DDC/cvad/manage/Tokens"
    $Headers = @{
        Accept = "application/json"
        Authorization = "Basic $EncodedAdminCredential"
    }

    try {
        $Response = Invoke-WebRequest -Uri $TokenURL -Method Post -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to return token. Exiting" -Level Error
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }
    
    $AccessToken = $Response.Content | ConvertFrom-Json

    if (-not ([string]::IsNullOrEmpty($AccessToken))) {
        Write-Log -Message "Successfully returned Token" -Level Info
    }
    else {
        Write-Log -Message "Failed to return token. Exiting" -Level Error
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }

    #--------------------------------------------
    # Get the CVAD Site ID
    #--------------------------------------------
    Write-Log -Message "Retrieving CVAD Site ID" -Level Info

    $URL = "https://$DDC/cvad/manage/Me"
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$($AccessToken.Token)";
        "Citrix-CustomerId" = "CitrixOnPremises";
    }

    try {
        $Response = Invoke-WebRequest -Uri $URL -Method Get -Header $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to return Site ID. Exiting" -Level Error
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }

    $SiteID = $Response.Content | ConvertFrom-Json

    if (-not ([String]::IsNullOrEmpty($SiteID))) {
        Write-Log -Message "Successfully returned CVAD Site ID: $($SiteID.Customers.Sites.Id)" -Level Info
    }
    else {
        Write-Log -Message "Failed to return Site ID. Exiting" -Level Error
        StopIteration
        Exit 1
    }

    #--------------------------------------------
    # Set the headers
    #--------------------------------------------

    Write-Log -Message "Set Standard Auth Heathers for CVAD API Calls" -Level Info
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$($AccessToken.Token)";
        "Citrix-CustomerId" = "CitrixOnPremises";
        "Citrix-InstanceId" = "$($SiteID.Customers.Sites.Id)";
    }

    # we need to send back the headers for use in future calls
    Return $Headers
    
}

function Get-DaaSAuthDetails {
    param (
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$ClientID,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$ClientSecret,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$CustomerID,
        [Parameter(ValuefromPipelineByPropertyName = $true, mandatory = $true)][string]$CloudUrl
    )

    #--------------------------------------------
    # Get the DaaS Access Token
    #--------------------------------------------
    $TokenURL = "https://$($CloudUrl)/cctrustoauth2/root/tokens/clients"
    $Body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientID
        client_secret = $ClientSecret
    }
    try {
        $Response = Invoke-WebRequest $tokenUrl -Method POST -Body $Body -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to return token. Exiting" -Level Error
        StopIteration
        Exit 1
    }

    $AccessToken = $Response.Content | ConvertFrom-Json

    if (-not ([string]::IsNullOrEmpty($AccessToken))) {
        Write-Log -Message "Successfully returned Token" -Level Info
    } else {
        Write-Log -Message "Failed to return token. Exiting" -Level Error
        StopIteration
        Exit 1
    }

    #--------------------------------------------
    # Get the DaaS Site ID
    #--------------------------------------------
    Write-Log -Message "Retrieving DaaS Site ID" -Level Info

    $RequestUri = "https://$($CloudUrl)/cvadapis/me"
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$($AccessToken.access_token)";
        "Citrix-CustomerId" = "$CustomerID";
    }

    try {
        $Response = Invoke-RestMethod -Uri $RequestUri -Method GET -Headers $Headers -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to return Site ID. Exiting" -Level Error
        StopIteration
        Exit 1
    }

    $SiteID = $Response.Customers.Sites.Id

    if (-not ([String]::IsNullOrEmpty($SiteID))) {
        Write-Log -Message "Successfully returned DaaS Site ID: $($SiteID)" -Level Info
    } else {
        Write-Log -Message "Failed to return Site ID. Exiting" -Level Error
        StopIteration
        Exit 1
    }

    #--------------------------------------------
    # Set the headers
    #--------------------------------------------
    Write-Log -Message "Set Standard Auth Heathers for DaaS API Calls" -Level Info
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$($AccessToken.access_token)";
        "Citrix-CustomerId" = "$CustomerID";
        "Citrix-InstanceId" = "$SiteID";
    }

    return $Headers
}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
$supported_hosting_connection_types = @("AcropolisFactory","AcropolisPCFactory")
#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

#check PoSH version
if ($PSVersionTable.PSVersion.Major -lt 7) { 
    Write-Log -Message "This script is only validated on PowerShell 7: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?" -Level Error 
    StopIteration
    Exit 1
}

#------------------------------------------------------------
# Set and validate environment
#------------------------------------------------------------
if (([string]::IsNullOrEmpty($Platform))) {
    Write-Log -Message "[PARAM ERROR] You must specify a platform, either CVAD or DaaS to continue" -Level Warn
    StopIteration
    Exit 0
}
if ($Platform -eq "CVAD" -and ([string]::IsNullOrEmpty($DDC))) {
    # CVAD requires a DDC to be specified, use parameters or specify variables
    Write-Log -Message "[PARAM ERROR] In CVAD processing mode, you must specify a DDC to continue" -Level Warn
    StopIteration
    Exit 0
}
if ($Platform -eq "CVAD" -and (([string]::IsNullOrEmpty($CVADUser)) -or ([string]::IsNullOrEmpty($CVADPass)))) {
    # CVAD requires username and password, use parameters or specify variables
    Write-Log -Message "[PARAM ERROR] In CVAD processing mode, you must specify a CVADUser and CVADPass to continue" -Level Warn
    StopIteration
    Exit 0
}
if ($Platform -eq "DaaS" -and (([string]::IsNullOrEmpty($CustomerID)))) {
    # DaaS requires CustomerID, ClientID and ClientSecret use parameters or specify variables
    Write-Log -Message "[PARAM ERROR] In DaaS processing mode, you must specify a CustomerID to continue" -Level Warn
    StopIteration
    Exit 0
}
if ($Platform -eq "DaaS" -and (([string]::IsNullOrEmpty($SecureClientFile)) -and (([string]::IsNullOrEmpty($ClientID)) -or ([string]::IsNullOrEmpty($ClientSecret))))) {
    # DaaS requires CustomerID, ClientID and ClientSecret use parameters or specify variables
    Write-Log -Message "[PARAM ERROR]: You must specify either SecureClientFile or ClientID and ClientSecret parameters to continue" -Level Warn
    StopIteration
    Exit 0
}
if ($Platform -eq "DaaS" -and $SecureClientFile -and ($ClientID -or $ClientSecret)) {
    Write-Log -Message "[PARAM ERROR]: You cannot specify both SecureClientFile and ClientID or ClientSecret together. Invalid parameter options" -Level Warn
    StopIteration
    Exit 0
}
if ([string]::IsNullOrEmpty($Catalogs)) {
    Write-Log -Message "[PARAM ERROR] You must specify an Array of Catalogs to process" -Level Warn
    StopIteration
    Exit 0
}
if ([string]::IsNullOrEmpty($Image)) {
    Write-Log -Message "[PARAM ERROR] You must specify an Image to continue" -Level Warn
    StopIteration
    Exit 0
}
#------------------------------------------------------------
# Convert Username and Password to base64. This is used to talk to Citrix API
#------------------------------------------------------------
if ($Platform -eq "CVAD") {
    $AdminCredential = "$($CVADUser):$($CVADPass)"
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($AdminCredential)
    $Global:EncodedAdminCredential = [Convert]::ToBase64String($Bytes)
}

#------------------------------------------------------------
# Set Cloud API URL based on Region
#------------------------------------------------------------
if ($Platform -eq "DaaS") {
    switch ($Region) {
        'AP-S' { 
            $CloudUrl = "api-ap-s.cloud.com"
        }
        'EU' {
            $CloudUrl = "api-eu.cloud.com"
        }
        'US' {
            $CloudUrl = "api-us.cloud.com"
        }
        'JP' {
            $CloudUrl = "api.citrixcloud.jp"
        }
    }
}

#------------------------------------------------------------
# Write Parameter or VariableDetails
#------------------------------------------------------------
Write-Log -Message "[Script Params] -----------------------------------" -Level Info
Write-Log -Message "[Script Params] LogPath = $($LogPath)" -Level Info
Write-Log -Message "[Script Params] Platform = $($Platform)" -Level Info
Write-Log -Message "[Script Params] Image = $($Image)" -Level Info
Write-Log -Message "[Script Params] Catalogs defined = $($Catalogs)" -Level Info
if ($Platform -eq "CVAD") {
    Write-Log -Message "[Script Params] DDC = $($DDC)" -Level Info
    Write-Log -Message "[Script Params] Domain Username = $($CVADUser)" -Level Info
}
if ($Platform -eq "DaaS") {
    Write-Log -Message "[Script Params] DaaS Region = $($Region)" -Level Info
    Write-Log -Message "[Script Params] DaaS Cloud URL = $($CloudUrl)" -Level Info
    Write-Log -Message "[Script Params] DaaS Customer ID = $($CustomerID)" -Level Info
    if ($SecureClientFile) {
        Write-Log -Message "[Script Params] DaaS SecureClientFile = $($SecureClientFile)" -Level Info
    } else {
        Write-Log -Message "[Script Params] DaaS Client ID = $($ClientID)" -Level Info
    }
}
Write-Log -Message "[Script Params] -----------------------------------" -Level Info

#------------------------------------------------------------ 
# Handle param validation prompt
#------------------------------------------------------------
if (!$noprompt) {
    do { $continue = Read-Host -Prompt "Do you want to continue? (Y[es]/N[o])" } 
    while ($continue -notmatch '[ynYN]')
    $continue = $continue.ToLower() #change to lowercase

    if ($continue -eq "n") {
       Write-Log -Message "Confirmation not received. Exit script" -Level Info
       StopIteration
       Exit 0
    }
}

#------------------------------------------------------------
# Handle Secure Client CSV Input
#------------------------------------------------------------
if ($SecureClientFile) {
    Write-Log -Message "Importing Secure Client: $($SecureClientFile)" -Level Info
    try {
        $SecureClient = Import-Csv -Path $SecureClientFile -ErrorAction Stop
        $ClientID = $SecureClient.ID
        $ClientSecret = $SecureClient.Secret
    }
    catch {
        Write-Log -Message "Failed to import Secure Client File" -Level Warn
        StopIteration
        Exit 1
    }
}

#---------------------------------------------
# Set Auth Headers
#---------------------------------------------
Write-Log -Message "Handling authentication and API headers" -Level Info
if ($Platform -eq "CVAD") {
    $Headers = Get-CVADAuthDetails -DDC $DDC -EncodedAdminCredential $EncodedAdminCredential
}
if ($Platform -eq "DaaS") {
    $Headers = Get-DaaSAuthDetails -CloudUrl $CloudUrl -CustomerID $CustomerID -ClientID $ClientID -ClientSecret $ClientSecret
}

#---------------------------------------------
# Set the common URL for calls
#---------------------------------------------
if ($Platform -eq "CVAD") {
    $ReqUri = $DDC
}
if ($Platform -eq "DaaS") {
    $ReqUri = $CloudUrl
}

#----------------------------------------------------------------------------------------------------------------------------
# Validate Citrix Site Details
#----------------------------------------------------------------------------------------------------------------------------
if ($Platform -eq "CVAD") {
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$ReqUri/cvad/manage/Sites/"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        Write-Log -Message "Getting Citrix Site Info" -Level Info
        $cvad_sites = (Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop).Items
        $cvad_site_id = $cvad_sites.Id
        # Now get details about the site
        #----------------------------------------------------------------------------------------------------------------------------
        # Set API call detail
        #----------------------------------------------------------------------------------------------------------------------------
        $Method = "Get"
        $RequestUri = "https://$ReqUri/cvad/manage/Sites/$($cvad_site_id)"
        #----------------------------------------------------------------------------------------------------------------------------
        $cvad_site = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
        Write-Log -Message "Successfully Returned Citrix Site Detail. Site version is: $($cvad_site.ProductVersion)" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Error
        Exit 1
    }
}
if ($Platform -eq "DaaS") {
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$ReqUri/cvad/manage/Sites/cloudxdsite"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        Write-Log -Message "Getting Citrix DaaS Site Info" -Level Info
        $daas_site = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
        Write-Log -Message "Successfully Returned Citrix DaaS Site Detail. Site version is $($daas_site.ProductVersion)" -Level Info
    }
    catch {
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }
}

#---------------------------------------------
# Validate Catalogs Exist and are of appropriate Type
#---------------------------------------------
# Initialize arrays
$supported_catalogs = @() #Looking for MCS catalogs only

$hosting_connection_type_element = 0
$hosting_connection_type_central = 0

foreach ($Catalog in $Catalogs) {
    #----------------------------------------------------------------------------------------------------------------------------
    # Check Catalog Exists
    #----------------------------------------------------------------------------------------------------------------------------
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$ReqURI/cvad/manage/MachineCatalogs/"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        Write-Log -Message "[Catalog Validation - $($Catalog)]" -Level Info
        Write-Log -Message "Checking to see if Catalog: $($Catalog) exists" -Level Info
        $catalog_details = (Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop).Items | Where-Object { $_.Name -eq $Catalog }
    }
    catch {
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }

    if (-not ([string]::IsNullOrEmpty($catalog_details))){
        Write-Log -Message "Catalog: $($Catalog) exists" -Level Info
    } else {
        Write-Log -Message "Catalog: $($Catalog) does not exist. Ignoring" -Level Info
        Continue
    }
    #----------------------------------------------------------------------------------------------------------------------------
    # Check Catalog is MCS Provisioned -> If not, fail
    #----------------------------------------------------------------------------------------------------------------------------
    if ($catalog_details.ProvisioningType -eq "MCS") {
        Write-Log -Message "Catalog: $($Catalog) is an MCS provisioned Catalog and is supported" -Level Info
        #----------------------------------------------------------------------------------------------------------------------------
        # Check Catalog is not already on the specified image
        #----------------------------------------------------------------------------------------------------------------------------
        if ($catalog_details.ProvisioningScheme.MasterImage.Name -eq $Image) {
            Write-Log -Message "Catalog: $($Catalog) is already using the specified image: $($Image) and will not be processed" -Level Info
            Continue
        }
        $supported_catalogs += $catalog_details

    } else {
        Write-Log -Message "Catalog: $($Catalog) Provisioning Type is: $($catalog_details.ProvisioningType) which is of no use to this process and will not be included for processing" -Level Warn
        Continue
    }

    #----------------------------------------------------------------------------------------------------------------------------
    # Check Hosting Connection Type (We can't process both PC and PE based Catalogs as they use different hosting image types)
    #----------------------------------------------------------------------------------------------------------------------------
    $catalog_hosting_details = $catalog_details.ProvisioningScheme.ResourcePool.Hypervisor

    #----------------------------------------------------------------------------------------------------------------------------
    # Validate Citrix Hosting Details
    #----------------------------------------------------------------------------------------------------------------------------
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$ReqURI/cvad/manage/hypervisors/$($catalog_hosting_details.Id)"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        Write-Log -Message "[Hosting Validation]" -Level Info
        Write-Log -Message "Getting Hosting Connection Details for: $($catalog_hosting_details.Name)"
        $hosting_connection_detail = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }

    if (-not ([string]::IsNullOrEmpty($hosting_connection_detail))){
        Write-Log -Message "Hosting Connection: $($hosting_connection_detail.Name) details retrieved" -Level Info
    } else {
        Write-Log -Message "Hosting Connection detail for Catalog: $($catalog_hosting_details.Name) not retrieved. Ignoring" -Level Info
        Continue
    }

    if ($hosting_connection_detail.PluginID -notin $supported_hosting_connection_types) {
        Write-Log -Message "Hosting Connection: $($hosting_connection_detail.Name) is not in the supported hosting connection list and is not supported by this script. Ignoring." -Level Warn
        Continue
    }
    #----------------------------------------------------------------------------------------------------------------------------
    # Validate this is a nutanix AHV hosting conection
    #----------------------------------------------------------------------------------------------------------------------------
    if ($hosting_connection_detail.PluginID -eq "AcropolisFactory") {
        Write-Log -Message "Hosting Connection: $($catalog_hosting_details.Name) is configured to use Nutanix Prism Element" -Level Info
        $hosting_connection_type_element ++

    } elseif ($hosting_connection_detail.PluginID -eq "AcropolisPCFactory") {
        Write-Log -Message "Hosting Connection: $($catalog_hosting_details.Name) is configured to use Nutanix Prism Central" -Level Info
        $hosting_connection_type_central ++
    }

    #----------------------------------------------------------------------------------------------------------------------------
    # Validate the hosting connection can find the specified snapshot or template
    #----------------------------------------------------------------------------------------------------------------------------
    Write-Log -Message "[Image Validation] ------------------------------------------" -Level Info
    Write-Log -Message "Looking for Image: $($Image) via Hosting Connection: $($catalog_hosting_details.Name) for Catalog: $($Catalog)" -Level Info
    $image_full = $image + ".template"
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "Get"
    $RequestUri = "https://$ReqUri/cvad/manage/hypervisors/$($catalog_hosting_details.Id)/allResources?path=$($image_full)&detail=true&?noCache=true"
    #----------------------------------------------------------------------------------------------------------------------------
    try {
        $image_exists = Invoke-RestMethod -Uri $RequestUri -Method $Method -Headers $Headers -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
    }
    catch {
        Write-Log -Message $_ -Level Error
        StopIteration
        Exit 1
    }

    try {$image_exists = $image_exists} catch {$image_exists = $null}

    if (-not [string]::IsNullOrEmpty($image_exists)) {
        Write-Log -Message "Hosting Connection: $($catalog_hosting_details.Name) has found image: $($Image) via path: $($image_exists.XDPath) for Catalog: $($Catalog)" -Level Info
    } else {
        Write-Log -Message "Hosting Connection: $($catalog_hosting_details.Name) cannot find requested image: $($Image) for Catalog: $($Catalog)" -Level Error
        StopIteration
        Exit 1
    }
}

#----------------------------------------------------------------------------------------------------------------------------
# Check counts above - we can't proceed if are different hosting types
#----------------------------------------------------------------------------------------------------------------------------
Write-Log -Message "[Validation Summary]" -Level Info
if ($hosting_connection_type_element -gt 0 -and $hosting_connection_type_central -gt 0) {
    Write-Log -Message "There are a combination of $($hosting_connection_type_element) Prism Element and $($hosting_connection_type_central) type Hosting Connections found. You should run this script against unique hosting types." -Level Warn
    StopIteration
    Exit 1
}

if ([string]::isNullOrEmpty($supported_catalogs)) {
    Write-Log -Message "There are no Catalogs to process" -Level Info
    StopIteration
    Exit 0
}

if ($hosting_connection_type_element -gt 0) {
    Write-Log -Message "$($supported_catalogs.Count) Catalogs are supported and use Nutanix Prism Element Hosting Connections" -Level Info
} elseif ($hosting_connection_type_central -gt 0) {
    Write-Log -Message "$($supported_catalogs.Count) Catalogs are supported and use Nutanix Prism Central Hosting Connections" -Level Info
} else {
    Write-Log -Message "$($supported_catalogs.Count) Catalogs are supported but are of neither Nutanix Prism Element or Prism Central hosting type" -Level Info
}

#---------------------------------------------
# Process the Catalogs 
#---------------------------------------------

$image_full = $image + ".template"

$CurrentCatalogCount = 1
$TotalCatalogSuccessCount = 0
$TotalCatalogFailureCount = 0

foreach ($Catalog in $supported_catalogs) {
    #---------------------------------------------
    # Update the Catalog
    #---------------------------------------------
    
    Write-Log -Message "[Catalog Processing - $($Catalog.Name)] Processing Catalog Update" -Level Info
    #----------------------------------------------------------------------------------------------------------------------------
    # Set API call detail
    #----------------------------------------------------------------------------------------------------------------------------
    $Method = "POST"
    $RequestUri = "https://$ReqUri/cvad/manage/MachineCatalogs/$($Catalog.Name)/`$UpdateProvisioningScheme"
    $PayloadContent = @{
        MasterImagePath = $image_full
    }
    $Payload = (ConvertTo-Json $PayloadContent -Depth 4)
    #----------------------------------------------------------------------------------------------------------------------------

    try {
        $PublishTask = Invoke-RestMethod -Method $Method -Headers $headers -Uri $RequestUri -Body $Payload -ContentType "application/json" -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop 

        ## Track progress of the image update
        Write-Log -Message "Tracking progress of the Catalog update task $($PublishTask.Id)" -Level Info
        #----------------------------------------------------------------------------------------------------------------------------                
        # Set API call detail                
        #----------------------------------------------------------------------------------------------------------------------------
        $Method = "Get"
        $RequestUri = "https://$ReqUri/cvad/manage/Jobs/$($PublishTask.Id)"
        $Payload = $null
        #----------------------------------------------------------------------------------------------------------------------------
        try {
            $ProvTask = Invoke-RestMethod -Method $Method -Headers $headers -Uri $RequestUri -Body $Payload -ContentType "application/json" -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
            Write-log -Message "Retrieved Catalog update task $($PublishTask.Id)" -level Info
        }
        catch {
            Write-log -Message "Failed to retrieve Catalog update task $($PublishTask.Id)" -level Warn
            Write-Log -Message $_ -Level Warn
            StopIteration
            Exit 1
        }
        
        Write-Log -Message "Tracking progress of the Catalog update task. Catalog update for: $($Catalog.Name) started at: $($ProvTask.CreationTime)" -Level Info
        
        $totalPercent = 0
        While ( $ProvTask.Status -ne "Complete" ) {
            Try { $totalPercent = If ( $ProvTask.OverallProgressPercent ) { $ProvTask.OverallProgressPercent } Else { 0 } } Catch { }
            
            $CurrentOperation = ($ProvTask.SubJobs | Where-Object {$_.Status  -eq "InProgress"} | Select-Object -ExpandProperty Parameters | Select-Object Value).Value
            Write-Log -Message "Provisioning image update on Provisioning Scheme is $($totalPercent)% Complete. Current Operation is: $($CurrentOperation)" -Level Info
            Start-Sleep 15
            try {
                $ProvTask = Invoke-RestMethod -Method $Method -Headers $headers -Uri $RequestUri -Body $Payload -ContentType "application/json" -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
            }
            catch {
                Write-log -Message "Failed to retrieve Catalog update task $($PublishTask.Id)" -level Warn
                Write-Log -Message $_ -Level Warn
                StopIteration
                Exit 1
            }
        }
    }
    catch {
        Write-Log -Message "Failed to start the update process on Catalog: $($Catalog.Name)" -Level Warn
        Write-Log -Message $_ -Level Warn
        $TotalCatalogFailureCount += 1
        Continue
    }
    
    $ElapsedTime = ($ProvTask.EndTime - $ProvTask.CreationTime).TotalSeconds
    Write-Log -Message "Catalog Update for Catalog: $($Catalog.Name) completed at $($ProvTask.EndTime) with an Active time of $($ElapsedTime) seconds" -Level Info
    $CurrentCatalogCount += 1
    $TotalCatalogSuccessCount += 1
}

Write-Log -Message "Successfully processed $($TotalCatalogSuccessCount) Catalogs" -Level Info
if ($TotalCatalogFailureCount -gt 0) {
    Write-Log "Failed to process $($TotalCatalogFailureCount) Catalogs" -Level Warn
}

StopIteration
Exit 0
#endregion