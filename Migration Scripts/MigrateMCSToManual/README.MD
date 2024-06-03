# Citrix MCS to Manual Catalog Switch

## Context

Citrix Machine Creation Services provisioning does not allow the alteration of either the `HypervisorConnectionUid` (The hypervisor connection that runs the machine) or `HostedMachineId` (The unique ID by which the hypervisor recognizes the machine) attributes. These attributes are immutable and cannot be overwritten. 

Additionally, MCS uses a Provisioning VM object `ProvVM` in conjunction with the actual `BrokerHostedMachine` record. The `ProvVM`:`VMid` attribute and the `BrokerHostedMachine`:`HostedMachineId` attribute both represent the machine in Nutanix (the Nutanix VM `uuid`).

If an MCS provisioned machine is removed from its Catalog (deleted) using the PowerShell command `Remove-BrokerMachine`, then the `ProvVM` object is left intact in the database.

*  If the machine ID of the virtual machine **is not** changed, then the machine can be added back to the MCS catalog using the `Add-BrokerMachine` PowerShell command as its `uuid` will match the existing (orphaned) `VMId` attribute.
*  If the machine ID of the virtual machine **is** changed, then the `uuid` of the Nutanix VM will have changed, and it cannot be added back to the MCS catalog without significant alteration.

In a power managed catalog scenario, these limitations do not exist. Citrix does not use a `ProvVM` record for power managed machines.

This script will work with both on-prem CVAD deployments and cloud-based DaaS deployments. It will move existing MCS provisioned machines, to a manual power managed catalog in a graceful manner.

## Script Logic

The `MigrateMCSToManual.ps1` script will action the following tasks:

*  Retrieve a list of VMs via the `TargetMachineScope` parameter. This can be either:
*  `All` which sources all VMs in the specified catalog specified by the `SourceCatalog` parameter
*  `MachineList` which is a provided array of VMs in the specified catalog specified by the `SourceCatalog` parameter
*  `CSV` which will import a list of VMs using the `TargetMachineCSVList` parameter and then source from the specified catalog specified by the `SourceCatalog` parameter. The CSV requires the header value: `HostedMachineName`. A standard export from an existing Catalog `Get-BrokerMachine -CatalogName "W10 MCS Migration Test" | Export-CSV -NoTypeInformation c:\temp\VMList.csv` would be a wise move
*  For each of the machines retrieved will action the following tasks:
    *  Validate the existence of the specified target Catalog as specified by the `TargetCatalog` parameter. If this Catalog does not exist, it will be created. The catalog must be power managed
    *  Validate the existence of the specified target Delivery Group as specified by the `TargetDeliveryGroup` parameter. If this Delivery Group does not exist, it will be created. If the `AlignTargetDeliveryGroupToSource` parameter is specified, then the following settings will be mirrored from the Source DeliveryGroup as specified by the `SourceDeliveryGroup` parameter:
        *  Minimal Functional Level: `MinimumFunctionalLevel`. **Note** that if `AlignTargetDeliveryGroupToSource` is not present, then the Functional Version from the Source Catalog will be used.
        *  Broker Access Policy Rules: `BrokerAccessPolicyRule`. **Note** that if `AlignTargetDeliveryGroupToSource` is not present, then default rules with no allowed access will be configured. 
        *  Allowed users (user filters): `AllowedUsers`
    *  Set the machine maintenance mode to `true`
    *  Remove the machine from the current Delivery Group
    *  Unlock the ProvVM
    *  Remove the ProvVM using the `-ForgetVM` switch
    *  Remove the AD Account from the MCS database but `retain` the Active Directory Account and the Virtual Machine on the hosting platform
    *  Remove the machine from the existing MCS catalog
    *  Add the VM to the new or existing Target Catalog as specified by the `TargetCatalog` parameter
    *  Add the VM to the new or existing Target Delivery Group as specified by the `TargetDeliveryGroup` parameter
    *  Restore user assignments
    *  Set the published name attributes with the following logic:
        *  Mirror the `PublishedName` attribute from the source VM if not empty (if empty, the value on the catalog will be inherited)
        *  Set the `PublishedName` attribute to the value specified in the `OverridePublishedName` parameter if specified
        *  Set the `PublishedName` attribute to the Machine Name if the `SetPublishedNameToMachineName` parameter switch is specified

## Warnings and Caveats

*  The MCS provisioned machine must be a full-cloned machine. This is the default in AHV deployments but may be a problem in vSphere based scenarios
*  This is a one way trip. Once a machine has been removed from an MCS catalog, it cannot be added back in
*  MCS is a developing technology set. It is likely that in the future enhancements will be introduced to remove the current limitations and this script will become redundant
*  MCS is a developing technology set and some features will be tied to MCS capability. It is important to note what the customers are using, how they are using it, and identifying if they will lose capability and functionality by removing machines from an MCS catalog 

