<#
.SYNOPSIS
Handles the assignment of certificates requried for both Citrix Brokers and Citrix Cloud Connectors as well as enabling or disabling HTTP based XML Access

Combines some of the work from Stephane Thirion found here https://www.archy.net/enable-ssl-on-xendesktop-7-x-xml-service/ as well as as some misc code snippets picked up along the way

.DESCRIPTION
This script enumerates the ProductID of the Citrix Broker Service or Cloud Connector and the thumbprint of an installed SSL Cert to run the netsh command to add the SSL binding for the broker service.

.PARAMETER EnableSSL
Enables SSL binding for XML Encryption

.PARAMETER DisableSSL
Disables (Deletes) the existing SSL Binding if exists. Enables HTTP

.PARAMETER DisableHTTP
Disables the HTTP listener for XML

.PARAMETER ValidateSSLStatus
Validates SSL configuration

.PARAMETER ValidateHTTPStatus
Validates HTTP configuration

.EXAMPLE
PS C:\> .\EnableSSL.ps1 -EnableSSL
The above example will prompt for a certificate, and once selected will create the apporopriate SSL binding.

PS C:\> .\EnableSSL.ps1 -EnableSSL -DisableHTTP
The above example will prompt for a certificate, and once selected will create the apporopriate SSL binding. It will also disable answering XML requests on HTTP

PS C:\> .\EnableSSL.ps1 -DisableHTTP
The abvoe example will Disable answering XML requests on HTTP

PS C:\> .\EnableSSL.ps1 -DisableSSL
The above example will delete the SSL bindings, and enforce HTTP so that the Cloud Connector or Broker isn't left useless

PS C:\> .\EnableSSL.ps1 -ValidateSSLStatus
The above example will validate the SSL status. It will check that a certificate is bound to the appropriate IP and AppId

PS C:\> .\EnableSSL.ps1 -ValidateHTTPStatus
The above example will validate that HTTP is disabled for XML

.NOTES
.LINK
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False, ParameterSetName = 'ActionEnable')]
    [Switch] $EnableSSL,
    
    [Parameter(Mandatory = $False, ParameterSetName = 'ActionEnable')]
    [Switch] $DisableHTTP,

    [Parameter(Mandatory = $False, ParameterSetName = 'ActionDisable')]
    [Switch] $DisableSSL,

    [Parameter(Mandatory = $False, ParameterSetName = 'Validate')]
    [Switch] $ValidateSSLStatus,

    [Parameter(Mandatory = $False, ParameterSetName = 'Validate')]
    [Switch] $ValidateHTTPStatus
)

function EnableSSL {
    # Fetching registry key to get the Citrix Broker Service GUID
    New-PSDrive -Name 'HKCR' -PSProvider 'Registry' -Root 'HKEY_CLASSES_ROOT' | Out-Null
    $CBS_Guid = Get-ChildItem 'HKCR:\Installer\Products' -Recurse -Ea 0 | Where-Object { $key = $_; $_.GetValueNames() | ForEach-Object { $key.GetValue($_) } | Where-Object { $_ -like '*Citrix Broker Service*' } } | Select-Object Name
    $CBS_Guid.Name -match "[A-Z0-9]*$" | Out-Null
    $GUID = $Matches[0]
 
    # Formating the string to look like a GUID with dash ( - )
    [GUID]$GUIDf = "$GUID"
    Write-Host -Object "INFO: Citrix Broker Service GUID for $env:computername is: $GUIDf" -foregroundcolor "Cyan"
    # Closing PSDrive
    Remove-PSDrive -Name HKCR
 
    # Getting local IP address and adding :443 port
    $ipV4 = Test-Connection -ComputerName (hostname) -Count 1 | Select-Object -ExpandProperty IPV4Address 
    $ipV4ssl = "$ipV4 :443" -replace " ", ""
    Write-Host -Object "INFO: The IP Address for $env:computername is: $ipV4ssl" -ForegroundColor Cyan;
 
    # Getting the certificate thumbprint
    #$Thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match "$HostName"}).Thumbprint -join ';';
    $Thumbprint = Get-ChildItem -Path 'Cert:\LocalMachine\My' | Out-GridView -PassThru | Select-Object -ExpandProperty Thumbprint
    if ($null -eq $Thumbprint) {
        Write-Warning "No Cert Selected. Goodbye."
        Break
    }
    Write-Host -Object "INFO: Certificate Thumbprint for $env:computername is: $Thumbprint" -ForegroundColor Cyan; 
 
    # Preparing to execute the netsh command inside powershell
    $SSLxml = "http add sslcert ipport=$ipV4ssl certhash=$Thumbprint appid={$GUIDf}"
    $SSLxml | netsh
 
    # Verifying the certificate binding on the Citrix XML
    $VerifySSLXML = "http show sslcert"
    $VerifySSLXML | netsh
}

