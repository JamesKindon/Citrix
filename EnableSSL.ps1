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
Disables the HTTP Listener for XML

.EXAMPLE
PS C:\> .\EnableSSL.ps1 -EnableSSL
The above example will prompt for a certificate, and once selected will create the apporopriate SSL binding.

PS C:\> .\EnableSSL.ps1 -EnableSSL -DisableHTTP
The above example will prompt for a certificate, and once selected will create the apporopriate SSL binding. It will also disable answering XML requests on HTTP

PS C:\> .\EnableSSL.ps1 -DisableHTTP
The abvoe example will Disable answering XML requests on HTTP

PS C:\> .\EnableSSL.ps1 -DisableSSL
The above example will delete the SSL bindings, and enforce HTTP so that the Cloud Connector or Broker isn't left useless

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
    [Switch] $DisableSSL
)

function EnableSSL {
    # Fetching registry key to get the Citrix Broker Service GUID
    New-PSDrive -Name 'HKCR' -PSProvider 'Registry' -Root 'HKEY_CLASSES_ROOT'
    $CBS_Guid = Get-ChildItem 'HKCR:\Installer\Products' -Recurse -Ea 0 | Where-Object { $key = $_; $_.GetValueNames() | ForEach-Object { $key.GetValue($_) } | Where-Object { $_ -like '*Citrix Broker Service*' } } | Select-Object Name
    $CBS_Guid.Name -match "[A-Z0-9]*$"
    $GUID = $Matches[0]
 
    # Formating the string to look like a GUID with dash ( - )
    [GUID]$GUIDf = "$GUID"
    Write-Host -Object "Citrix Broker Service GUID for $env:computername is: $GUIDf" -foregroundcolor "yellow";
    # Closing PSDrive
    Remove-PSDrive -Name HKCR
 
    # Getting local IP address and adding :443 port
    $ipV4 = Test-Connection -ComputerName (hostname) -Count 1 | Select-Object -ExpandProperty IPV4Address 
    $ipV4ssl = "$ipV4 :443" -replace " ", ""
    Write-Host -Object "The IP Address for $env:computername is: $ipV4ssl" -foregroundcolor "green";
 
    # Getting the certificate thumbprint
    #$Thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match "$HostName"}).Thumbprint -join ';';
    $Thumbprint = Get-ChildItem -Path 'Cert:\LocalMachine\My' | Out-GridView -PassThru | Select-Object -ExpandProperty Thumbprint
    if ($null -eq $Thumbprint) {
        Write-Warning "No Cert Selected. Goodbye."
        Break
    }
    Write-Host -Object "Certificate Thumbprint for $env:computername is: $Thumbprint" -foregroundcolor "magenta"; 
 
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
    Write-Host "`nDisabling HTTP XML Access" -ForegroundColor Green
    $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    if ($null -eq $XMLHTTPStatus) {
        New-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -PropertyType DWORD -Value '0' -Force | Out-Null
        $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    }
    if ($null -ne $XMLHTTPStatus) {
        New-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -PropertyType DWORD -Value '0' -Force | Out-Null
        $XMLHTTPStatus = Get-ItemProperty -Path 'hklm:\Software\citrix\desktopserver' -Name 'XmlServicesEnableNonSsl' -ErrorAction SilentlyContinue
    }
    if ($XMLHttpStatus.XmlServicesEnableNonSsl -eq "1") {
        Write-Host "XML HTTP is Disabled" -ForegroundColor Green
    }
}

function EnableHTTP {
    Write-Host "`nEnable HTTP XML Access" -ForegroundColor Green
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
        Write-Host "XML HTTP is Enabled" -ForegroundColor Green
    }
}

function ResetCloudConnectorServices {
    Write-Host "`nRestarting Citrix Worksapce Cloud Agent System" -ForegroundColor Green
    Get-Service CitrixWorkspaceCloudAgentSystem | Restart-Service -Force -Verbose
    Write-Host "Service Status:" -ForegroundColor Green
    Get-Service CitrixWorkspace* | Select-Object Name, Status | Format-Table
    $RestartComplete = $false
    while (((Get-EventLog Application -Source Citrix* -InstanceId 10000 -after ((Get-Date).AddSeconds(-10))).count -eq 0 ) -and ($RestartComplete -eq $false)) {
        write-host "Checking for successful transaction with control plane...."
        Start-Sleep 10
        if ((Get-EventLog Application -Source Citrix* -InstanceId 10000 -after ((Get-Date).AddSeconds(-10))).count -gt 0) {
            $RestartComplete = $true
        }
    }
    write-host "Connected to the control plane!"
}

function ResetBrokerServices {
    Write-Host "`nRestarting Broker Services" -ForegroundColor Green
    Get-Service CitrixBrokerService | Restart-Service -Force -Verbose
    Write-Host "Service Status:" -ForegroundColor Green
    Get-Service CitrixBrokerService | Select-Object Name, Status | Format-Table
    $RestartComplete = $false
    while (((Get-EventLog Application -Source Citrix* -InstanceId 506 -after ((Get-Date).AddSeconds(-10))).count -eq 0 ) -and ($RestartComplete -eq $false)) {
        write-host "Checking for Broker Service Restart...."
        Start-Sleep 10
        if ((Get-EventLog Application -Source Citrix* -InstanceId 506 -after ((Get-Date).AddSeconds(-10))).count -gt 0) {
            $RestartComplete = $true
        }
    }
    write-host "Broker Service successfully restarted!" 

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