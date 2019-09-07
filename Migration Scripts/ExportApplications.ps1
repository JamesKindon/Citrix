<#
.SYNOPSIS
Exports applications from all, or a specified delivery group to an XML file. To be used in conjunction with ImportApplications.ps1

Some of the original code is found here, but had lots of issues
https://discussionsqa3.citrix.com/topic/356373-xendesktopxenapp-7x-applications-exporting-importing/

.DESCRIPTION
provides a clean export of existing Applications via Clixml (See notes)

Use the corresponding ImportApplications.ps1 script to retrieve to import the export from this script
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ImportApplications.ps1

.EXAMPLE
The following example will export all apps from all Delivery Group and output the XML files to C:\Temp
.\ExportApplications.ps1 -OutputLocation "C:\Temp\"

.EXAMPLE
The following example will export all apps from all Delivery Group and output the XML files to the current location
.\ExportApplications.ps1

.EXAMPLE
The following example will export all apps from a single specified Delivery Group and output the XML files to C:\Temp
.\ExportApplications.ps1 -DeliveryGroup "Really Great Delivery Group" -OutputLocation "C:\Temp\"

.EXAMPLE
The following example will export all apps from a single specified Delivery Group and output the XML files to C:\Temp.
The following example specifies Citrix Cloud as the export location and thus calls Citrix Cloud based PS Modules.

.\ExportApplications.ps1 -DeliveryGroup "Really Great Delivery Group" -OutputLocation "C:\Temp\" -Cloud

.NOTES

.LINK
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [String] $DeliveryGroup = $null,

    [Parameter(Mandatory = $False)]
    [String] $OutputLocation = $null,

    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\ApplicationExport.log"
$StartDTM = (Get-Date)

# Optionally set configuration without being prompted
#$DeliveryGroup = "Delivery Group Name"
#$ExportLocation = "C:\temp\"

function GetAppsFromDeliveryGroup {
    foreach ($DeliveryGroup in $AllDeliveryGroups) {
        
        Write-Verbose "Using Delivery Group: $($DeliveryGroup.Name) as targeted Delivery Group" -Verbose
        try {
            $DeliveryGroupID = (Get-BrokerDesktopGroup -Name $DeliveryGroup.Name).Uid
        }
        catch {
            Write-Warning "$_" -Verbose
        }
        
        if ($null -ne $DeliveryGroupID) {
            Write-Verbose "Attempting to Get a list of Apps from Delivery Group: $($DeliveryGroup.Name)" -Verbose
            # Get a list of applications
            try {
                $apps = Get-BrokerApplication -AssociatedDesktopGroupUid $DeliveryGroupID -MaxRecordCount 2147483647


                $Count = ($Apps | Measure-Object).Count
                $StartCount = 1

                Write-Verbose "There are $Count Applications to process for $($DeliveryGroup.Name)" -Verbose

                $Results = @()

                foreach ($app in $apps) {
                    Write-Verbose "Processing Application $StartCount ($($App.PublishedName)) of $Count" -Verbose
                    # Builds Properties for each application ready for export
                    $Properties = @{
                        AdminFolderName                  = $app.AdminFolderName
                        AdminFolderUid                   = $app.AdminFolderUid
                        ApplicationName                  = $app.ApplicationName
                        ApplicationType                  = $app.ApplicationType
                        AssociatedApplicationGroupUUIDs  = $app.AssociatedApplicationGroupUUIDs
                        AssociatedApplicationGroupUids   = $app.AssociatedApplicationGroupUids
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
                        Tags                             = $app.Tags
                    }

                    # Stores each Application setting for export
                    $Results += New-Object psobject -Property $properties
                    $StartCount += 1
                }

                # Setting File name
                $Date = Get-Date

                $FileName = $Date.ToShortDateString() + $Date.ToLongTimeString()
                $FileName = (($FileName -replace ":", "") -replace " ", "") -replace "/", ""
                $FileName = $DeliveryGroup.Name + "_Apps_" + $FileName + ".xml"
                $FileName = ($FileName -replace " ", "_")
                if (!($OutputLocation)) {
                    $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
                    $ExportLocation = $ScriptDir + "\" + $FileName
                }
                else {
                    $ExportLocation = $OutputLocation + "\" + $FileName
                }

                # Exporting results
                $Results | export-clixml $ExportLocation
                Write-Verbose "Exported file located at $ExportLocation" -Verbose
            }
            catch {
                Write-Warning "$_" -Verbose
            }
        }
        else {
            Write-Warning "Could not retrieve Delivery Group ID for $($DeliveryGroup)" -Verbose
            Write-Warning "Attempting next Delivery Group" -Verbose
        }
    }
}

Add-PSSnapin citrix*

if ($Cloud.IsPresent) {
    Write-Verbose "Cloud Switch Specified, Attempting to Authenticate to Citrix Cloud" -Verbose
    try {
        Get-XDAuthentication # Added a Cloud Check - not validated yet
    }
    catch {
        Write-Warning "$_" -Verbose
        Write-Warning "Authentication Failed. Bye"
        Break
    }
}

Write-Verbose "Start Logging" -Verbose
Start-Transcript $LogPS | Out-Null

if (!($DeliveryGroup)) {
    Write-Verbose "No Delivery Group Sepcified. Processing all Delivery Groups" -Verbose
    try {
        $AllDeliveryGroups = Get-BrokerDesktopGroup
        GetAppsFromDeliveryGroup
    }
    catch {
        Write-Warning "$_" -Verbose
    }

}
else {
    try {
        $AllDeliveryGroups = Get-BrokerDesktopGroup $DeliveryGroup
        GetAppsFromDeliveryGroup
    }
    catch {
        Write-Verbose "$_" -Verbose
    }
}

Write-Verbose "Stop logging" -Verbose
Write-Verbose "Logfile located at $LogPS" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript | Out-Null
