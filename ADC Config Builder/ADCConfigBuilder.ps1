Param(
    [Parameter(Mandatory = $false)]
    [Switch]$GeneralConfig,
    [Parameter(Mandatory = $false)]
    [Switch]$LBWEM,
    [Parameter(Mandatory = $false)]
    [Switch]$LBStoreFront,
    [Parameter(Mandatory = $false)]
    [Switch]$LBDirector,
    [Parameter(Mandatory = $false)]
    [Switch]$LBADDS,
    [Parameter(Mandatory = $false)]
    [Switch]$AuthProfile,
    [Parameter(Mandatory = $false)]
    [Switch]$LBXML,
    [Parameter(Mandatory = $false)]
    [Switch]$LBAzureMFA,
    [Parameter(Mandatory = $True)]
    [String]$CSV,
    [Parameter(Mandatory = $False)]
    [String]$ConfigFile = "~\Desktop\Config.txt",
    [Parameter(Mandatory = $false)]
    [Switch]$ShowConfig
)

# ====================================================================================================================================================
# Setup
# ====================================================================================================================================================
Write-Verbose "Importing CSV" -Verbose
$Config = Import-CSV -Path $CSV
Write-Verbose "Output Config file is: $ConfigFile" -Verbose

#region variables
# ====================================================================================================================================================
# Variables - Set Per Customer
# ====================================================================================================================================================

#-----------------------------------------------------------------------------------------------------------------------------------------------------
# ADC Setup
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$TimeZone                       =   ($Config | Where-Object { $_.Setting -eq "TimeZone" }).Value
$DNSSuffix                      =   ($Config | Where-Object { $_.Setting -eq "DNSSuffix" }).Value
$HostName                       =   ($Config | Where-Object { $_.Setting -eq "HostName" }).Value
$SystemGroup                    =   ($Config | Where-Object { $_.Setting -eq "SystemGroup" }).Value
$NSIP                           =   ($Config | Where-Object { $_.Setting -eq "NSIP" }).Value
$NSMask                         =   ($Config | Where-Object { $_.Setting -eq "NSMask" }).Value
$NTPServer                      =   ($Config | Where-Object { $_.Setting -eq "NTPServer" }).Value
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# ADDS Setup
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$AD_Server1_Name                =   ($Config | Where-Object { $_.Setting -eq "AD_Server1_Name" }).Value
$AD_Server1_IP                  =   ($Config | Where-Object { $_.Setting -eq "AD_Server1_IP" }).Value
$AD_Server2_Name                =   ($Config | Where-Object { $_.Setting -eq "AD_Server2_Name" }).Value
$AD_Server2_IP                  =   ($Config | Where-Object { $_.Setting -eq "AD_Server2_IP" }).Value
$lbvs_DS_VIP_IP                 =   ($Config | Where-Object { $_.Setting -eq "lbvs_DS_VIP_IP" }).Value

$mon_DNS_53                     =   ($Config | Where-Object { $_.Setting -eq "mon_DNS_53" }).Value
$mon_LDAP                       =   ($Config | Where-Object { $_.Setting -eq "mon_LDAP" }).Value
$svcg_DNS_53                    =   ($Config | Where-Object { $_.Setting -eq "svcg_DNS_53" }).Value
$svcg_LDAP_389                  =   ($Config | Where-Object { $_.Setting -eq "svcg_LDAP_389" }).Value
$svcg_LDAPS_636                 =   ($Config | Where-Object { $_.Setting -eq "svcg_LDAPS_636" }).Value
$lbvs_DNS_53                    =   ($Config | Where-Object { $_.Setting -eq "lbvs_DNS_53" }).Value
$lbvs_LDAP_389                  =   ($Config | Where-Object { $_.Setting -eq "lbvs_LDAP_389" }).Value
$lbvs_LDAP_636                  =   ($Config | Where-Object { $_.Setting -eq "lbvs_LDAP_636" }).Value
$LDAPActionName                 =   ($Config | Where-Object { $_.Setting -eq "LDAPActionName" }).Value
$LDAPPolicyName                 =   ($Config | Where-Object { $_.Setting -eq "LDAPPolicyName" }).Value
$LDAPActionNameInsecure         =   ($Config | Where-Object { $_.Setting -eq "LDAPActionNameInsecure" }).Value
$LDAPPolicyNameInsecure         =   ($Config | Where-Object { $_.Setting -eq "LDAPPolicyNameInsecure" }).Value
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# Auth Profile Setup
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$LDAPBase                       =   ($Config | Where-Object { $_.Setting -eq "LDAPBase" }).Value
$LDAPBindDN                     =   ($Config | Where-Object { $_.Setting -eq "LDAPBindDN" }).Value
$LDAPBindPW                     =   ($Config | Where-Object { $_.Setting -eq "LDAPBindPW" }).Value
$LDAPSearchFilter               =   ($Config | Where-Object { $_.Setting -eq "LDAPSearchFilter" }).Value
$DNS_Query                      =   ($Config | Where-Object { $_.Setting -eq "DNS_Query" }).Value
$DNS_Query_IP                   =   ($Config | Where-Object { $_.Setting -eq "DNS_Query_IP" }).Value
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# WEM Load Balancing
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$WEM_Broker1_Name               =   ($Config | Where-Object { $_.Setting -eq "WEM_Broker1_Name" }).Value
$WEM_Broker1_IP                 =   ($Config | Where-Object { $_.Setting -eq "WEM_Broker1_IP" }).Value
$WEM_Broker2_Name               =   ($Config | Where-Object { $_.Setting -eq "WEM_Broker2_Name" }).Value
$WEM_Broker2_IP                 =   ($Config | Where-Object { $_.Setting -eq "WEM_Broker2_IP" }).Value
$Lbvs_WEM_VIP_IP                =   ($Config | Where-Object { $_.Setting -eq "Lbvs_WEM_VIP_IP" }).Value

