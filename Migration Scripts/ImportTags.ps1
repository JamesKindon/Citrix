<#
.SYNOPSIS
Imports Tags from an XML Export

.DESCRIPTION
requires a clean export of existing Tags via Clixml (See notes)

Use the corresponding ExportTags.ps1 script to retrieve the appropriate export files
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ExportTags.ps1

.EXAMPLE
The following Example will prompt for an XML Import Files and then create the Tags
.\ImportTags.ps1 

.EXAMPLE
The following Example will prompt for an XML Import Files and then create the Tags. It will attempt to call the Citrix Cloud Modules
.\ImportTags.ps1 -Cloud

.NOTES
Export required from existing farm
Use corresponding export script to achieve appropriate export
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ExportTags.ps1

.LINK
#>

[CmdletBinding()]
Param (

    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\TagsImport.log"
$StartDTM = (Get-Date)

$AppGroups = $null

# Optionally set configuration without being prompted
#$Tags = Import-Clixml -path C:\temp\Tags.xml

# Load Assemblies
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

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

# If Not Manually set, prompt for variable configurations
if ($null -eq $Tags) {
    Write-Verbose "Please Select an XML Import File" -Verbose
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter           = 'XML Files (*.xml)|*.*'
    }
    $null = $FileBrowser.ShowDialog()
    try {
        $Tags = Import-Clixml -Path $FileBrowser.FileName
    }
    catch {
        Write-Warning "No input file selected. Exit"
        Break
    }
}

$Count = ($Tags | Measure-Object).Count
$StartCount = 1

Write-Verbose "There are $Count Tags to process" -Verbose

foreach ($Tag in $Tags) {
    Write-Verbose "Processing Tags $StartCount of $Count" -Verbose
    if (Get-BrokerTag -Name $Tag.Name -ErrorAction SilentlyContinue) {
        Write-Verbose "Tags with Name: $($Tag.Name) already exists. Ignoring" -Verbose
        $StartCount += 1
    }
    else {
        #Resetting failure detection
        $failed = $false
        #Creating Tags
        Write-Verbose "Attempting to create Tags: $($Tag.Name)" -Verbose
        try {
            New-BrokerTag -Name $Tag.Name -Description $Tag.Description | Out-Null
            Write-Verbose "SUCCESS: Tag Succesfully Created: $($Tag.Name)" -Verbose
        }
        catch {
            Write-Warning "FAILURE: Creating Tag: $($Tag.Name) failed. Attempting next Tag" -Verbose
            Write-Warning "$_" -Verbose
            $failed = $true
        }

        $StartCount += 1
    }
}

Write-Verbose "Stop logging" -Verbose
Write-Verbose "Logfile located at $LogPS" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript  | Out-Null
