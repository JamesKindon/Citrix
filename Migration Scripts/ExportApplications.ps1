<#
.SYNOPSIS
Exports applications from a specified delivery group to an XML file. To be used in conjunction with ImportApplications.ps1

Some of the original code is found here, but had lots of issues
https://discussionsqa3.citrix.com/topic/356373-xendesktopxenapp-7x-applications-exporting-importing/

.DESCRIPTION
provides a clean export of existing Applications via Clixml (See notes)

Use the corresponding ImportApplications.ps1 script to retrieve to import the export from this script
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ImportApplications.ps1

.EXAMPLE
.\ExportApplications.ps1

.NOTES
Use corresponding import script to achieve appropriate export

$ExportLocation = 'PATH HERE\Apps.xml'

# To do
Add App Group Support

.LINK
#>

Add-PSSnapin citrix*

#Get-XDAuthentication

$DelGroupName = $null
$ExportLocation = $null

$LogPS = "${env:SystemRoot}" + "\Temp\ApplicationExport.log"

# Optionally set configuration without being prompted
#$DelGroupName = "Delivery Group Name"
#$ExportLocation = "C:\temp\Apps.xml"

$StartDTM = (Get-Date)

Write-Verbose "Start Logging" -Verbose
Start-Transcript $LogPS | Out-Null

# Get Delivery Groups if not specified already
if ($null -ne $DelGroupName) {
    $DelGroupID = (Get-BrokerDesktopGroup -Name $DelGroupName -ErrorAction SilentlyContinue).Uid
    if ($DelGroupID) {
        Write-Verbose "Using Delivery Group: $($DelGroupName) as targeted Delivery Group" -Verbose
    }
    else {
        Write-Warning "Delivery Group: $($DelGroupName) not found. Exit Script." -Verbose
        Break
    }
}

# Display a list if Delivery Group not specifed
if ($null -eq $DelGroupID) {
    $DeliverGroups = Get-BrokerDesktopGroup | Format-list -property Name, UID | out-string
    Write-Host  "Delivery groups : $DeliverGroups"
    $DelGroupID = Read-Host -Prompt 'Specify Delivery Group UID to Target for export'
}

$DelGroup = Get-BrokerDesktopGroup -Uid $DelGroupID
Write-Verbose "Using Delivery Group: $($DelGroup.Name) as targeted Delivery Group" -Verbose

# Gets a list of applications
$apps = Get-BrokerApplication -AssociatedDesktopGroupUid $DelGroupID -MaxRecordCount 2147483647

$Count = ($Apps | Measure-Object).Count
$StartCount = 1

Write-Verbose "There are $Count Applications to process" -Verbose

$Results = @()

foreach ($app in $apps) {
    Write-Verbose "Processing Application $StartCount ($($App.PublishedName)) of $Count" -Verbose
    # Builds Properties for each application ready for export
    $Properties = @{
        AdminFolderName                  = $app.AdminFolderName
        AdminFolderUid                   = $app.AdminFolderUid
        ApplicationName                  = $app.ApplicationName
        ApplicationType                  = $app.ApplicationType
        AssociatedDesktopGroupPriorities = $app.AssociatedDesktopGroupPriorities
        AssociatedDesktopGroupUUIDs      = $app.AssociatedDesktopGroupUUIDs
        AssociatedDesktopGroupUids       = $app.AssociatedDesktopGroupUids
        AssociatedUserFullNames          = $app.AssociatedUserFullNames
        AssociatedUserNames              = $app.AssociatedUserNames
        AssociatedUserUPNs               = $app.AssociatedUserUPNs
        BrowserName                      = $app.BrowserName
        ClientFolder                     = $app.ClientFolder
        CommandLineArguments             = $app.CommandLineArguments
        CommandLineExecutable            = $app.CommandLineExecutable
        CpuPriorityLevel                 = $app.CpuPriorityLevel
        Description                      = $app.Description
        IgnoreUserHomeZone               = $app.IgnoreUserHomeZone
        Enabled                          = $app.Enabled
        IconFromClient                   = $app.IconFromClient
        EncodedIconData                  = (Get-Brokericon -Uid $app.IconUid).EncodedIconData # Grabs Icon Image
        IconUid                          = $app.IconUid                       
        MetadataKeys                     = $app.MetadataKeys
        MetadataMap                      = $app.MetadataMap
        MaxPerUserInstances              = $app.MaxPerUserInstances
        MaxTotalInstances                = $app.MaxTotalInstances
        Name                             = $app.Name
        PublishedName                    = $app.PublishedName
        SecureCmdLineArgumentsEnabled    = $app.SecureCmdLineArgumentsEnabled
        ShortcutAddedToDesktop           = $app.ShortcutAddedToDesktop
        ShortcutAddedToStartMenu         = $app.ShortcutAddedToStartMenu
        StartMenuFolder                  = $app.StartMenuFolder
        UUID                             = $app.UUID
        Uid                              = $app.Uid
        HomeZoneName                     = $app.HomeZoneName
        HomeZoneOnly                     = $app.HomeZoneOnly
        HomeZoneUid                      = $app.HomeZoneUid
        UserFilterEnabled                = $app.UserFilterEnabled
        Visible                          = $app.Visible
        WaitForPrinterCreation           = $app.WaitForPrinterCreation
        WorkingDirectory                 = $app.WorkingDirectory
    }

    # Stores each Application setting for export
    $Results += New-Object psobject -Property $properties
    $StartCount += 1
}

# Setting File name
$Date = Get-Date

$FileName = $Date.ToShortDateString() + $Date.ToLongTimeString()
$FileName = (($FileName -replace ":", "") -replace " ", "") -replace "/", ""
$FileName = "Apps" + $FileName + ".xml"
if ($null -eq $ExportLocation) {
    $ExportLocation = $FileName
}

# Exporting results
$Results | export-clixml $ExportLocation
Write-Verbose "Exported file located at $ExportLocation" -Verbose

Write-Verbose "Stop logging" -Verbose
Write-Verbose "Logfile located at $LogPS" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript | Out-Null