$svcg_WEM_brokerAdmin           =   ($Config | Where-Object { $_.Setting -eq "svcg_WEM_brokerAdmin" }).Value
$svcg_WEM_AgentSync             =   ($Config | Where-Object { $_.Setting -eq "svcg_WEM_AgentSync" }).Value
$svcg_WEM_AgentBroker           =   ($Config | Where-Object { $_.Setting -eq "svcg_WEM_AgentBroker" }).Value
$svcg_WEM_AgentSyncCacheData    =   ($Config | Where-Object { $_.Setting -eq "svcg_WEM_AgentSyncCacheData" }).Value
$lbvs_WEM_BrokerAdmin           =   ($Config | Where-Object { $_.Setting -eq "lbvs_WEM_BrokerAdmin" }).Value
$lbvs_WEM_AgentBroker           =   ($Config | Where-Object { $_.Setting -eq "lbvs_WEM_AgentBroker" }).Value
$lbvs_WEM_AgentSync             =   ($Config | Where-Object { $_.Setting -eq "lbvs_WEM_AgentSync" }).Value
$lbvs_WEM_AgentSyncCacheData    =   ($Config | Where-Object { $_.Setting -eq "lbvs_WEM_AgentSyncCacheData" }).Value
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# StoreFront Load Balancing
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$SF_Server1_Name                =   ($Config | Where-Object { $_.Setting -eq "SF_Server1_Name" }).Value
$SF_Server1_IP                  =   ($Config | Where-Object { $_.Setting -eq "SF_Server1_IP" }).Value
$SF_Server2_Name                =   ($Config | Where-Object { $_.Setting -eq "SF_Server2_Name" }).Value
$SF_Server2_IP                  =   ($Config | Where-Object { $_.Setting -eq "SF_Server2_IP" }).Value
$Monitor_SF_Store               =   ($Config | Where-Object { $_.Setting -eq "Monitor_SF_Store" }).Value
$Lbvs_SF_VIP_IP                 =   ($Config | Where-Object { $_.Setting -eq "Lbvs_SF_VIP_IP" }).Value
$SF_RedirectURL                 =   ($Config | Where-Object { $_.Setting -eq "SF_RedirectURL" }).Value
$SF_RedirUrl                    =   ($Config | Where-Object { $_.Setting -eq "SF_RedirUrl" }).Value
$SF_ResPol_Pattern              =   ($Config | Where-Object { $_.Setting -eq "SF_ResPol_Pattern" }).Value

$Monitor_StoreFront             =   ($Config | Where-Object { $_.Setting -eq "Monitor_StoreFront" }).Value                                                   
$svcg_Citrix_SF_80              =   ($Config | Where-Object { $_.Setting -eq "svcg_Citrix_SF_80" }).Value                                                 
$svcg_Citrix_SF_443             =   ($Config | Where-Object { $_.Setting -eq "svcg_Citrix_SF_443" }).Value                                               
$lbvs_SF_VIP_Name               =   ($Config | Where-Object { $_.Setting -eq "lbvs_SF_VIP_Name" }).Value                                                  
$SF_RespAct                     =   ($Config | Where-Object { $_.Setting -eq "SF_RespAct" }).Value                                                
$SF_ResPol                      =   ($Config | Where-Object { $_.Setting -eq "SF_ResPol" }).Value    
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# Director Load Balancing
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$Dir_Server1_Name               =   ($Config | Where-Object { $_.Setting -eq "Dir_Server1_Name" }).Value
$Dir_Server1_IP                 =   ($Config | Where-Object { $_.Setting -eq "Dir_Server1_IP" }).Value
$Dir_Server2_Name               =   ($Config | Where-Object { $_.Setting -eq "Dir_Server2_Name" }).Value
$Dir_Server2_IP                 =   ($Config | Where-Object { $_.Setting -eq "Dir_Server2_IP" }).Value
$Lbvs_Dir_VIP_IP                =   ($Config | Where-Object { $_.Setting -eq "Lbvs_Dir_VIP_IP" }).Value
$Dir_RedirectURL                =   ($Config | Where-Object { $_.Setting -eq "Dir_RedirectURL" }).Value
$Dir_Cert                       =   ($Config | Where-Object { $_.Setting -eq "Dir_Cert" }).Value

$svcg_Citrix_Director_80        =   ($Config | Where-Object { $_.Setting -eq "svcg_Citrix_Director_80" }).Value                                             
$svcg_Citrix_Director_443       =   ($Config | Where-Object { $_.Setting -eq "svcg_Citrix_Director_443" }).Value                                           
$lbvs_Dir_VIP_Name              =   ($Config | Where-Object { $_.Setting -eq "lbvs_Dir_VIP_Name" }).Value                                           
$Monitor_Director               =   ($Config | Where-Object { $_.Setting -eq "Monitor_Director" }).Value                                                         
$Dir_RespAct                    =   ($Config | Where-Object { $_.Setting -eq "Dir_RespAct" }).Value                                               
$Dir_RedirURL                   =   ($Config | Where-Object { $_.Setting -eq "Dir_RedirURL" }).Value                                 
$Dir_ResPol                     =   ($Config | Where-Object { $_.Setting -eq "Dir_ResPol" }).Value                                                         
$Dir_Respol_Pattern             =   ($Config | Where-Object { $_.Setting -eq "Dir_Respol_Pattern" }).Value 
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# Controller XML Load Balancing
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$Controller1_Name               =   ($Config | Where-Object { $_.Setting -eq "Controller1_Name" }).Value
$Controller1_IP                 =   ($Config | Where-Object { $_.Setting -eq "Controller1_IP" }).Value
$Controller2_Name               =   ($Config | Where-Object { $_.Setting -eq "Controller2_Name" }).Value
$Controller2_IP                 =   ($Config | Where-Object { $_.Setting -eq "Controller2_IP" }).Value
$lbvs_Controller_XML_IP         =   ($Config | Where-Object { $_.Setting -eq "lbvs_Controller_XML_IP" }).Value
$Controller_Cert                =   ($Config | Where-Object { $_.Setting -eq "Controller_Cert" }).Value

