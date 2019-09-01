<#
.SYNOPSIS
via an exported XML from an existing environment, replicate exported folder structure

.DESCRIPTION
requires a clean export of an existing folder structure to Clixml (See notes)

.EXAMPLE
.\MigrateAppFolderStructure.ps1

.NOTES
Export required folder structure

$ExportLocation = 'PATH HERE\AppFolderStructure.xml'

Get-BrokerAdminFolder -MaxRecordCount 100000 | Export-Clixml -Path $ExportLocation

.LINK
#>

# Load Assemblies
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

Add-PSSnapin citrix*

#Get-XDAuthentication

$AdminFolders = $null

$LogPS = "${env:SystemRoot}" + "\Temp\AppFolderMigration.log"

# Optionally set configuration without being prompted
#$AdminFolders = Import-Clixml -path C:\temp\AppFolderStructure.xml

# If Not Manually set, prompt for variable configurations
if ($null -eq $AdminFolders) {
    Write-Verbose "Please Select an XML Import File" -Verbose
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter           = 'XML Files (*.xml)|*.*'
    }
    $null = $FileBrowser.ShowDialog()

    $AdminFolders = Import-Clixml -Path $FileBrowser.FileName
}

$Count = ($AdminFolders | Measure-Object).Count
$StartCount = 1

$StartDTM = (Get-Date)

Write-Verbose "Start Logging" -Verbose
Start-Transcript $LogPS | Out-Null

Write-Verbose "There are $Count folders to process" -Verbose
Write-Verbose "Folder $StartCount is a system folder and will be ignored" -Verbose

foreach ($Folder in $AdminFolders) {
    if ($Folder.Name -eq ($Folder.FolderName + "\")) {
        Write-Verbose "Processing Folder $StartCount of $Count" -Verbose
        Write-Verbose "Folder: $($Folder.FolderName) is a root folder" -Verbose
        if (!(Get-BrokerAdminFolder -Name $Folder.Name -ErrorAction SilentlyContinue)) {
            Write-Verbose "Processing Folder $StartCount of $Count" -Verbose
            Write-Warning "Folder: $($Folder.FolderName).......does not exist" -Verbose
            Write-Verbose "Creating root Folder: $($Folder.FolderName)" -Verbose
            try {
                New-BrokerAdminFolder $Folder.FolderName | Out-Null
            }
            catch {
                Write-Warning "An error occurred creating the Folder:" -Verbose
                Write-Warning $_ -Verbose
            }
        }
        else {
            Write-Verbose "Root Folder: $($Folder.Name).......Exists" -Verbose
        }
        $StartCount += 1
    }
    if ($Folder.Name -ne ($Folder.FolderName + '\')) {
        if ($Folder.Name) {
            $ParentFolder = Split-Path ($Folder).Name
            Write-Verbose "Folder: $($Folder.FolderName) should be a sub Folder of Parent Folder: $($ParentFolder)" -Verbose
        
            $PF = $ParentFolder + "\"
            if (Get-BrokerAdminFolder -Name $PF -ErrorAction SilentlyContinue) {
                Write-Verbose "Processing Folder $StartCount of $Count" -Verbose
                Write-Verbose "Parent Folder: $($PF) for Folder: $($Folder.FolderName).......Exists" -Verbose
                if (Get-BrokerAdminFolder -Name $Folder.Name -ErrorAction SilentlyContinue) {
                    Write-Verbose "Folder: $($Folder.Name).......Exists" -Verbose
                }
                else {
                    Write-Warning "Folder: $($Folder.Name).......does not exist" -Verbose
                    Write-Verbose "Creating new Application Folder: $($Folder.FolderName) in Parent Folder: $($PF)" -Verbose
                    try {
                        New-BrokerAdminFolder -FolderName $Folder.FolderName -ParentFolder $PF | Out-Null
                    }
                    catch {
                        Write-Warning "An error occurred creating the Folder:" -Verbose
                        Write-Warning $_ -Verbose
                    }
                }
            }
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