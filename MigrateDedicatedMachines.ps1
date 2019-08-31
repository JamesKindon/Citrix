<#
.SYNOPSIS
via an exported XML from an existing dedicated VDI catalog (Power Managed), migrate machines to Citrix Cloud with new hosting connection mappings

.DESCRIPTION
requires a clean export of an existing catalog to Clixml (See notes)

.EXAMPLE
.\MigrateDedicatedMachines.ps1

.NOTES
Export required information from existing catalog

$CatalogName = 'CATALOGNAMEHERE'
$ExportLocation = 'PATH HERE\vms.xml'

Get-BrokerMachine -CatalogName $CatalogName -MaxRecordCount 100000 | Export-Clixml $ExportLocation

.LINK
#>

Add-PSSnapin citrix*

Get-XDAuthentication

$VMs = $null
$HostingConnectionName = $null
$CatalogName = $null
$PublishedName = $null
$DeliveryGroupName = $null

# Optionally set configuration without being prompted
#$VMs = Import-Clixml -Path 'Path to XML Here'
#$HostingConnectionName = "Hosting Connection Name Here" #(Get-BrokerHypervisorConnection | Select-Object Name)
#$CatalogName = "Catalog Name Here" #(Get-BrokerCatalog | Select-Object Name)
#$PublishedName = "Display name Here" 
#$DeliveryGroupName = "Delivery Group Name here" #(Get-BrokerDesktopGroup | Select-Object Name)

# If Not Manually set, prompt for variable configurations
if ($null -eq $VMs) {
    Write-Verbose "Please Select an XML Import File" -Verbose
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter           = 'XML Files (*.xml)|*.*'
    }
    $null = $FileBrowser.ShowDialog()

    $VMs = Import-Clixml -Path $FileBrowser.FileName
}

if ($null -eq $HostingConnectionName) {
    $HostingConnectionName = Get-BrokerHypervisorConnection | Select-Object Name, State, IsReady | Out-GridView -PassThru -Title "Select a Hosting Connection"
}

if ($null -eq $CatalogName) {
    $CatalogName = Get-BrokerCatalog | Select-Object Name, AllocationType, PersistUserChanges, ProvisioningType, SessionSupport, ZoneName | Out-GridView -PassThru -Title "Select a Destination Catalog"
}

if ($null -eq $DeliveryGroupName) {
    $DeliveryGroupName = Get-BrokerDesktopGroup | Select-Object Name, DeliveryType, Description, DesktopKind, Enabled, SessionSupport | Out-GridView -PassThru -Title "Select a Desktop Group"
}


$Catalog = (Get-BrokerCatalog -Name $CatalogName)
$HostingConnectionDetail = (Get-BrokerHypervisorConnection | Where-Object { $_.Name -eq $HostingConnectionName })

$Count = ($VMs | Measure-Object).Count
$StartCount = 1
Write-Verbose "There are $Count machines to process" -Verbose

function AddVMtoCatalog {
    if ($null -eq (Get-BrokerMachine -MachineName $VM.MachineName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Adding $($VM.MachineName) to Catalog $($Catalog.Name)" -Verbose
        New-BrokerMachine -CatalogUid $Catalog.Uid -HostedMachineId $VM.HostedMachineId -HypervisorConnectionUid $HostingConnectionDetail.Uid -MachineName $VM.SID -Verbose | Out-Null
    }
    else {
        Write-Warning "Machine $($VM.MachineName) already exists in catalog $($VM.CatalogName)" -Verbose
    }
}

function AddVMtoDeliveryGroup {
    $DG = (Get-BrokerMachine -MachineName $VM.MachineName).DesktopGroupName
    if ($null -eq $DG) {
        Write-Verbose "Adding $($VM.MachineName) to DesktopGroup $DeliveryGroupName" -Verbose
        Add-BrokerMachine -MachineName $VM.MachineName -DesktopGroup $DeliveryGroupName -Verbose
    }
    else {
        Write-Warning "$($VM.MachineName) already a member of: $DG"
    } 
}

function AddUsertoVM {
    Write-Verbose "Attempting User Assignments" -Verbose
    $AssignedUsers = $VM.AssociatedUserNames
    if ($AssignedUsers) {
        Write-Verbose "Processing $($VM.MachineName)" -Verbose
        foreach ($User in $AssignedUsers) {
            Write-Verbose "Adding $($User) to $($VM.MachineName)" -Verbose
            Add-BrokerUser $User -PrivateDesktop $VM.MachineName -Verbose
        }
    }
    else {
        Write-Warning "There are no user assignments defined for $($VM.MachineName)" -Verbose
    }
}

function SetVMDisplayName {
    if ($null -ne $PublishedName) {
        Write-Verbose "Setting Published Name for $($VM.MachineName) to $PublishedName" -Verbose
        Set-BrokerMachine -MachineName $VM.MachineName -PublishedName $PublishedName -Verbose
    }
}

foreach ($VM in $VMs) {
    $OutputColor = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = "Green"
    Write-Output "VERBOSE: Processing machine $StartCount of $Count" -Verbose
    $host.ui.RawUI.ForegroundColor = $OutputColor

    AddVMtoCatalog
    AddVMtoDeliveryGroup
    SetVMDisplayName
    AddUsertoVM
    
    $StartCount += 1
}