$svcg_Controller_XML_80         =   ($Config | Where-Object { $_.Setting -eq "svcg_Controller_XML_80" }).Value
$svcg_Controller_XML_443        =   ($Config | Where-Object { $_.Setting -eq "svcg_Controller_XML_443" }).Value
$lbvs_Controller_XML_80         =   ($Config | Where-Object { $_.Setting -eq "lbvs_Controller_XML_80" }).Value
$lbvs_Controller_XML_443        =   ($Config | Where-Object { $_.Setting -eq "lbvs_Controller_XML_443" }).Value
$mon_Controller_XML             =   ($Config | Where-Object { $_.Setting -eq "mon_Controller_XML" }).Value
$mon_Controller_XML_Sec         =   ($Config | Where-Object { $_.Setting -eq "mon_Controller_XML_Sec" }).Value
#-----------------------------------------------------------------------------------------------------------------------------------------------------
# Azure MFA NPS Load Balancing
#-----------------------------------------------------------------------------------------------------------------------------------------------------
$AzureMFA_Server1_Name          =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_Server1_Name" }).Value
$AzureMFA_Server1_IP            =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_Server1_IP" }).Value
$AzureMFA_Server2_Name          =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_Server2_Name" }).Value
$AzureMFA_Server2_IP            =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_Server2_IP" }).Value
$Lbvs_AzureMFA_VIP_IP           =   ($Config | Where-Object { $_.Setting -eq "Lbvs_AzureMFA_VIP_IP" }).Value
$AzureMFA_Mon_UserName          =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_Mon_UserName" }).Value
$AzureMFA_Mon_Password          =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_Mon_Password" }).Value
$AzureMFA_RADIUS_Key            =   ($Config | Where-Object { $_.Setting -eq "AzureMFA_RADIUS_Key" }).Value

$svcg_AzureMFA_Radius_1812      =   ($Config | Where-Object { $_.Setting -eq "svcg_AzureMFA_Radius_1812" }).Value                                           
$lbvs_AzureMFA_VIP_Name         =   ($Config | Where-Object { $_.Setting -eq "lbvs_AzureMFA_VIP_Name" }).Value                                            
$Monitor_AzureMFA               =   ($Config | Where-Object { $_.Setting -eq "Monitor_AzureMFA" }).Value
#-----------------------------------------------------------------------------------------------------------------------------------------------------

#endregion

if (Test-Path $ConfigFile) {
    Remove-Item $ConfigFile -Force
}

