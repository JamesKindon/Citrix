# Migrate Citrix Dedicated Machine to Citrix DaaS

## Objective

The script is designed to move a dedicated single-session machines from one CVAD site to Citrix Cloud DaaS.

If you want to move machines from a Citrix Site to Citrix Site, see this [Script instead](https://github.com/JamesKindon/Citrix/tree/master/Migration%20Scripts/MigrateDedicatedMachines/MigratedDedicatedVM)

## Technical requirements for running the script

The script is compatible with Windows PowerShell 5.1. You cannot run Citrix Snapins in PowerShell Core. Whilst the script uses the DaaS API in favor of the Remote PowerShell SDK for compatibility reasons, the source sites still required PowerShell Snapins.

This means that the technical requirements for the workstation or server running the script are as follows:

-  Any Windows version which can run Windows PowerShell 5.1.
-  Admin Credentials and access to the source Site.
-  Appropriate credentials to the Citrix Cloud DaaS instance, preferably via a secure Client.

## Parameter Details

The following parameters exist to drive the behaviour of the script:

### Mandatory and recommended parameters

-  `Region`: Mandatory **`String`**. The Citrix Cloud DaaS Tenant Region. Either AP-S (Asia Pacific), US (USA), EU (Europe) or JP (Japan).
-  `CustomerID`: Mandatory **`String`**. The Citrix Cloud Customer ID.
-  `SecureClientFile`: Optional **`String`**. The path to the Citrix Cloud Secure Client CSV. Cannot be used with `ClientID` or `ClientSecret` parameters.
-  `SourceController`: Mandatory **`String`**. The source Delivery Controller whene the machines can be found.
-  `TargetCatalog`: Optional **`String`**. The Catalog where machines will go. If not specified, the DaaS instance will be queried and a list of appropriate catalogs will be presented for selection.
-  `TargetDeliveryGroup`: Optional **`String`**. The Delivery Group where machines will go. If not specified, the DaaS instance will be queried and a list of appropriate Delivery Groups will be presented.
-  `TargetHostingConnection`: Optional **`String`**. The name of the Hosting Connection hosting the machine in the target site. If not specified, the DaaS instance will be queried and a list of appropriate Hosting Connections will be presented.
-  `TargetMachineScope`: Mandatory **`Switch`**. The method used to target machine scoping. Can be either `MachineList` (you must provide the `TargetMachineList` param) or `Catalog` (you must provide the `SourceCatalog` param).
-  `TargetMachineList`: Optional **`Array`**. An array of machines to target. "Machine1","Machine2","Machine3". Used with the `TargetMachineScope` parameter when set to `MachineList`.
-  `SourceCatalog`: Optional **`String`**. If choosing to use a `Catalog` as the source of machines with `TargetMachineScope`, the `SourceCatalog` parameter is required.

### Optional Parameters

-  `ClientID`: Optional **`String`**. The Citrix Cloud Secure Client ID. Cannot be used with the `SecureClientFile` Parameter. Must be combined with the `ClientSecret` parameter.
-  `ClientSecret`: Optional **`String`**. The Citrix Cloud Secure Client Secret. Cannot be used with the `SecureClientFile` Parameter. Must be used with the `ClientID` parameter.
-  `LogPath`: Optional **`String`**. Log path output for all operations. The default is `C:\Logs\MigrateDedicatedMachinesDaaS.log`
-  `LogRollover`: Optional **`Int`**. Number of days before log files are rolled over. The default is `5`.
-  `ExclusionList`: Optional **`Array`**. A list of machines to exclude from processing. Used regardless of the the `TargetmachineScope` parameter.
-  `IncludeMCSMachinesFromSource`: Optional **`Switch`**. By default, MCS machines are excluded, however you can include them using this parameter.
-  `RemoveVMFromSource`: Optional **`Switch`**. llows the script to remove the migrated machine from the source environment. This includes removing ProvVM components in an MCS scenario if the `IncludeMCSMachinesFromSource` is used.
-  `SetMaintenanceModeInTarget`: Optional **`Switch`**. Allows setting maintenance mode on the machines moved to the Citrix Cloud DaaS.
-  `SetMaintenanceModeInSource`: Optional **`Switch`**. Allows setting maintenance mode on the machines in the source site.
-  `PublishedName`: Optional **`Switch`**. Allows setting the Published Name on the target desktop. Either `MatchSourceDG` or `New` (you must specify the new name with the `NewPublishedName` parameter). If `MatchSourceDG` the source Delivery Group will be queried and the target machines will have their Published Name set to this value.
-  `NewPublishedName`: Optional **`String`**. The value of the Published Name if the `PublishedName` parameter is used with the `New` value.
-  `ResetTargetHostingConnection`: Optional **`Switch`**. Reset the Target Hosting Connection if any machine objects are altered. This removes the Sync delay between Citrix and the Hosting platform and allows power status to be retrieved.
-  `MaxRecordCount`: Optional **`Int`**. The max number of machines to be queried in the source site. The default is 1000.
-  `Whatif`: Optional **`Switch`**. Will action the script in a whatif processing mode only.
-  `HideSourceMCSWarning`: Optional **`Switch`**. If you enable MCS inclusion via the `IncludeMCSMachinesFromSource` parameter and you enable `RemoveVMFromSource`, a warning/disclaimer will be shown due to discrepencies in Citrix Powershell versions. You can hide this warning if you have tested appropriately.

## Scenarios and Examples

### Basic Machine Migration

Param Splatting:

```
$params = @{
    Region                       = "US"
    CustomerID                   = "fakecustID"
    SecureClientFile             = "C:\SecureFolder\secureclient.csv"
    SourceController             = "SourceDDC"
    TargetMachineScope           = "MachineList"
    TargetMachineList            = @("VM1,"VM2","VM3")
    TargetHostingConnection      = "HostingConnection1"
    ResetTargetHostingConnection = $true
    TargetCatalog                = "TargetCatalog1"
    TargetDeliveryGroup          = "TargetDeliveryGroup1"
    PublishedName                = "MatchSourceDG"
    Whatif                       = $true
}

& C:\Temp\MigrateDedicatedMachinesDaaS.ps1 @params
```

The direct script invocation via the command line with defined arguments would be:

```
MigrateDedicatedMachinesDaaS.ps1 -Region "US" -CustomerID "fakecustID" -SecureClientFile "C:\SecureFolder\secureclient.csv" -SourceController "SourceDDC" -TargetMachineScope MachineList -TargetMachineList "VM1,"VM2","VM3" -TargetHostingConnection "HostingConnection1" -ResetTargetHostingConnection -TargetCatalog "TargetCatalog1" -TargetDeliveryGroup "TargetDeliveryGroup1" -PublishedName MatchSourceDG -whatif
```

The script will:

-  Use the Citrix Cloud DaaS `US` region.
-  Use the provided Customer ID `fakecustID` and Secure Client File in `c:\SecureFolder\secureclient.csv`.
-  Connect to Citrix Cloud and validate the appropriate configurations are in place based on inputs.
-  Pull machines from the source Delivery Controller `SourceDDC`
-  Scope machines based on a `MachineList` input of `"VM1,"VM2","VM3"`
-  Target the Delivery Controller in another site `TargetDDC`
-  Target the Catalog `TargetCatalog1` in the target site
-  Target the Delivery Group `TargetDeliveryGroup1` in the target site
-  Target the Hosting Connection `TargetHostingConnection` in the target site
-  Set the migrated machines Published Name to the `PublishedName` attribute found on the Source Delivery Group that the machine is a member of
-  Reset the Hosting Connection in the remote site via the `ResetTargetHostingConnection` switch
-  Process in Whatif mode only due to `Whatif` switch
-  Will `not` include MCS provisioned machines, only Manual provisioned machines

### Machine Migration including MCS Provisioned Machines

```
$params = @{
    Region                       = "US"
    CustomerID                   = "fakecustID"
    SecureClientFile             = "C:\SecureFolder\secureclient.csv"
    SourceController             = "SourceDDC"
    TargetMachineScope           = "MachineList"
    TargetMachineList            = @("VM1,"VM2","VM3")
    TargetHostingConnection      = "HostingConnection1"
    ResetTargetHostingConnection = $true
    TargetCatalog                = "TargetCatalog1"
    TargetDeliveryGroup          = "TargetDeliveryGroup1"
    IncludeMCSMachinesFromSource = $true
    PublishedName                = "MatchSourceDG"
    SetMaintenanceModeInSource   = $true
    Whatif                       = $true
}

& C:\Temp\MigrateDedicatedMachinesDaaS.ps1 @params
```

The direct script invocation via the command line with defined arguments would be:

```
MigrateDedicatedMachinesDaaS.ps1 -Region "US" -CustomerID "fakecustID" -SecureClientFile "C:\SecureFolder\secureclient.csv" -SourceController "SourceDDC" -TargetMachineScope MachineList -TargetMachineList "VM1,"VM2","VM3" -TargetHostingConnection "HostingConnection1" -ResetTargetHostingConnection -TargetCatalog "TargetCatalog1" -TargetDeliveryGroup "TargetDeliveryGroup1" -IncludeMCSMachinesFromSource -PublishedName MatchSourceDG -SetMaintenanceModeInSource -whatif
```

The script will:

-  Use the Citrix Cloud DaaS `US` region.
-  Use the provided Customer ID `fakecustID` and Secure Client File in `c:\SecureFolder\secureclient.csv`.
-  Connect to Citrix Cloud and validate the appropriate configurations are in place based on inputs.
-  Pull machines from the source Delivery Controller `SourceDDC`
-  Scope machines based on a `MachineList` input of `"VM1,"VM2","VM3"`
-  Target the Delivery Controller in another site `TargetDDC`
-  Target the Catalog `TargetCatalog1` in the target site
-  Target the Delivery Group `TargetDeliveryGroup1` in the target site
-  Target the Hosting Connection `TargetHostingConnection` in the target site
-  Set the migrated machines Published Name to the `PublishedName` attribute found on the Source Delivery Group that the machine is a member of
-  Reset the Hosting Connection in the remote site via the `ResetTargetHostingConnection` switch
-  Will include MCS provisioned machines due to the `IncludeMCSMachinesFromSource`
-  Set the machines in the Source Site to maintenance mode due to the `SetMaintenanceModeInSource` switch
-  Process in Whatif mode only due to `Whatif` switch

### Machine Migration including MCS Provisioned Machines and Removal of Machines in the Source Site

```
$params = @{
    Region                       = "US"
    CustomerID                   = "fakecustID"
    SecureClientFile             = "C:\SecureFolder\secureclient.csv"
    SourceController             = "SourceDDC"
    TargetController             = "TargetDDC"
    TargetMachineScope           = "Catalog"
    SourceCatalog                = "CatalogInSource"
    ExclusionList                = @("VM4,"VM7","VM12")
    TargetHostingConnection      = "HostingConnection1"
    ResetTargetHostingConnection = $true
    TargetCatalog                = "TargetCatalog1"
    TargetDeliveryGroup          = "TargetDeliveryGroup1"
    IncludeMCSMachinesFromSource = $true
    PublishedName                = "New"
    NewPublishedName             = "NewDesktopName"
    RemoveVMFromSource           = $true
    HideSourceMCSWarning         = $false
    Whatif                       = $true
}

& C:\Temp\MigrateDedicatedMachinesDaaS.ps1 @params
```

The direct script invocation via the command line with defined arguments would be:

```
MigrateDedicatedMachinesDaaS.ps1 -Region "US" -CustomerID "fakecustID" -SecureClientFile "C:\SecureFolder\secureclient.csv" -SourceController "SourceDDC" -TargetMachineScope Catalog -SourceCatalog 'CatalogInSource" -ExclusionList "VM4,"VM7","VM12" -TargetHostingConnection "HostingConnection1" -ResetTargetHostingConnection -TargetCatalog "TargetCatalog1" -TargetDeliveryGroup "TargetDeliveryGroup1" -IncludeMCSMachinesFromSource -PublishedName New -NewPublishedName "NewDesktopName" -RemoveVMFromSource -whatif
```

The script will:

-  Use the Citrix Cloud DaaS `US` region.
-  Use the provided Customer ID `fakecustID` and Secure Client File in `c:\SecureFolder\secureclient.csv`.
-  Connect to Citrix Cloud and validate the appropriate configurations are in place based on inputs.
-  Pull machines from the source Delivery Controller `SourceDDC`
-  Scope machines based on a `Catalog` input. Catalog is `CatalogInSource` in the Source Site
-  Exclude machines `"VM4,"VM7","VM12"`
-  Target the Delivery Controller in another site `TargetDDC`
-  Target the Catalog `TargetCatalog1` in the target site
-  Target the Delivery Group `TargetDeliveryGroup1` in the target site
-  Target the Hosting Connection `TargetHostingConnection` in the target site
-  Set the migrated machines Published Name to `NewDesktopName`
-  Reset the Hosting Connection in the remote site via the `ResetTargetHostingConnection` switch
-  Will include MCS provisioned machines due to the `IncludeMCSMachinesFromSource`
-  Remove Machines in the source site including MCS provisioned machines due to the `RemoveVMFromSource` switch
-  Shows the associated warning for MCS source removal due to the `HideSourceMCSWarning` switch not being present (see note below)
-  Process in Whatif mode only due to `Whatif` switch

#### A note on MCS Source Machine Removal

If you are using a newer version of the Citrix PowerShell Snapins than your site is currently running, the -ForgetVM switch may not operate as documented, and the VM entity will be removed/deleted (yes deleted) from the hypervisor.

This has been validated as a bug in scenarios such as Site Version: `2203 LTSR` and Studio/PowerShell Version `2305` on a remote server. It is wise to keep operational components at a similar version.

Test before executing production workloads (scope with a `MachineList` specific command set)