function DisableSSL {
    $ipV4 = Test-Connection -ComputerName (hostname) -Count 1 | Select-Object -ExpandProperty IPV4Address 
    $ipV4ssl = "$ipV4 :443" -replace " ", ""
    $KillSSLxml = "http delete sslcert ipport=$ipV4ssl"
    $KillSSLxml | netsh
}

function DisableHTTP {
    Write-Host "`nINFO: Disabling HTTP XML Access" -ForegroundColor Green
    $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    if ($null -eq $XMLHTTPStatus) {
        New-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -PropertyType DWORD -Value '0' -Force | Out-Null
        $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    }
    if ($null -ne $XMLHTTPStatus) {
        New-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -PropertyType DWORD -Value '0' -Force | Out-Null
        $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    }
    if ($XMLHttpStatus.XmlServicesEnableNonSsl -eq "0") {
        Write-Host "INFO: XML HTTP is Disabled" -ForegroundColor Green
    }
}

function EnableHTTP {
    Write-Host "`nINFO: Enable HTTP XML Access" -ForegroundColor Green
    $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    if ($null -eq $XMLHTTPStatus) {
        New-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -PropertyType DWORD -Value '1' -Force | Out-Null
        $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    }
    if ($null -ne $XMLHTTPStatus) {
        New-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -PropertyType DWORD -Value '1' -Force | Out-Null
        $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    }
    if ($XMLHttpStatus.XmlServicesEnableNonSsl -eq "1") {
        Write-Host "INFO: XML HTTP is Enabled" -ForegroundColor Green
    }
}

function ResetCloudConnectorServices {
    Write-Host "`nINFO: Restarting Citrix Worksapce Cloud Agent System" -ForegroundColor Green
    Get-Service CitrixWorkspaceCloudAgentSystem | Restart-Service -Force -Verbose
    Write-Host "INFO: Service Status:"
    Get-Service CitrixWorkspace* | Select-Object Name, Status | Format-Table
    $RestartComplete = $false
    while (((Get-EventLog Application -Source Citrix* -InstanceId 10000 -after ((Get-Date).AddSeconds(-10))).count -eq 0 ) -and ($RestartComplete -eq $false)) {
        write-host "INFO: Checking for successful transaction with control plane...."
        Start-Sleep 10
        if ((Get-EventLog Application -Source Citrix* -InstanceId 10000 -after ((Get-Date).AddSeconds(-10))).count -gt 0) {
            $RestartComplete = $true
        }
    }
    write-host "INFO: Connected to the control plane!" -ForegroundColor Green
}

function ResetBrokerServices {
    Write-Host "`nINFO: Restarting Broker Services" -ForegroundColor Green
    Get-Service CitrixBrokerService | Restart-Service -Force -Verbose
    Write-Host "INFO: Service Status:"
    Get-Service CitrixBrokerService | Select-Object Name, Status | Format-Table
    $RestartComplete = $false
    while (((Get-EventLog Application -Source Citrix* -InstanceId 506 -after ((Get-Date).AddSeconds(-10))).count -eq 0 ) -and ($RestartComplete -eq $false)) {
        write-host "INFO: Checking for Broker Service Restart...."
        Start-Sleep 10
        if ((Get-EventLog Application -Source Citrix* -InstanceId 506 -after ((Get-Date).AddSeconds(-10))).count -gt 0) {
            $RestartComplete = $true
        }
    }
    write-host "INFO: Broker Service successfully restarted!" -ForegroundColor Green

}