#region ADC General
if ($GeneralConfig.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing General ADC Settings" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # ADC General Configurations
    # ============================================================================

    # General Setup
    Write-Verbose "Setting ADC General Paramaters" -Verbose
    Write-Output "set ns param -timezone $TimeZone" | Out-File -Append $ConfigFile
    Write-Output "add dns suffix $DNSSuffix" | Out-File -Append $ConfigFile
    Write-Output "set aaa parameter -maxAAAUsers 4294967295" | Out-File -Append $ConfigFile
    Write-Output "set ns hostName $HostName" | Out-File -Append $ConfigFile
    Write-Output "add system group '$SystemGroup'" | Out-File -Append $ConfigFile
    Write-Output "set ns config -IPAddress $NSIP -netmask $NSMask" | Out-File -Append $ConfigFile
    Write-Output "set ns tcpbufParam -size 256 -memLimit 256" | Out-File -Append $ConfigFile
    Write-Output "set ns httpProfile nshttp_default_profile -dropInvalReqs ENABLED -markHttp09Inval ENABLED" | Out-File -Append $ConfigFile
    Write-Output "set ns ip $NSIP -mgmtAccess ENABLED -gui SECUREONLY" | Out-File -Append $ConfigFile
    Write-Output "add ntp server $NTPServer -minpoll 6 -maxpoll 10" | Out-File -Append $ConfigFile
    Write-Output "enable ntp sync" | Out-File -Append $ConfigFile

    # SSL Global Parameters
    Write-Verbose "Setting ADC SSL Paramaters" -Verbose
    Write-Output "set ssl parameter -denySSLReneg NONSECURE" | Out-File -Append $ConfigFile

    # Load Balancing Global Parameters
    Write-Verbose "Setting ADC Load Balancing Global Parameters" -Verbose
    Write-Output "set ns param -cookieversion 1" | Out-File -Append $ConfigFile
    Write-Output "set ns tcpParam -WS ENABLED -SACK ENABLED" | Out-File -Append $ConfigFile
    Write-Output "set ns httpParam -dropInvalReqs ON" | Out-File -Append $ConfigFile
    Write-Output "set ns param -cookieversion 1" | Out-File -Append $ConfigFile

    # SSL Cipher Group
    Write-Verbose "Setting ADC SSL Cipher Group" -Verbose
    Write-Output "add ssl cipher ssllabs-smw-q2-2018" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.3-AES256-GCM-SHA384 -cipherPriority 1" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.3-CHACHA20-POLY1305-SHA256 -cipherPriority 2" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.3-AES128-GCM-SHA256 -cipherPriority 3" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-ECDSA-AES128-GCM-SHA256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-ECDSA-AES256-GCM-SHA384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-ECDSA-AES128-SHA256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-ECDSA-AES256-SHA384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-ECDHE-ECDSA-AES128-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-ECDHE-ECDSA-AES256-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-RSA-AES128-GCM-SHA256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-RSA-AES256-GCM-SHA384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-RSA-AES-128-SHA256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-ECDHE-RSA-AES-256-SHA384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-ECDHE-RSA-AES128-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-ECDHE-RSA-AES256-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-DHE-RSA-AES128-GCM-SHA256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1.2-DHE-RSA-AES256-GCM-SHA384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-DHE-RSA-AES-128-CBC-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-DHE-RSA-AES-256-CBC-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-AES-128-CBC-SHA" | Out-File -Append $ConfigFile
    Write-Output "bind ssl cipher ssllabs-smw-q2-2018 -cipherName TLS1-AES-256-CBC-SHA" | Out-File -Append $ConfigFile

    #Strict Transport Security – Rewrite Policy
    Write-Verbose "Setting ADC Strict Transport Security Parameters" -Verbose
    Write-Output "enable ns feature rewrite" | Out-File -Append $ConfigFile
    Write-Output "add rewrite action insert_STS_header insert_http_header Strict-Transport-Security ""\""max-age=157680000\""""" | Out-File -Append $ConfigFile
    Write-Output "add rewrite policy insert_STS_header true insert_STS_header" | Out-File -Append $ConfigFile
    
    # CTX207005 Performance Issues with NetScaler MPX SSL
    Write-Output "add ns tcpProfile tcp_test -WS ENABLED -SACK ENABLED -maxBurst 20 -initialCwnd 8 -bufferSize 4096000 -flavor BIC -dynamicReceiveBuffering DISABLED -sendBuffsize 4096000" | Out-File -Append $ConfigFile

    # Configure CPU Yield - https://support.citrix.com/article/CTX229555
    Write-Output "set ns vpxparam -cpuyield YES" | Out-File -Append $ConfigFile

    #SSL Redirect – Responder Method
    Write-Verbose "Setting ADC AlwaysUp Responder" -Verbose
    Write-Output "enable ns feature RESPONDER" | Out-File -Append $ConfigFile
    Write-Output "add server 1.1.1.1 1.1.1.1" | Out-File -Append $ConfigFile
    Write-Output "add service AlwaysUp 1.1.1.1 HTTP 80 -healthMonitor NO" | Out-File -Append $ConfigFile

    Write-Output "add responder action http_to_ssl_redirect_responderact redirect ""\""https://\"" + HTTP.REQ.HOSTNAME.HTTP_URL_SAFE + HTTP.REQ.URL.PATH_AND_QUERY.HTTP_URL_SAFE"" -responseStatusCode 302" | Out-File -Append $ConfigFile
    Write-Output "add responder policy http_to_ssl_redirect_responderpol HTTP.REQ.IS_VALID http_to_ssl_redirect_responderact" | Out-File -Append $ConfigFile

}
#endregion

#region WEM Load Balancing
if ($LBWEM.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing WEM Load Balancing" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # ADC WEM Load Balancing
    # ============================================================================

    # WEM Configurations
    Write-Verbose "Configure SPN! setspn -U -S Norskale/BrokerService svc_citrix_wem" -Verbose

    # Servers
    Write-Verbose "Setting WEM Broker Name: $WEM_Broker1_Name" -Verbose
    Write-Verbose "Setting WEM Broker $WEM_Broker1_Name IP: $WEM_Broker1_IP" -Verbose
    Write-Verbose "Setting WEM Broker Name: $WEM_Broker2_Name" -Verbose
    Write-Verbose "Setting WEM Broker $WEM_Broker2_Name IP: $WEM_Broker2_IP" -Verbose

    Write-Output "add server $WEM_Broker1_Name $WEM_Broker1_IP" | Out-File -Append $ConfigFile
    Write-Output "add server $WEM_Broker2_Name $WEM_Broker2_IP" | Out-File -Append $ConfigFile

    # Service Groups
    Write-Verbose "Setting WEM Service Group Name: $svcg_WEM_brokerAdmin" -Verbose
    Write-Verbose "Setting WEM Service Group Name: $svcg_WEM_AgentSync" -Verbose
    Write-Verbose "Setting WEM Service Group Name: $svcg_WEM_AgentBroker" -Verbose
    Write-Verbose "Setting WEM Service Group Name: $svcg_WEM_AgentSyncCacheData" -Verbose

    Write-Output "add serviceGroup $svcg_WEM_BrokerAdmin TCP -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport YES -cltTimeout 9000 -svrTimeout 9000 -CKA NO -TCPB NO -CMP NO" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_WEM_AgentBroker TCP -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport YES -cltTimeout 9000 -svrTimeout 9000 -CKA NO -TCPB NO -CMP NO" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_WEM_AgentSync TCP -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport YES -cltTimeout 9000 -svrTimeout 9000 -CKA NO -TCPB NO -CMP NO" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_WEM_AgentSyncCacheData TCP -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport YES -cltTimeout 9000 -svrTimeout 9000 -CKA NO -TCPB NO -CMP NO" | Out-File -Append $ConfigFile

    Write-Output "bind servicegroup $svcg_WEM_BrokerAdmin $WEM_Broker1_Name 8284" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_BrokerAdmin $WEM_Broker2_Name 8284" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_AgentBroker $WEM_Broker1_Name 8286" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_AgentBroker $WEM_Broker2_Name 8286" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_AgentSync $WEM_Broker1_Name 8285" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_AgentSync $WEM_Broker2_Name 8285" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_AgentSyncCacheData $WEM_Broker1_Name 8288" | Out-File -Append $ConfigFile
    Write-Output "bind servicegroup $svcg_WEM_AgentSyncCacheData $WEM_Broker2_Name 8288" | Out-File -Append $ConfigFile

    # Load Balancers
    Write-Verbose "Setting WEM Load Balancer VIP IP: $Lbvs_WEM_VIP_IP" -Verbose
    Write-Verbose "Setting WEM Load Balancer Name: $lbvs_WEM_BrokerAdmin" -Verbose
    Write-Verbose "Setting WEM Load Balancer Name: $lbvs_WEM_AgentBroker" -Verbose
    Write-Verbose "Setting WEM Load Balancer Name: $lbvs_WEM_AgentSync" -Verbose
    Write-Verbose "Setting WEM Load Balancer Name: $lbvs_WEM_AgentSyncCacheData" -Verbose

    Write-Output "add lb vserver $lbvs_WEM_BrokerAdmin TCP $Lbvs_WEM_VIP_IP 8284 -persistenceType NONE -cltTimeout 9000" | Out-File -Append $ConfigFile
    Write-Output "add lb vserver $lbvs_WEM_AgentBroker TCP $Lbvs_WEM_VIP_IP 8286 -persistenceType NONE -cltTimeout 9000" | Out-File -Append $ConfigFile
    Write-Output "add lb vserver $lbvs_WEM_AgentSync TCP $Lbvs_WEM_VIP_IP 8285 -persistenceType NONE -cltTimeout 9000" | Out-File -Append $ConfigFile
    Write-Output "add lb vserver $lbvs_WEM_AgentSyncCacheData TCP $Lbvs_WEM_VIP_IP 8288 -persistenceType NONE -cltTimeout 9000" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_WEM_BrokerAdmin $svcg_WEM_BrokerAdmin" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_WEM_AgentBroker $svcg_WEM_AgentBroker" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_WEM_AgentSync $svcg_WEM_AgentSync" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_WEM_AgentSyncCacheData $svcg_WEM_AgentSyncCacheData" | Out-File -Append $ConfigFile

}
#endregion

#region StoreFront Load Balancing
if ($LBStoreFront.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing StoreFront Load Balancing" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # ADC StoreFront Load Balancing
    # ============================================================================

    # Servers
    Write-Verbose "Setting StoreFront Server Name: $SF_Server1_Name" -Verbose
    Write-Verbose "Setting StoreFront Server $SF_Server1_Name IP: $SF_Server1_IP" -Verbose
    Write-Verbose "Setting StoreFront Server Name: $SF_Server2_Name" -Verbose
    Write-Verbose "Setting StoreFront Server $SF_Server2_Name IP: $SF_Server2_IP" -Verbose

    Write-Output "add server $SF_Server1_Name $SF_Server1_IP -comment ""Citrix StoreFront""" | Out-File -Append $ConfigFile
    Write-Output "add server $SF_Server2_Name $SF_Server2_IP -comment ""Citrix StoreFront""" | Out-File -Append $ConfigFile

    # Monitors
    Write-Verbose "Setting StoreFront Monitor Name: $Monitor_StoreFront" -Verbose
    Write-Output "add lb monitor $Monitor_StoreFront StoreFront -scriptName nssf.pl -dispatcherIP 127.0.0.1 -dispatcherPort 3013 -secure YES -storename $Monitor_SF_Store" | Out-File -Append $ConfigFile

    # Service Groups
    Write-Verbose "Setting StoreFront 80 Service Group Name: $svcg_Citrix_SF_80" -Verbose
    Write-Verbose "Setting StoreFront 443 Service Group Name: $svcg_Citrix_SF_443" -Verbose

    Write-Output "add serviceGroup $svcg_Citrix_SF_80 HTTP -comment ""Citrix StoreFront Service Group""" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_Citrix_SF_443 SSL -maxClient 0 -maxReq 0 -cip ENABLED X-Forwarded-For -usip NO -useproxyport YES -cltTimeout 180 -svrTimeout 360 -CKA NO -TCPB NO -CMP NO" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_SF_80 $SF_Server1_Name 80" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_SF_80 $SF_Server2_Name 80" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_SF_443 $SF_Server1_Name 443" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_SF_443 $SF_Server2_Name 443" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_Citrix_SF_443 -monitorName $Monitor_StoreFront" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Citrix_SF_443 -eccCurveName P_256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Citrix_SF_443 -eccCurveName P_384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Citrix_SF_443 -eccCurveName P_224" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Citrix_SF_443 -eccCurveName P_521" | Out-File -Append $ConfigFile


    # Load Balancers
    Write-Verbose "Setting StoreFront Load Balancer VIP IP: $Lbvs_SF_VIP_IP" -Verbose
    Write-Verbose "Setting StoreFront Load Balancer Name: $lbvs_SF_VIP_Name" -Verbose
    Write-Verbose "Setting StoreFront Load Balancer Redirect URL: $SF_RedirectURL" -Verbose
    Write-Verbose "Setting StoreFront Load Balancer Certificate : $SF_Cert" -Verbose

    Write-Output "add lb vserver $lbvs_SF_VIP_Name SSL $Lbvs_SF_VIP_IP 443 -comment ""Citrix StoreFront Virtual Server"" -persistenceType SOURCEIP -timeout 60 -cltTimeout 180 -redirectFromPort 80 -httpsRedirectUrl ""$SF_RedirectURL""" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_SF_VIP_Name $svcg_Citrix_SF_443" | Out-File -Append $ConfigFile

    #Bind Strict Transport Security
    Write-Output "bind lb vserver $lbvs_SF_VIP_Name -policyName insert_STS_header -priority 100 -gotoPriorityExpression END -type RESPONSE" | Out-File -Append $ConfigFile

    # Responder Policies
    Write-Verbose "Setting StoreFront Responder Action Name: $SF_RespAct" -Verbose
    Write-Verbose "Setting StoreFront Responder Action Redirection URL: $SF_RedirURL" -Verbose
    Write-Output "add responder action $SF_RespAct redirect $SF_RedirUrl -responseStatusCode 302" | Out-File -Append $ConfigFile
    
    Write-Verbose "Setting StoreFront Responder Policy Name: $SF_ResPol" -Verbose
    Write-Verbose "Setting StoreFront Responder Policy Pattern: $SF_Respol_Pattern" -Verbose
    Write-Output "add responder policy $SF_ResPol $SF_ResPol_Pattern $SF_RespAct" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_SF_VIP_Name -policyName $SF_ResPol -priority 100 -gotoPriorityExpression END -type REQUEST" | Out-File -Append $ConfigFile

    # SSL Certs
    Write-Output "bind sslvserver $lbvs_SF_VIP_Name -certkeyName $SF_Cert" | Out-File -Append $ConfigFile
    Write-Output "set ssl vserver $lbvs_SF_VIP_Name -ssl3 DISABLED -tls12 ENABLED -HSTS ENABLED -maxage 1576800000" | Out-File -Append $ConfigFile
    Write-Output "unbind ssl vserver $lbvs_SF_VIP_Name -cipherName DEFAULT" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_SF_VIP_Name -cipherName add ssl cipher ssllabs-smw-q2-2018" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_SF_VIP_Name -eccCurveName P_256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_SF_VIP_Name -eccCurveName P_384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_SF_VIP_Name -eccCurveName P_224" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_SF_VIP_Name -eccCurveName P_521" | Out-File -Append $ConfigFile
}
#endregion

