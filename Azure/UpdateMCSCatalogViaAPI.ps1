<#
.SYNOPSIS
    Updates a Citrix Cloud MCS catalog with an Azure image via API
.DESCRIPTION
    All credit goes to Martin Therkelsen whose code is the basis for this script - awesome work
    https://www.cloudninja.nu/post/2021/10/10/citrix-images-using-citrix-cloud-restapi-and-azure-devops/
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================

#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================
function Get-CCAccessToken {
    param (
        [string]$ClientID,
        [string]$ClientSecret
    )
    $TokenURL = "https://api-us.cloud.com/cctrustoauth2/root/tokens/clients"
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
    $RequestUri = "https://api-us.cloud.com/cvadapis/me"
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$AccessToken";
        "Citrix-CustomerId" = $CustomerID;
    }
    $Response = Invoke-RestMethod -Uri $RequestUri -Method GET -Headers $Headers
    return $Response.Customers.Sites.Id
}

function Get-CCMachineCatalog {
    param (
        [Parameter(Mandatory = $true)]
        [string] $CustomerID,
        [Parameter(Mandatory = $true)]
        [string] $SiteID,
        [Parameter(Mandatory = $true)]
        [string] $AccessToken
    )
    $RequestUri = "https://api-us.cloud.com/cvadapis/$SiteID/MachineCatalogs"
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$AccessToken";
        "Citrix-CustomerId" = $CustomerID;
    }
    $Response = Invoke-RestMethod -Uri $RequestUri -Method GET -Headers $Headers 
    return $Response.items
}

function Update-CCMachineCatalog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CustomerID,
        [Parameter(Mandatory=$true)]
        [string]$SiteId,
        [Parameter(Mandatory=$true)]
        [string]$AccessToken,        
	    [string]$MachineCatalogId,        
        [string]$SnapShot
    )
    $RequestUri = "https://api.cloud.com/cvadapis/$SiteId/MachineCatalogs/$MachineCatalogId/`$UpdateProvisioningScheme"    
    $Headers = @{
        "Accept"            = "application/json";
        "Authorization"     = "CWSAuth Bearer=$AccessToken";
        "Citrix-CustomerId" = $CustomerID;
    }
 $body = @"
 {
   "MasterImagePath":"$SnapShot",
   "StoreOldImage":true,
   "RebootOptions":{
     "RebootDuration":0,
     "WarningDuration":0,
     "SendMessage":false
    },
    "RebootOptions":{
      "RebootDuration":0,
      "WarningDuration":0,
      "SendMessage":false
    }
  }
"@     
    $Response = Invoke-WebRequest -Uri $requestUri -Method Post -Headers $headers -Body $body -ContentType "application/json" -UseBasicParsing
    return $Response
}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
# Set Variables

$ClientID                   = $env:ClientID
$ClientSecret               = $env:ClientSecret
$CustomerID                 = $env:CustomerID
$MCSCatalogName             = $env:MCSCatalogName
$ResourceGroup              = $env:ResourceGroup
$ImageName                  = $env:ImageName
$HostingConnectionResource  = $env:HostingConnectionResource

##// For Manual Execution
#$ClientID                   = "" # Citrix Client ID
#$ClientSecret               = "" # Citrix Client Secret
#$CustomerID                 = "" # Citrix Customer ID
#$MCSCatalogName             = "" # Citrix MCS Catalog Name
#$ResourceGroup              = "" # Image Resource group
#$ImageName                  = "" # Image Name
#$HostingConnectionResource  = "" # Citrix Hosting Connection Resource Eg Azure_AE

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================

Write-Host "Creating Citrix Cloud acccess token"
$AccessToken = Get-CCAccessToken -ClientID $ClientID -ClientSecret $ClientSecret
Start-Sleep -Seconds 5

Write-Host "Getting Citrix Cloud Site ID"
$SiteID = Get-CCSiteID -CustomerID $CustomerID -AccessToken $AccessToken 

Write-Host "Getting machine catalog information"
$MachineCatalogInfo = Get-CCMachineCatalog -CustomerID $CustomerID -SiteID $SiteID -AccessToken $AccessToken | Where-Object {$_.Name -eq "$MCSCatalogName"}
    
$NewVersionXDPath = "XDHyp:\\HostingUnits\\$HostingConnectionResource\\image.folder\\$ResourceGroup.resourcegroup\\$ImageName.snapshot"
Write-Host "New snapshot path is $($NewVersionXDPath)"
Write-Host "Updating machine catalog: $($MCSCatalogName)"
Update-CCMachineCatalog -MachineCatalogId $MachineCatalogInfo.id -Snapshot $NewVersionXDPath -SiteID $SiteID -CustomerID $CustomerID -AccessToken $AccessToken -Verbose:$False

Exit 0
#endregion

