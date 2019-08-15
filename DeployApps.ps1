

# TO DO: 
# Customisation Routines per Applications as required
# Add Internet Check

# Script to utilise the work of Trond and Aaron Parker
# Leverage the Evergreen approach of Enablement Applications

#.\DeployApps.ps1 -Applications 7zip,AdobeReaderDC,BISF,chrome,firefox,FileZilla,KeePass,Java,Notepadplusplus -CleanupAfterInstall

param (
    [Parameter(Mandatory=$False,ValueFromPipeline=$true)] [String] $InstallerLocation = "$env:SystemDrive\AppInstallers",
    [Parameter(Mandatory=$False,ValueFromPipeline=$true)] [Switch] $CleanupAfterInstall = $False,
    [Parameter(Mandatory=$True,ValueFromPipeline=$true)] [ValidateSet('chrome',
    'firefox',
    '7zip',
    'AdobeReaderDC',
    'sysinternals',
    'Greenshot',
    'Notepadplusplus',
    'VCRedists',
    'BISF',
    'KeePass',
    'FileZilla',
    'PaintDotNet',
    'ControlUp',
    'Java',
    'VSCode')] [Array] $Applications
)

$ScriptURL_Chrome = "https://raw.githubusercontent.com/haavarstein/Applications/master/Google/Chrome%20Enterprise/Install.ps1"
$ScriptURL_FireFox = "https://raw.githubusercontent.com/haavarstein/Applications/master/Mozilla/Firefox/Install.ps1"
$ScriptURL_7zip = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/7-Zip/Install.ps1"
$ScriptURL_AdobeReaderDC = "https://raw.githubusercontent.com/haavarstein/Applications/master/Adobe/Reader%20DC/Install.ps1"
$ScriptURL_SysInternals = "https://raw.githubusercontent.com/haavarstein/Applications/master/Microsoft/Sysinternals/Install.ps1"
$ScriptURL_Greenshot = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/GreenShot/Install.ps1"
$ScriptURL_Notepadplusplus = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/NotePadPlusPlus/Install.ps1"
$ScriptURL_BISF = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/BISF/Install.ps1"
$ScriptURL_KeePass = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/KeePass/Install.ps1"
$ScriptURL_FileZilla = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/FileZilla/Install.ps1"
$ScriptURL_PaintDotNet = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/Paint%20NET/Install.ps1"
$ScriptURL_ControlUp = "https://raw.githubusercontent.com/haavarstein/Applications/master/Misc/ControlUp/Install_Agent.ps1"
$ScriptURL_Java = "https://raw.githubusercontent.com/haavarstein/Applications/master/Oracle/Java%20JRE/Install.ps1"
$ScriptURL_VSCode = "https://raw.githubusercontent.com/haavarstein/Applications/master/Microsoft/Visual%20Studio%20Code/Install.ps1"

$scriptPath = $script:MyInvocation.MyCommand.Path
$StartDir = Split-Path $scriptpath

if (!(Test-Path $InstallerLocation)) {
    new-item -ItemType Directory -Path $InstallerLocation -Force
}

Set-Location $InstallerLocation 

# Function to Execute 
function DeployApps {
    foreach ($Application in ($Applications | Sort-Object -Unique)) {
        switch ($Application) {
            'chrome' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_Chrome
            } 'firefox' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_FireFox
            } '7zip' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_7zip
            } 'AdobeReaderDC' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_AdobeReaderDC
            } 'sysinternals' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_SysInternals
            } 'Greenshot' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_Greenshot
            } 'notepadplusplus' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_Notepadplusplus
            } 'VCRedists' {
                InstallVCRedists
            } 'BISF' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_BISF
            } 'KeePass' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_KeePass
            } 'FileZilla' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_FileZilla
            } 'PaintDotNet' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_PaintDotNet
            } 'ControlUp' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_ControlUp
            } 'Java' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_Java
            } 'VSCode' {
                GetAppInstallScript -InstallScriptURL $ScriptURL_VSCode
            }
        }
    }
    Set-Location $StartDir

    if ($CleanupAfterInstall.IsPresent) {
        Write-Host "Deleting all Installers and Downloaded Scripts" -ForegroundColor Green
        Remove-Item -Path $InstallerLocation -Recurse -Force -ErrorAction SilentlyContinue
    }   
}

Function Set-Repository {
    # https://github.com/aaronparker/build-azure-lab/blob/master/rds-packer/Rds-CoreApps.ps1
    # Trust the PSGallery for installing modules
    If (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
        Write-Verbose "Trusting the repository: PSGallery"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
}

# Function to Install VcRedists via Aaron Parker
function InstallVCRedists {
    # https://docs.stealthpuppy.com/vcredist/
    Set-Repository
    Install-Module -Name VcRedist -Force
    Import-Module -Name VcRedist
    
    # Download the Redists
    if (!(Test-Path "$InstallerLocation\VcRedist")) {
        New-Item "$InstallerLocation\VcRedist" -ItemType Directory
    }
    
    Get-VcList | Get-VcRedist -Path "$InstallerLocation\VcRedist"
    # Install the Redists
    $VcList = Get-VcList
    Install-VcRedist -Path "$InstallerLocation\VcRedist" -VcList $VcList -Silent
}

# Function to Download the Installer Script
function GetAppInstallScript {
    param (
        [Parameter(Mandatory)]
        [String] $InstallScriptURL
    )
    #Download the Script here
    Write-Host "Downloading and Executing the $Application Installer Script" -ForegroundColor Green

    $ScriptURL = $InstallScriptURL

    if (!(Test-Path "$InstallerLocation\$Application")) {
        New-Item -ItemType Directory -Path "$InstallerLocation\$Application" -Force
    }
    
    Set-Location $InstallerLocation\$Application
    
    (new-object net.webclient).DownloadFile($ScriptURL,"$InstallerLocation\Install_$Application.ps1")
    & "$InstallerLocation\Install_$Application.ps1"
    
    Set-Location $InstallerLocation
}

# Run the Thing
DeployApps



