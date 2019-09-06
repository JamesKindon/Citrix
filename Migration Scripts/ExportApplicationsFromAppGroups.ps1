<#
.SYNOPSIS

.DESCRIPTION
provides a clean export of existing Applications via Clixml (See notes)


.EXAMPLE
The following example will export all apps from all Delivery Group and output the XML files to the current location
.\ExportApplicationsFromAppGroups

.EXAMPLE
The following example will export all apps from all AppGroups and output the XML files to C:\Temp
.\ExportApplicationsFromAppGroups -OutputFile "C:\temp"

.EXAMPLE
The following example will export all apps from a single specified AppGroup and output the XML files to C:\Temp
.\ExportApplicationsFromAppGroups -AppGroup "My AppGroup" -OutputFile "C:\temp"

.EXAMPLE
The following example will export all apps from a single specified AppGroup and output the XML files to C:\Temp.
The following example specifies Citrix Cloud as the export location and thus calls Citrix Cloud based PS Modules
.\ExportApplicationsFromAppGroups -AppGroup "My AppGroup" -OutputFile "C:\temp" -Cloud

.NOTES
To be used in conjunction with the ImportApplicationsFromAppGroups.ps1 Script

.LINK
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [String] $AppGroup = $null,

    [Parameter(Mandatory = $False)]
    [String] $OutputLocation = $null,

    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\AppsFromAppGroupExport.log"
$StartDTM = (Get-Date)

# Optionally set configuration without being prompted
#$AppGroup = "AppGroup Name"
#$ExportLocation = "C:\temp\"

function GetApps {
    try {

        $Count = ($Apps | Measure-Object).Count
        $StartCount = 1

        Write-Verbose "There are $Count Applications in AppGroups to process" -Verbose

        $Results = @()

        foreach ($app in $apps) {
            Write-Verbose "Processing Application $StartCount ($($App.PublishedName)) of $Count" -Verbose
            $AppGroupMemberships = $app.AssociatedApplicationGroupUids
            foreach ($AppGroupMembership in $AppGroupMemberships) {
                try {
                    $AppGroup = Get-BrokerApplicationGroup -Uid $AppGroupMembership
                    Write-Verbose "$($App.PublishedName) is a member of $($AppGroup.Name)" -Verbose
                }
                catch {
                    Write-Warning "$_" -Verbose
                }
            }
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
            }

            # Stores each Application setting for export
            $Results += New-Object psobject -Property $properties
            $StartCount += 1
        }
        # Exporting results
        $Results | export-clixml $ExportLocation
        Write-Verbose "Exported file located at $ExportLocation" -Verbose                 
    }
    catch {
        Write-Warning "$_" -Verbose
    }           
}

Write-Verbose "Start Logging" -Verbose
Start-Transcript $LogPS | Out-Null

Add-PSSnapin citrix*

# Setting File name
$Date = Get-Date

$FileName = $Date.ToShortDateString() + $Date.ToLongTimeString()
$FileName = (($FileName -replace ":", "") -replace " ", "") -replace "/", ""
$FileName = "Apps_" + $FileName + ".xml"
$FileName = ($FileName -replace " ", "_")
if (!($OutputLocation)) {
    $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
    $ExportLocation = $ScriptDir + "\" + $FileName
}
else {
    $ExportLocation = $OutputLocation + "\" + $FileName
}

if (!($AppGroup)) {
    Write-Verbose "No AppGroup Sepcified. Processing all Applications in All AppGroups" -Verbose
    try {
        $apps = Get-BrokerApplication | Where-Object { $_.AssociatedApplicationGroupUids -ne $null }
        GetApps
    }
    catch {
        Write-Warning "$_" -Verbose
    }
}
else {
    Write-Verbose "AppGroup: $($AppGroup) Sepcified. Processing all Applications in $($AppGroup)" -Verbose
    try {
        $AG = Get-BrokerApplicationGroup -Name $AppGroup
        $apps = Get-BrokerApplication | Where-Object { $_.AssociatedApplicationGroupUids -eq $AG.Uid }
        GetApps
    }
    catch {
        Write-Verbose "$_" -Verbose
    }
}

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

Write-Verbose "Stop logging" -Verbose
Write-Verbose "Logfile located at $LogPS" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript | Out-Null