#region Director Load Balancing
if ($LBDirector.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing Director Load Balancing" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # ADC Director Load Balancing
    # ============================================================================

    # Servers
    Write-Verbose "Setting Director Server Name: $Dir_Server1_Name" -Verbose
    Write-Verbose "Setting Director Server $Dir_Server1_Name IP: $Dir_Server1_IP" -Verbose
    Write-Verbose "Setting Director Server Name: $Dir_Server2_Name" -Verbose
    Write-Verbose "Setting Director Server $Dir_Server2_Name IP: $Dir_Server2_IP" -Verbose

    Write-Output "add server $Dir_Server1_Name $Dir_Server1_IP -comment ""Citrix Controller""" | Out-File -Append $ConfigFile
    Write-Output "add server $Dir_Server2_Name $Dir_Server2_IP -comment ""Citrix Controller""" | Out-File -Append $ConfigFile

    # Monitors
    Write-Verbose "Setting Director Monitor Name: $Monitor_Director " -Verbose
    Write-Output "add lb monitor $Monitor_Director HTTP -respCode 200 302 -httpRequest ""GET /Director/LogOn.aspx?cc=true"" -LRTM DISABLED -secure YES" | Out-File -Append $ConfigFile

    #Service Groups
    Write-Verbose "Setting Director 80 Service Group Name: $svcg_Citrix_Director_80" -Verbose
    Write-Verbose "Setting Director 443 Service Group Name: $svcg_Citrix_Director_443" -Verbose

    Write-Output "add serviceGroup $svcg_Citrix_Director_80 HTTP -comment ""Citrix Director Service Group""" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_Citrix_Director_443 SSL -comment ""Citrix Director Service Group""" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_Citrix_Director_80 $Dir_Server1_Name 80" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_Director_80 $Dir_Server2_Name 80" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_Director_443 $Dir_Server1_Name 443" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Citrix_Director_443 $Dir_Server2_Name 443" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_Citrix_Director_443 -monitorName $Monitor_Director" | Out-File -Append $ConfigFile

    #Load Balancers
    Write-Verbose "Setting Director Load Balancer VIP IP: $Lbvs_Dir_VIP_IP" -Verbose
    Write-Verbose "Setting Director Load Balancer Name: $lbvs_Dir_VIP_Name" -Verbose
    Write-Verbose "Setting Director Load Balancer Redirect URL: $Dir_RedirectURL" -Verbose
    Write-Verbose "Setting Director Load Balancer Certificate: $Dir_Cert" -Verbose

    Write-Output "add lb vserver $lbvs_Dir_VIP_Name SSL $Lbvs_Dir_VIP_IP 443 -comment ""Citrix Director Virtual Server"" -persistenceType COOKIEINSERT -timeout 0 -persistenceBackup SOURCEIP -backupPersistenceTimeout 245 -cltTimeout 180 -redirectFromPort 80 -httpsRedirectUrl ""$Dir_RedirectURL""" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_Dir_VIP_Name $svcg_Citrix_Director_443" | Out-File -Append $ConfigFile

    # Responder Policies
    Write-Verbose "Setting Director Responder Action Name: $Dir_RespAct" -Verbose
    Write-Verbose "Setting Director Responder Action Redirection URL: $Dir_RedirURL" -Verbose
    Write-Output "add responder action $Dir_RespAct redirect $Dir_RedirURL -responseStatusCode 302" | Out-File -Append $ConfigFile

    Write-Verbose "Setting Director Responder Policy Name: $Dir_ResPol" -Verbose
    Write-Verbose "Setting Director Responder Policy Pattern: $Dir_Respol_Pattern" -Verbose
    Write-Output "add responder policy $Dir_ResPol $Dir_Respol_Pattern $Dir_RespAct" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_Dir_VIP_Name -policyName $Dir_ResPol -priority 100 -gotoPriorityExpression END -type REQUEST" | Out-File -Append $ConfigFile

    # SSL
    Write-Output "bind sslvserver $lbvs_Dir_VIP_Name -certkeyName $Dir_Cert" | Out-File -Append $ConfigFile

    Write-Output "set ssl vserver $lbvs_Dir_VIP_Name -ssl3 DISABLED -tls12 ENABLED -HSTS ENABLED -maxage 157680000" | Out-File -Append $ConfigFile
    Write-Output "unbind ssl vserver $lbvs_Dir_VIP_Name -cipherName DEFAULT" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Dir_VIP_Name -cipherName add ssl cipher ssllabs-smw-q2-2018" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Dir_VIP_Name -eccCurveName P_256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Dir_VIP_Name -eccCurveName P_384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Dir_VIP_Name -eccCurveName P_224" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Dir_VIP_Name -eccCurveName P_521" | Out-File -Append $ConfigFile

    #Bind Strict Transport Security
    Write-Output "bind lb vserver $lbvs_Dir_VIP_Name -policyName insert_STS_header -priority 100 -gotoPriorityExpression END -type RESPONSE" | Out-File -Append $ConfigFile

}
#endregion

