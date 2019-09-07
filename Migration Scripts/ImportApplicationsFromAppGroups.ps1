<#
.SYNOPSIS
via an exported XML from an existing AppGroup Export, Creates published applications and assigns to AppGroup

.DESCRIPTION
requires a clean export of existing AppGroups via Clixml (See notes)

requires the folder structure to be in place to support imported applications. Use corresponding Scripts to deal with this
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/MigrateAppFolderStructure.ps1

requires that AppGroups Exist to support the imported applications. Use corresponding Scripts to deal with this
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ImportAppGroups.ps1


.EXAMPLE
The following Example will import via a selected XML file, all apps and assigned to the appropriate AppGroup
.\ImportApplicationsFromAppGroup.ps1

.EXAMPLE
The following Example will import via a selected XML file, all apps and assigned to the appropriate AppGroup
The following example specifies Citrix Cloud as the import location and thus calls Citrix Cloud based PS Modules.
.\ImportApplicationsFromAppGroup.ps1 -Cloud

.NOTES
Folder Structure for Apps must exist
AppGroups must Exist
Use corresponding export scripts to achieve appropriate export
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/MigrateAppFolderStructure.ps1
https://github.com/JamesKindon/Citrix/blob/master/Migration%20Scripts/ImportAppGroups.ps1

.LINK
#>


[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False)]
    [Switch] $Cloud
)

$LogPS = "${env:SystemRoot}" + "\Temp\ApplicationFromAppGroupImport.log"
$StartDTM = (Get-Date)

$Apps = $null

# Optionally set configuration without being prompted
#$Apps = Import-Clixml -path C:\temp\ApplicationsFromAppGroups.xml

# Load Assemblies
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

Add-PSSnapin citrix*

function ImportandSetIcon {
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

}

function AddUsersToApp {
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

function AddTags {
    if (Get-BrokerTag -Name $Tag -ErrorAction SilentlyContinue) {
        Write-Verbose "Tag: $($Tag) Exists. Attempting to assign" -Verbose
        try {
            Get-BrokerTag -Name $Tag | Add-BrokerTag -Application $app.PublishedName
            Write-Verbose "SUCCESS: Assigned Tag: $($Tag) to $($app.PublishedName)" -Verbose
        }
        catch {
            Write-Warning "$_" -Verbose
        } 
    }
    else {
        try {
            Write-Verbose "Tag: $($Tag) does not exist. Attempting to create" -Verbose
            New-BrokerTag -Name $Tag | Out-Null
            Write-Verbose "SUCCESS: Created Tag: $($Tag). Attempting to Assign" -Verbose
            Get-BrokerTag -Name $Tag | Add-BrokerTag -Application $app.PublishedName
            Write-Verbose "SUCCESS: Assigned Tag: $($Tag) to $($app.PublishedName)" -Verbose
        }
        catch {
            Write-Warning "$_" -Verbose
        } 
    }
}

function AddToAdditionalAppGroups {
    try {
        $AG = Get-BrokerApplicationGroup | Where-Object { $_.UUID -eq $AppGroup.Guid }
        if ($AG) {
            try {
                Get-BrokerApplication $App.PublishedName | Add-BrokerApplication -ApplicationGroup $AG.Name -ErrorAction SilentlyContinue
                Write-Verbose "AppGroup: $($AG.Name) Assignment Updated" -Verbose
            }
            catch {
                Write-Warning "$_" -Verbose
                Write-Warning "Adding $($App.PublishedName) to AppGroup: $($AG.Name) Failed."
            }
        }   
    }
    catch {
        Write-Warning "$_" -Verbose
        Write-Warning "AppGroup with UUID $($AppGroup.Guid) does not exist. Please create the AppGroup"
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

foreach ($App in $Apps) {
    Write-Verbose "Processing Application $StartCount of $Count" -Verbose
    if (Get-BrokerApplication -PublishedName $App.PublishedName -ErrorAction SilentlyContinue) {
        Write-Verbose "Application with Name: $($App.PublishedName) already exists. Ignoring" -Verbose
        Write-Warning "AppGroup Memberships may not be in Sync with export due to existing application" -Verbose

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
            ########  Deal with AppGroups  
            if ($null -ne $app.AssociatedApplicationGroupUUIDs) {

                $ListofAppGroups = $app.AssociatedApplicationGroupUUIDs
                $CountOfAppGroups = ($ListofAppGroups | Measure-Object).Count
                Write-Verbose "$($app.PublishedName) should be a member of $($CountOfAppGroups) AppGroups. Searching for AppGroups" -Verbose
                foreach ($AppGroup in $ListofAppGroups) {
                    try {
                        $AG = Get-BrokerApplicationGroup | Where-Object { $_.UUID -eq $appGroup.Guid }
                        if ($AG) {
                            Write-Verbose "AppGroup: $($AG.Name) Found for $($App.PublishedName)" -Verbose
                        }   
                    }
                    catch {
                        Write-Warning "$_" -Verbose
                        Write-Warning "AppGroup does not exist. Please create the AppGroup" -Verbose
                    }
                }
                if ($null -ne $AG) {
                    Write-Verbose "AppGroup: $($AG.Name) used for Initial Application Creation and Assignment" -Verbose
                }
                $MakeApp += ' -ApplicationGroup $AG.Name' #Use the last AppGroup Defined in the array
            }
            ########            

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
            Write-Warning "FAILURE: Application Group does not exist" -Verbose
            Write-Warning "$_" -Verbose
            $failed = $true
        }

        $StartCount += 1

        if ($failed -ne $true) {
            # Set Application Icons
            ImportandSetIcon

            # Adding Users and Groups to application associations
            If ($null -ne $app.AssociatedUserNames) {
                AddUsersToApp
            }
            
            # Adding Tags to Applications
            if ($null -ne $app.Tags) {
                $Tags = $app.Tags
                foreach ($Tag in $Tags) {
                    AddTags
                }
            }
            
            # Add To Additional AppGroups
            if ($CountOfAppGroups -gt 1) {
                Write-Verbose "Ensuring $($app.PublishedName) is a member of all specified AppGroups ($($CountOfAppGroups)). Searching for AppGroups" -Verbose
                foreach ($AppGroup in $ListofAppGroups) {
                    AddToAdditionalAppGroups
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
Stop-Transcript | Out-Null
