<#
.SYNOPSIS
via an exported XML from an existing Delivery Group, Creates published applications against a new delivery group

Some of the original code is found here, but had lots of issues
https://discussionsqa3.citrix.com/topic/356373-xendesktopxenapp-7x-applications-exporting-importing/

.DESCRIPTION
requires a clean export of existing Applications via Clixml (See notes)

requires the folder structure to be in place to support imported applications. Use corresponding Scripts to deal with this
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/MigrateAppFolderStructure.ps1

Use the corresponding ExportApplications.ps1 script to retrieve the appropriate export files
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ExportApplications.ps1

.EXAMPLE
The following Example will import via a selected XML file, all apps in the specified delivery group
.\ImportApplications.ps1 -DeliveryGroup "Really Great Delivery Group"

.EXAMPLE
The following example will import via a selected XML file, all apps in the specified delivery group
The following example specifies Citrix Cloud as the import location and thus calls Citrix Cloud based PS Modules.
.\ImportApplications.ps1 -DeliveryGroup "Really Great Delivery Group" -Cloud


.NOTES
Export required from existing delivery group
Use corresponding export script to achieve appropriate export


# To do
Add App Group Support

.LINK
#>


[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [String] $DeliveryGroup = $null,

    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\ApplicationImport.log"
$StartDTM = (Get-Date)

$Apps = $null

# Optionally set configuration without being prompted
#$Apps = Import-Clixml -path C:\temp\Applications.xml
#$DeliveryGroup = "Del Group Name"

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
if ($null -eq $Apps) {
    Write-Verbose "Please Select an XML Import File" -Verbose
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter           = 'XML Files (*.xml)|*.*'
    }
    $null = $FileBrowser.ShowDialog()
    try {
        $Apps = Import-Clixml -Path $FileBrowser.FileName
    }
    catch {
        Write-Warning "No input file selected. Exit"
        Break
    }
}

$Count = ($Apps | Measure-Object).Count
$StartCount = 1

Write-Verbose "There are $Count Applications to process" -Verbose

# Get Delivery Groups if specified already
if ($DeliveryGroup) {
    try {
        $DelGroupID = (Get-BrokerDesktopGroup -Name $DeliveryGroup).Uid
        $DelGroup = Get-BrokerDesktopGroup -Uid $DelGroupID
        Write-Verbose "Using Delivery Group: $($DelGroup.Name) as targeted Delivery Group" -Verbose
    }
    catch {
        Write-Warning "Delivery Group: $($DeliveryGroup) not found. Exit Script." -Verbose
        Break
    }
}
else {
    $DeliveryGroups = Get-BrokerDesktopGroup | Format-list -property Name, UID | out-string
    Write-Host  "Delivery groups : $DeliveryGroups"
    $DelGroupID = Read-Host -Prompt 'Specify Delivery Group UID to Target Imported Apps'
    $DelGroup = Get-BrokerDesktopGroup -Uid $DelGroupID
    Write-Verbose "Using Delivery Group: $($DelGroup.Name) as targeted Delivery Group" -Verbose
}


foreach ($App in $Apps) {
    Write-Verbose "Processing Application $StartCount of $Count" -Verbose
    if (Get-BrokerApplication -PublishedName $App.PublishedName -ErrorAction SilentlyContinue) {
        Write-Verbose "Application with Name: $($App.PublishedName) already exists. Ignoring" -Verbose
        $StartCount += 1
    }
    else {
        
        #Resetting failure detection
        $failed = $false
        #Publishing Application
        Write-Verbose "Attempting to Publish Application: $($app.PublishedName)" -Verbose

        if ($app.CommandLineArguments.Length -lt 2) { $app.CommandLineArguments = " " }

        try {
            $Results = @()
            #Prep for Application Import - Removing Null values
            $MakeApp = 'New-BrokerApplication -ApplicationType HostedOnDesktop'
            if ($null -ne $app.CommandLineExecutable) { $MakeApp += ' -CommandLineExecutable $app.CommandLineExecutable' }
            if ($null -ne $app.Description) { $MakeApp += ' -Description $app.Description' }
            if ($null -ne $app.ClientFolder) { $MakeApp += ' -ClientFolder $app.ClientFolder' }
            if ($null -ne $app.CommandLineArguments) { $MakeApp += ' -CommandLineArguments $app.CommandLineArguments' }
            if ($null -ne $app.PublishedName) { $MakeApp += ' -Name $app.PublishedName' }
            if ($null -ne $app.PublishedName) { $MakeApp += ' -PublishedName $app.PublishedName' }
            if ($null -ne $app.Enabled) { $MakeApp += ' -Enabled $app.Enabled' }
            if ($null -ne $app.WorkingDirectory) { $MakeApp += ' -WorkingDirectory $app.WorkingDirectory' }
            if ($app.AdminFolderName -ne "") { $MakeApp += ' -AdminFolder $app.AdminFolderName' }
            if ($app.UserFilterEnabled -eq "True") { $MakeApp += ' -UserFilterEnabled $app.UserFilterEnabled' }
            if ($null -ne $DelGroup) { $MakeApp += ' -DesktopGroup $DelGroup' }
            # AppGroup?

            #Creating Application
            $Results = Invoke-Expression $MakeApp | out-string -Stream
            $Results = $Results[16] -replace '^[^:]+:', ''
            $Results = $Results.Trim()

            if (Get-BrokerApplication -PublishedName $App.Name -ErrorAction SilentlyContinue) {
                Write-Verbose "SUCCESS: Application Succesfully Published: $($App.Name)" -Verbose
            }
        }
        catch {
            Write-Warning "FAILURE: Creating Application: $($App.Name) failed" -Verbose
            Write-Warning "$_" -Verbose
            $failed = $true
        }

        $StartCount += 1

        if ($failed -ne $true) {
            #Importing Icon
            $IconUid = New-BrokerIcon -EncodedIconData $app.EncodedIconData

            #Setting applications icon
            try {
                $application = Get-BrokerApplication -BrowserName $App.PublishedName
                Set-BrokerApplication -InputObject $application -IconUid $IconUid.Uid
                write-Verbose "Icon changed for application: $($app.PublishedName)" -Verbose
            }
            catch {
                Write-Warning "Setting App Icon Failed for $($app.PublishedName)" -Verbose
                Write-Warning "$_" -Verbose
            }

            # Adding Users and Groups to application associations
            If ($null -ne $app.AssociatedUserNames) {
                try {
                    $users = $app.AssociatedUserNames 
                    foreach ($user in $users) {
                        $FullAppPath = $app.AdminFolderName + $app.PublishedName
                        Add-BrokerUser -Name "$user" -Application "$FullAppPath"
                        write-Verbose "User: $($User) Succesfully added for application (Limit Visibility): $($app.PublishedName)" -Verbose
                    }
                }
                catch {
                    Write-Warning $_.Exception.Message -Verbose
                    write-Warning "Error on User: $($user) for application: $($app.PublishedName)"  -Verbose
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