#region ADDS
if ($LBADDS.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing ADDS Load Balancing" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # ADDS Load Balancing
    # ============================================================================
    
    $LDAPServerIP = $lbvs_DS_VIP_IP

    #Server
    Write-Verbose "Setting AD Controller Name: $AD_Server1_Name" -Verbose
    Write-Verbose "Setting AD Controller IP $AD_Server1_Name IP: $AD_Server1_IP" -Verbose
    Write-Verbose "Setting AD Controller Name: $AD_Server2_Name" -Verbose
    Write-Verbose "Setting AD Controller IP $AD_Server2_Name IP: $AD_Server2_IP" -Verbose

    Write-Output "add server $AD_Server1_Name $AD_Server1_IP -comment ""Domain Controller""" | Out-File -Append $ConfigFile
    Write-Output "add server $AD_Server2_Name $AD_Server2_IP -comment ""Domain Controller""" | Out-File -Append $ConfigFile

    #Monitors
    Write-Output "add lb monitor $mon_LDAP LDAP -scriptName nsldap.pl -dispatcherIP 127.0.0.1 -dispatcherPort 3013 -password $LDAPBindPW -encrypted -encryptmethod ENCMTHD_3 -LRTM DISABLED -secure YES -baseDN $LDAPBase -bindDN $LDAPBindDN -filter cn=builtin" | Out-File -Append $ConfigFile
    Write-Output "add lb monitor $mon_DNS_53 DNS -query $DNS_Query -queryType Address -LRTM DISABLED -IPAddress $DNS_Query_IP"

    #Service Group
    Write-Verbose "Setting DNS Service Group Name: $svcg_DNS_53" -Verbose
    Write-Verbose "Setting LDAP Service Group Name: $svcg_LDAP_389" -Verbose
    Write-Verbose "Setting LDAPS Service Group Name: $svcg_LDAPS_636" -Verbose

    Write-Output "add serviceGroup $svcg_DNS_53 DNS -comment ""DNS Service Group""" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_LDAP_389 TCP -comment ""LDAP Service Group""" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_LDAPS_636 SSL_TCP -comment ""LDAPS Service Group""" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_DNS_53 -monitorName $mon_DNS_53" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_LDAP_389 -monitorName $mon_LDAP" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_LDAP_636 -monitorName $mon_LDAP" | Out-File -Append $ConfigFile

    #Load Balancers
    Write-Verbose "Setting ADDS Load Balancer VIP IP: $lbvs_DS_VIP_IP" -Verbose
    Write-Verbose "Setting DNS Load Balancer Name: $lbvs_DNS_53" -Verbose
    Write-Verbose "Setting LDAP Load Balancer Name: $lbvs_LDAP_389" -Verbose
    Write-Verbose "Setting LDAPS Load Balancer Name: $lbvs_LDAP_636" -Verbose

    Write-Output "add lb vserver $lbvs_DNS_53 DNS $Lbvs_DS_VIP_IP 53 -comment ""DNS Virtual Server""" | Out-File -Append $ConfigFile
    Write-Output "add lb vserver $lbvs_LDAP_389 TCP $Lbvs_DS_VIP_IP 389 -comment ""LDAP Virtual Server""" | Out-File -Append $ConfigFile
    Write-Output "add lb vserver $lbvs_LDAP_636 SSL_TCP $Lbvs_DS_VIP_IP 636 -comment ""LDAPS Virtual Server""" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_DNS_53 $svcg_DNS_53" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_LDAP_389 $svcg_LDAP_389" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_LDAP_636 $svcg_LDAPS_636" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_DNS_53 $AD_Server1_Name 53" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_DNS_53 $AD_Server2_Name 53" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_LDAP_389 $AD_Server1_Name 389" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_LDAP_389 $AD_Server2_Name 389" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_LDAPS_636 $AD_Server1_Name 636" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_LDAPS_636 $AD_Server2_Name 636" | Out-File -Append $ConfigFile

    Write-Verbose "Setting DNS Name Server: $lbvs_DNS_53" -Verbose

    Write-Output "add dns nameServer $lbvs_DNS_53" | Out-File -Append $ConfigFile
}
#endregion