function ValidateSSLStatus {
    Write-Host "INFO: This is a Citrix $BrokerType" -ForegroundColor Cyan
    Write-Host "INFO: Performing SSL Status Validation" -ForegroundColor Green

    $ipV4 = Test-Connection -ComputerName (hostname) -Count 1 | Select-Object -ExpandProperty IPV4Address 
    $ipV4ssl = "$ipV4 :443" -replace " ", ""
    $Results = netsh http show sslcert ipport=$ipV4ssl
    $AppId = $Results | Select-String "Application ID               :"
    $AppId = $AppId -replace "    Application ID               : ", ""
    $Hash = $Results | Select-String "Certificate Hash             :"
    $Hash = $Hash -replace "    Certificate Hash             : ", ""

    if ($Results -match "The system cannot find the file specified") {
        Write-Warning "There is no SSL Certificate Bound to $($ipV4)"
        Write-Host "INFO: SSL Validation Test: ............FAIL" -ForegroundColor Red
    }
    else {
        # Fetching registry key to get the Citrix Broker Service GUID
        New-PSDrive -Name 'HKCR' -PSProvider 'Registry' -Root 'HKEY_CLASSES_ROOT' | Out-Null
        $CBS_Guid = Get-ChildItem 'HKCR:\Installer\Products' -Recurse -Ea 0 | Where-Object { $key = $_; $_.GetValueNames() | ForEach-Object { $key.GetValue($_) } | Where-Object { $_ -like '*Citrix Broker Service*' } } | Select-Object Name
        $CBS_Guid.Name -match "[A-Z0-9]*$" | Out-Null
        $GUID = $Matches[0]

        # Formating the string to look like a GUID with dash ( - )
        [GUID]$GUIDf = "$GUID"
        Write-Host "INFO: Citrix Broker Service GUID for $env:computername is: $GUIDf" -foregroundcolor Cyan 
        # Closing PSDrive
        Remove-PSDrive -Name HKCR
        if ($AppId -like "*$GUIDf*") {
            Write-Host "INFO: A certificate is bound to $($IpV4ssl) with hash: $($Hash) which matches the Citrix Broker GUID $($GUIDf)" -ForegroundColor Cyan
            Write-Host "INFO: SSL Validation Test: ............PASS" -ForegroundColor Green
        }
        elseif ($AppId -notlike "*$GUIDf*") {
            Write-Warning "A Certificate is bound to $($IpV4ssl) with hash: $($Hash), however is not bound to the correct AppId"
            Write-Host "INFO: SSL Validation Test: ............FAIL" -ForegroundColor Red
        }
    }
}

function ValidateHTTPStatus {
    Write-Host "INFO: Performing HTTP Status Validation" -ForegroundColor Green
    $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    if ($XMLHttpStatus.XmlServicesEnableNonSsl -eq "0") {
        Write-Host "INFO: XML HTTP is Disabled" -ForegroundColor Green
        Write-Host "INFO: HTTP Validation Test: ...........PASS" -ForegroundColor Green
    }
    elseif ($XMLHttpStatus.XmlServicesEnableNonSsl -eq "1" -or $null -eq $XMLHttpStatus.XmlServicesEnableNonSsl) {
        Write-Warning "XML HTTP is Enabled"
        Write-Host "INFO: HTTP Validation Test: ...........FAIL" -ForegroundColor Red
    }
}


$CloudConnector = Get-Service 'CitrixWorkspaceCloudAgentSystem' -ErrorAction SilentlyContinue
$DeliveryController = Get-Service 'CitrixBrokerService' -ErrorAction SilentlyContinue

if ($null -ne $CloudConnector) {
    $BrokerType = 'CloudConnector'
}
elseif ($null -ne $DeliveryController) {
    $BrokerType = 'DeliveryController'
}

# Execute
if ($null -eq $BrokerType) {
    Write-Warning "I am neither a Delivery Controller nor a Cloud Connector. Bye Bye"
    Break
}

if ($EnableSSL.IsPresent) {
    EnableSSL
    if ($BrokerType -eq 'CloudConnector') {
        ResetCloudConnectorServices
    }
    if ($BrokerType -eq 'DeliveryController') {
        ResetBrokerServices
    }
}
if ($DisableSSL.IsPresent) {
    DisableSSL
    if ($BrokerType -eq 'CloudConnector') {
        EnableHTTP
        ResetCloudConnectorServices
    }
    if ($BrokerType -eq 'DeliveryController') {
        EnableHTTP
        ResetBrokerServices
    }
}
if ($DisableHTTP.IsPresent) {
    DisableHTTP
    if ($BrokerType -eq 'CloudConnector') {
        ResetCloudConnectorServices
    }
    if ($BrokerType -eq 'DeliveryController') {
        ResetBrokerServices
    }
}
if ($ValidateHTTPStatus.IsPresent) {
    ValidateHTTPStatus
}
if ($ValidateSSLStatus.IsPresent) {
    ValidateSSLStatus
}