<#
.SYNOPSIS
Imports AppGroups from an XML

.DESCRIPTION
requires a clean export of existing AppGroups via Clixml (See notes)

Use the corresponding ExportAppGroups.ps1 script to retrieve the appropriate export files
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ExportAppGroups.ps1

.EXAMPLE
The following Example will prompt for an XML Import Files and then create the AppGroups
.\ImportAppGroups.ps1 

.EXAMPLE
The following Example will prompt for an XML Import Files and then create the AppGroups. It will attempt to call the Citrix Cloud Modules
.\ImportAppGroups.ps1 -Cloud

.NOTES
Export required from existing farm
Use corresponding export script to achieve appropriate export
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ExportAppGroups.ps1

.LINK
#>

[CmdletBinding()]
Param (

    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\AppGroupImport.log"
$StartDTM = (Get-Date)

$AppGroups = $null

# Optionally set configuration without being prompted
#$AppGroups = Import-Clixml -path C:\temp\AppGroups.xml

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
if ($null -eq $AppGroups) {
    Write-Verbose "Please Select an XML Import File" -Verbose
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter           = 'XML Files (*.xml)|*.*'
    }
    $null = $FileBrowser.ShowDialog()
    try {
        $AppGroups = Import-Clixml -Path $FileBrowser.FileName
    }
    catch {
        Write-Warning "No input file selected. Exit"
        Break
    }
}

$Count = ($AppGroups | Measure-Object).Count
$StartCount = 1

Write-Verbose "There are $Count AppGroups to process" -Verbose

foreach ($AppGroup in $AppGroups) {
    Write-Verbose "Processing AppGroup $StartCount of $Count" -Verbose
    if (Get-BrokerApplicationGroup -Name $AppGroup.Name -ErrorAction SilentlyContinue) {
        Write-Verbose "AppGroup with Name: $($AppGroup.Name) already exists. Ignoring" -Verbose
        $StartCount += 1
    }
    else {
        #Resetting failure detection
        $failed = $false
        #Creating AppGroup
        Write-Verbose "Attempting to create AppGroup: $($AppGroup.Name)" -Verbose
        try {
            New-BrokerApplicationGroup -Name $AppGroup.Name -Description $AppGroup.Description -Enabled $AppGroup.Enabled -UserFilterEnabled $AppGroup.UserFilterEnabled | Out-Null
            if (Get-BrokerApplication -PublishedName $App.Name -ErrorAction SilentlyContinue) {
                Write-Verbose "SUCCESS: AppGroup Succesfully Created: $($AppGroup.Name)" -Verbose
            }
        }
        catch {
            Write-Warning "FAILURE: Creating AppGroup: $($AppGroup.Name) failed. Attempting next AppGroup" -Verbose
            Write-Warning "$_" -Verbose
            $failed = $true
        }

        $StartCount += 1

        if ($failed -ne $true) {
            #Assigning Users
            $Users = $AppGroup.AssociatedUserNames
            foreach ($User in $Users) {
                try {
                    Write-Verbose "Adding user: $($User) to $($AppGroup.Name)" -Verbose
                    Add-BrokerUser $User -ApplicationGroup $AppGroup.Name
                }
                catch {
                    Write-Warning "Failed to Add User to AppGroup: $($AppGroup.Name). Attempting next AppGroup"
                    Write-Warning "$_" -Verbose
                }
            }   
        }
    }
}

Write-Verbose "Stop logging" -Verbose
Write-Verbose "Logfile located at $LogPS" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript  | Out-Null