#region AuthProfile
if ($AuthProfile.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing LDAP Auth Profile: $LDAPActionName" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # LDAP Auth Profile
    # ============================================================================

    Write-Verbose "Setting LDAP Action Name: $LDAPActionName" -Verbose
    Write-Verbose "Setting LDAP Policy Name: $LDAPPolicyName" -Verbose
    Write-Verbose "Setting LDAP Server IP: $LDAPServerIP" -Verbose
    Write-Verbose "Setting LDAP Base: $LDAPBase" -Verbose
    Write-Verbose "Setting LDAP Bind DN: $LDAPBindDN" -Verbose
    Write-Verbose "Setting LDAP Bind PW: $LDAPBindPW" -Verbose
    Write-Verbose "Setting LDAP Search Filter: $LDAPSearchFilter" -Verbose

    Write-Output "bind system group '$SystemGroup' -policyName superuser 1" | Out-File -Append $ConfigFile
    Write-Output "add authentication ldapAction $LDAPActionName -serverIP $LDAPServerIP -serverPort 636 -ldapBase $LDAPBase -ldapBindDn $LDAPBindDN -ldapBindDnPassword $LDAPBindPW -ldapLoginName samAccountName -searchFilter $LDAPSearchFilter -groupAttrName memberOf -subAttributeName CN -secType SSL" | Out-File -Append $ConfigFile
    Write-Output "add authentication ldapAction $LDAPActionNameInsecure -serverIP $LDAPServerIP -ldapBase $LDAPBase -ldapBindDn $LDAPBindDN -ldapBindDnPassword $LDAPBindPW -ldaploginName samAccountName -searchFilter $LDAPSearchFilter -groupAttrName memberOf -subAttributeName CN" | Out-File -Append $ConfigFile

    Write-Output "add authentication ldapPolicy $LDAPPolicyName ns_true $LDAPActionName" | Out-File -Append $ConfigFile
    Write-Output "add authentication ldapPolicy $LDAPActionNameInsecure ns_true $LDAPActionNameInsecure" | Out-File -Append $ConfigFile

    Write-Output "bind system global $LDAPPolicyName -priority 100" | Out-File -Append $ConfigFile
}
#endregion

