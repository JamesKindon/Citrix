# Notes:
 # Master Image VM Example: XDHyp:\HostingUnits\Azure_AE\image.folder\RG_AE_Citrix_Cloud.resourcegroup\AE-VM-Test01_OsDisk_1_ecc86fafbca14627894a5caf00b4cfe3.manageddisk
 # Network Mapping Example: virtualprivatecloud.folder\RG-AE-General.resourcegroup\VNET-AE-Kindon.virtualprivatecloud\subnet-wvd.network
 # Service Offering Example: #serviceoffering.folder\Standard_DS1_v2.serviceoffering
function CreateCatalog {
    if ($MC_SpecificZone -eq "true") {
        New-BrokerCatalog -Name $MC_CatalogName -AllocationType $MC_AllocationType -PersistUserChanges $MC_PersistUserChanges -ProvisioningType $MC_ProvisioningType -SessionSupport $MC_SessionSupport -ZoneUid $MC_ZoneUid
    }
    else {
        New-BrokerCatalog -Name $MC_CatalogName -AllocationType $MC_AllocationType -PersistUserChanges $MC_PersistUserChanges -ProvisioningType $MC_ProvisioningType -SessionSupport $MC_SessionSupport
    }    
}

function CreateAcctIdentityPool {
    if ($CitrixCloud -eq "true") {
        Write-Host "Requires setting Identity Pool Domain information on machine provision"
        New-AcctIdentityPool -IdentityPoolName $AP_Name
    }
    else {
        New-AcctIdentityPool -IdentityPoolName $AP_Name -Domain $AP_Domain -NamingScheme $AP_NamingScheme -NamingSchemeType $AP_NamingSchemeType -OU $AP_OU
    }
}

function CreateProvScheme {
    New-ProvScheme -CleanOnBoot -CustomProperties $CustomProperties -HostingUnitName $PS_HostingUnitName -IdentityPoolName $PS_IdentityPoolName -MasterImageVM $PS_MasterImageVM `
    -NetworkMapping $PS_NetworkMapping -ProvisioningSchemeName $PS_PSName -ServiceOffering $PS_ServiceOffering `
    -UseWriteBackCache -WriteBackCacheDiskSize $PS_WBDiskSize -WriteBackCacheMemorySize $PS_WBMemorySize
}

function AssignProvScheme {
    $PS = Get-ProvScheme -ProvisioningSchemeName $MC_CatalogName
    Set-BrokerCatalog -Name $MC_CatalogName -ProvisioningSchemeId $PS.ProvisioningSchemeUid
}

##### General Variables
$CitrixCloud            = "true" # true of false for Citrix Cloud PowerShell

########-------- Machine Catalog Variables
$MC_CatalogName         = "Kindon-Azure-AustraliaEast-MCS-PersistWBC"
$MC_AllocationType      = "Random"
$MC_PersistUserChanges  = "Discard"
$MC_ProvisioningType    = "MCS"
$MC_SessionSupport      = "MultiSession"
$MC_SpecificZone        = "false" # true or false for zone alteration
$MC_ZoneUid             = "54b732df-7595-44fe-afd6-af5afd3010b8" # Only if required and works with $MC_SpecificZone

########-------- AcctIdentityPool Variables - Doesn't play nice with Citrix Cloud
$AP_Name                = $MC_CatalogName
$AP_Domain              = "KINDO.COM"
$AP_NamingScheme        = "AAE-VM-Test##"
$AP_NamingSchemeType    = "Numeric"
$AP_OU                  = "OU=Azure - Aus East,OU=Windows 10 Azure - Failover Testing,OU=Workers,OU=Citrix FMA,DC=Kindo,DC=com"

########-------- ProvScheme Custom Properties
$PS_PSName              = $MC_CatalogName # Prov Scheme Name
$PS_HostingUnitName     = "AE-General" # Name of hosting unit containing network details for provisioining. Get-ProvScheme to find HostingUnitName from existing ProvScheme
$PS_IdentityPoolName    = $MC_CatalogName # AcctIdentity Pool Name
$PS_UseManagedDisks     = "true" # true or false for managed disks
$PS_StorageAccountType  = "Premium_LRS" #Premium_LRS or Standard_LRS
$PS_ResourceGroups      = "RG-AE-CTX-MCS-PersistWBC"
$PS_Offering_Size       = "Standard_DS1_v2" # Machine Size
$PS_WBDiskSize          = "40" # Disk size for the persistent disk in GB
$PS_WBMemorySize        = "2048" # Memory allocation for Writeback Cache in GB
$PS_PersistWBC          = "true" # Persist Writeback Cache
$PS_LicenseType         = "Windows_Server" # Windows_Server, Windows_Client
#ProvScheme Master Image
$PS_MI_ResourceGroup    = "RG_AE_Citrix_OnPrem" #Master Image or Snapshot Resource Group
$PS_MI_OSDiskName       = "VM-CTX-MI-01_OsDisk_1_f7946cdebde049d8b44c716a053eb1f9" #OSDisk or Snapshot Name
$PS_MI_Type             = "manageddisk" # manageddisk or snapshot
#ProvScheme Network Mapping
$PS_NM_hostingUnit      = $PS_HostingUnitName # Name of hosting unit containing network details for provisioining
$PS_NM_VNET             = "VNET-AE-Kindon" # VNET for Workloads as defined in hosting connection
$PS_NM_Subnet           = "subnet-general" # Subnet for Workloads as defined in hosting connection
$PS_NM_ResourceGroup    = "RG-AE-General" # Resource Group holding the VNET
#ProvScheme Custom Properties 
$CustomProperties       = "<CustomProperties xmlns=`"http://schemas.citrix.com/2014/xd/machinecreation`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">`
<Property xsi:type=`"StringProperty`" Name=`"UseManagedDisks`" Value=`"$PS_UseManagedDisks`" />`
<Property xsi:type=`"StringProperty`" Name=`"StorageAccountType`" Value=`"$PS_StorageAccountType`" />`
<Property xsi:type=`"StringProperty`" Name=`"ResourceGroups`" Value=`"$PS_ResourceGroups`" />`
<Property xsi:type=`"StringProperty`" Name=`"PersistWBC`" Value=`"$PS_PersistWBC`" />`
<Property xsi:type=`"StringProperty`" Name=`"LicenseType`" Value=`"$PS_LicenseType`" />`
</CustomProperties>"

############################################################
#############--------Leave these alone--------##############
############################################################
$PS_MasterImageVM       = "XDHyp:\HostingUnits\$PS_HostingUnitName\image.folder\$PS_MI_ResourceGroup.resourcegroup\$PS_MI_OSDiskName.$PS_MI_Type" #Master Image VM or Snapshot Path                    
$PS_NetworkMapping      = @{"0" = "XDHyp:\HostingUnits\$PS_NM_hostingUnit\\virtualprivatecloud.folder\$PS_NM_ResourceGroup.resourcegroup\$PS_NM_VNET.virtualprivatecloud\$PS_NM_Subnet.network" } #(Get-ProvScheme NAME).NetworkMaps.NetworkPath
$PS_ServiceOffering     = "XDHyp:\HostingUnits\$PS_NM_hostingUnit\serviceoffering.folder\$PS_Offering_Size.serviceoffering"
############----------------------------------#############


#####
# Step 1: Create the Catalog
CreateCatalog
# Step 2: Create the AcctIdentityPool for the computer accounts
CreateAcctIdentityPool
# Step 3: Create the ProvScheme object
CreateProvScheme
# Step 4: Assign the ProvScheme to the Catalog
AssignProvScheme

