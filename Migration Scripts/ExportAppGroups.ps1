<#
.SYNOPSIS
Exports AppGroups ready to be imported to another farm

.DESCRIPTION
provides a clean export of existing AppGroups via Clixml (See notes)

Use the corresponding ImportAppGroups.ps1 script to retrieve to import the export from this script
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ImportAppGroups.ps1

.EXAMPLE
The following example will export all AppGroups to C:\Temp
.\ExportAppFolderStructure.ps1 -OutputLocation "C:\Temp\"

.EXAMPLE
The following example will export all AppGroups to the current location
.\ExportAppFolderStructure.ps1

.EXAMPLE
The following example will export all AppGroups to C:\Temp an attempt to Auth to Citrix Cloud
.\ExportAppFolderStructure.ps1 -OutputLocation "C:\Temp\" -Cloud

.NOTES
Use corresponding import script to import the structure
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ImportAppGroups.ps1

.LINK
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [String] $OutputLocation = $null,

    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\AppGroupExport.log"
$StartDTM = (Get-Date)

# Optionally set configuration without being prompted
#$ExportLocation = 'PATH HERE\AppFolderStructure.xml'

Write-Verbose "Start Logging" -Verbose
Start-Transcript $LogPS | Out-Null

Add-PSSnapin citrix*

# Setting File name
$Date = Get-Date

$FileName = $Date.ToShortDateString() + $Date.ToLongTimeString()
$FileName = (($FileName -replace ":", "") -replace " ", "") -replace "/", ""
$FileName = "AppGroups_" + $FileName + ".xml"
$FileName = ($FileName -replace " ", "_")
if (!($OutputLocation)) {
    $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
    $ExportLocation = $ScriptDir + "\" + $FileName
}
else {
    $ExportLocation = $OutputLocation + "\" + $FileName
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

try {
    Write-Verbose "Exporting AppGroups" -Verbose
    $AppGroups = Get-BrokerApplicationGroup -MaxRecordCount 100000 
    $Count = ($AppGroups | Measure-Object).Count
    Write-Verbose "There are $($Count) AppGroups to export" -Verbose
    $AppGroups | Export-Clixml -Path $ExportLocation
    Write-Verbose "Exported file located at $ExportLocation" -Verbose
}
catch {
    Write-Warning "$_" -Verbose
}

Write-Verbose "Stop logging" -Verbose
Write-Verbose "Logfile located at $LogPS" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript | Out-Null