#region Controller XML
if ($LBXML.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing Controller XML Load Balancing" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # Controller Load Balancing
    # ============================================================================
    
    #Servers
    Write-Verbose "Setting XML Controller Server Name: $Controller1_Name" -Verbose
    Write-Verbose "Setting XML Controller Server $Controller1_Name IP: $Controller1_IP" -Verbose
    Write-Verbose "Setting XML Controller Server Name: $Controller2_Name" -Verbose
    Write-Verbose "Setting XML Controller Server $Controller2_Name IP: $Controller2_IP" -Verbose

    Write-Output "add server $Controller1_Name $Controller1_IP" | Out-File -Append $ConfigFile
    Write-Output "add server $Controller2_Name $Controller2_IP" | Out-File -Append $ConfigFile

    #Service Groups
    Write-Verbose "Setting XML Controller Service Group Name: $svcg_Controller_XML_80" -Verbose
    Write-Verbose "Setting XML Controller Service Group Name: $svcg_Controller_XML_443" -Verbose
    Write-Output "add serviceGroup $svcg_Controller_XML_80 HTTP -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport YES -cltTimeout 180 -svrTimeout 360 -CKA NO -TCPB NO -CMP YES" | Out-File -Append $ConfigFile
    Write-Output "add serviceGroup $svcg_Controller_XML_443 SSL -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport YES -cltTimeout 180 -svrTimeout 360 -CKA NO -TCPB NO -CMP YES" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_Controller_XML_80 $Controller1_Name 80" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Controller_XML_80 $Controller2_Name 80" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Controller_XML_443 $Controller1_Name 443" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Controller_XML_443 $Controller2_Name 443" | Out-File -Append $ConfigFile

    Write-Output "bind ssl serviceGroup $svcg_Controller_XML_443 -eccCurveName P_384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Controller_XML_443 -eccCurveName P_256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Controller_XML_443 -eccCurveName P_224" | Out-File -Append $ConfigFile
    Write-Output "bind ssl serviceGroup $svcg_Controller_XML_443 -eccCurveName P_521" | Out-File -Append $ConfigFile

    #Load Balancers
    Write-Verbose "Setting XML Controller Load Balancer Name: $lbvs_Controller_XML_80" -Verbose
    Write-Verbose "Setting XML Controller Load Balancer Name: $lbvs_Controller_XML_443" -Verbose
    Write-Verbose "Setting XML Controller Load Balancer VIP IP: $lbvs_Controller_XML_IP" -Verbose
    Write-Verbose "Setting XML Controller Cert: $Controller_Cert" -Verbose
    
    Write-Output "add lb vserver $lbvs_Controller_XML_80 HTTP $lbvs_Controller_XML_IP  80 -persistenceType NONE -cltTimeout 180" | Out-File -Append $ConfigFile
    Write-Output "add lb vserver $lbvs_Controller_XML_443 SSL $lbvs_Controller_XML_IP 443 -persistenceType NONE -cltTimeout 180" | Out-File -Append $ConfigFile

    Write-Output "bind lb vserver $lbvs_Controller_XML_443 $svcg_Controller_XML_443" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_Controller_XML_80 $svcg_Controller_XML_80" | Out-File -Append $ConfigFile

    Write-Output "bind ssl vserver $lbvs_Controller_XML_443 -eccCurveName P_384" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Controller_XML_443 -eccCurveName P_256" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Controller_XML_443 -eccCurveName P_224" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Controller_XML_443 -eccCurveName P_521" | Out-File -Append $ConfigFile
    Write-Output "bind ssl vserver $lbvs_Controller_XML_443 -certkeyName $Controller_Cert" | Out-File -Append $ConfigFile

    #Monitors
    Write-Verbose "Setting XML Controller Monitor Name: $mon_Controller_XML" -Verbose
    Write-Verbose "Setting XML Controller Monitor Name: $mon_Controller_XML_Sec" -Verbose

    Write-Output "add lb monitor $mon_Controller_XML CITRIX-XD-DDC -LRTM DISABLED" | Out-File -Append $ConfigFile
    Write-Output "add lb monitor $mon_Controller_XML_Sec CITRIX-XD-DDC -LRTM DISABLED -secure YES" | Out-File -Append $ConfigFile

    Write-Output "bind serviceGroup $svcg_Controller_XML_80 -monitorName $mon_Controller_XML" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_Controller_XML_443 -monitorName $mon_Controller_XML_Sec" | Out-File -Append $ConfigFile

}
#endregion

#region NPS
if ($LBAzureMFA.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Writing AzureMFA Load Balancing" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    # ============================================================================
    # Azure MFA NPS Load Balancing
    # ============================================================================
    
    #Servers 
    Write-Verbose "Setting AzureMFA Server Name: $AzureMFA_Server1_Name" -Verbose
    Write-Verbose "Setting AzureMFA Server $SF_Server1_Name IP: $AzureMFA_Server1_IP" -Verbose
    Write-Verbose "Setting AzureMFA Server Name: $AzureMFA_Server2_Name" -Verbose
    Write-Verbose "Setting AzureMFA Server $SF_Server2_Name IP: $AzureMFA_Server2_IP" -Verbose

    Write-Output "add server $AzureMFA_Server1_Name $AzureMFA_Server1_IP -comment ""Azure MFA NPS Server""" | Out-File -Append $ConfigFile
    Write-Output "add server $AzureMFA_Server2_Name $AzureMFA_Server2_IP -comment ""Azure MFA NPS Server""" | Out-File -Append $ConfigFile

    #Service Groups
    Write-Verbose "Setting AzureMFA Service Group Name: $svcg_AzureMFA_Radius_1812" -Verbose

    Write-Output "add serviceGroup $svcg_AzureMFA_Radius_1812 RADIUS -maxClient 0 -maxReq 0 -cip DISABLED -usip NO -useproxyport NO -cltTimeout 120 -svrTimeout 120 -CKA NO -TCPB NO -CMP NO -comment ""Azure MFA RADIUS Service Group""" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_AzureMFA_Radius_1812 $AzureMFA_Server1_Name 1812" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_AzureMFA_Radius_1812 $AzureMFA_Server1_Name 1812" | Out-File -Append $ConfigFile
    
    # Monitors
    Write-Verbose "Setting AzureMFA Monitor Name: $Monitor_AzureMFA" -Verbose
    Write-Verbose "Setting AzureMFA Monitor Username: $AzureMFA_Mon_UserName" -Verbose

    Write-Output "add lb monitor $Monitor_AzureMFA RADIUS -respCode 2-3 -userName $AzureMFA_Mon_UserName -password $AzureMFA_Mon_Password -radKey $AzureMFA_RADIUS_Key -resptimeout 4" | Out-File -Append $ConfigFile
    Write-Output "bind serviceGroup $svcg_AzureMFA_Radius_1812 -monitorName $Monitor_AzureMFA" | Out-File -Append $ConfigFile

    #Load Balancers
    Write-Verbose "Setting AzureMFA Load Balancer VIP Name: $lbvs_AzureMFA_VIP_Name" -Verbose
    Write-Verbose "Setting AzureMFA Load Balancer VIP IP: $Lbvs_AzureMFA_VIP_IP" -Verbose

    Write-Output "add lb vserver $lbvs_AzureMFA_VIP_Name $Lbvs_AzureMFA_VIP_IP 1812 -persistenceType RULE -lbMethod TOKEN -rule CLIENT.UDP.RADIUS.USERNAME -cltTimeout 120" | Out-File -Append $ConfigFile
    Write-Output "bind lb vserver $lbvs_AzureMFA_VIP_Name $svcg_AzureMFA_Radius_1812" | Out-File -Append $ConfigFile
    
}
#endregion

#region ShowConfig
if ($ShowConfig.IsPresent) {
    Write-Verbose "--------------------------------------------" -Verbose
    Write-Verbose "Displaying Config" -Verbose
    Write-Verbose "--------------------------------------------" -Verbose
    $Config    
}
#endregion

Write-Output "save ns config" | Out-File -Append $ConfigFile