## Technical requirements for running the script

The script is compatible with Windows PowerShell 5.1. Because it uses Citrix Snap-Ins (no modules are available), it cannot run on PowerShell core (which does not support snap-ins).

This means that the technical requirements for the workstation or server running the script are as follows:

1.  Any Windows version which can run Windows PowerShell 5.1
2.  All Citrix VAD Snap-Ins installed (those can be found on the Citrix VAD installation media) or the Citrix Cloud PowerShell SDK for Citrix DaaS
3.  Network access to the Citrix brokers (TCP/80 and TCP/443) or to the appropriate Citrix Cloud Endpoints
4.  Privileged accounts to the Citrix brokers (for the user running the script) or an appropriate client credential for Citrix DaaS

## Parameter and Scenario Details

The following parameters exist to drive the behaviour of the script:

### Mandatory and recommended parameters:

*  `Controller`: Mandatory **`String`**. Value for the Delivery Controller to target, Eg. DDC1
*  `SourceCatalog`: Mandatory **`string`**. Specifies the source catalog for MCS machines
*  `TargetCatalog`: Optional **`string`** . Specifies the target catalog for machines migrated from MCS. Will be created if not found.
*  `TargetDeliveryGroup`: Optional **`string`**. Specifies the target Delivery Group for migrated machines. Will be created if not found.

### Optional Parameters:

*  `LogPath`: Optional **`String`**. Log path output for all operations. The default is `C:\Logs\MCSMigration.log`
*  `LogRollover`: Optional **`int`** .Number of days before log files are rolled over. Default is 5
*  `JSON`: Optional **`switch`**. Will consume a JSON import for configuration
*  `JSONInputPath`: Optional **`string`**. Specifies the JSON input file
*  `SourceDeliveryGroup`: Optional **`switch`**. Specifies the source Delivery Group to mirror Published Name, Access Policy Rules and Functional Levels from. Used in conjunction with `AlignTargetDeliveryGroupToSource` Parameter
*  `AlignTargetDeliveryGroupToSource`: Optional **`switch`**. Switch to enable mirroring of settings from Source Delivery Group. Used in conjunction with `SourceDeliveryGroup` Parameter
*  `OverridePublishedName`: Optional **`string`**. Value to override the published desktop name with a new value else will consume existing published name
*  `SetPublishedNameToMachineName`: Optional **`switch`**. Switch to force set the published name to the VM name.
*  `TargetMachineScope`: Optional **`Array`**. Specifies how machines are handled, either `All`, `MachineList` or `CSV`. Defaults to `All`.
*  `TargetMachineList`: Optional **`Array`**. An array of machines to target "VM01","VM02. Used in conjunction with the `TargetMachineScope` when using the `MachineList` value.
*  `TargetMachineCSVList`: Optional **`Array`**. Target CSV File for machine targets. Used in conjunction with the `TargetMachineScope` Param when using the `CSV` value. CSV must use the `HostedMachineName` Header. Suggest exporting via `Get-BrokerMachine`
*  `MaxRecordCount`: Optional **`int`**.  Overrides the query max for VM lookups - defaults to 10000

## Scenarios

### General Basic Use

This scenario outlines migration from the source environment to the target environment with a change of Display Name

Param Splatting: 

```
$params = @{
    Controller                    = "DDC1"
    SourceCatalog                 = "W10 MCS Catalog Source"
    TargetCatalog                 = "W10 MCS Catalog Dest"
    TargetDeliveryGroup           = "W10 MCS DG Dest"
    SetPublishedNameToMachineName = $true
}

& MigrateMCSToManual.ps1 @params
```

The direct script invocation via the command line with define arguments would be:

```
.\MigrateMCSToManual -SourceCatalog "W10 MCS Catalog Source" -TargetCatalog "W10 MCS Catalog Dest" -TargetDeliveryGroup "W10 MCS DG Dest" -SetPublishedNameToMachineName -Controller DDC1
```

The script will:

*  Connect to the Controller `DDC1`.
*  Target all machines in the Catalog `W10 MCS Catalog Source`.
*  Move machines into the Catalog `W10 MCS Catalog Dest`. The Catalog will be created if it does not exist.
*  Move machines into the Delivery Group `W10 MCS DG Dest`. The Delivery Group will be created if it does not exist.
*  Will set the Published name of the resource to the name of the virtual machine.
