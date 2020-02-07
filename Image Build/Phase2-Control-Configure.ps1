#Phase 2 - Configure
Write-Host "====== Configuring Start Layouts\"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/CreateShortcuts.ps1'))
New-Item -Type Directory C:\Tools -Force | Out-Null
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/CustomLayout-2019-Basic-Office-x64.xml' -outfile 'c:\Tools\CustomLayout-2019-Basic-Office-x64.xml'
Import-StartLayout -LayoutPath 'c:\Tools\CustomLayout-2019-Basic-Office-x64.xml' -MountPath 'c:\' -Verbose

Write-Host "====== Downloading AppMasking Files\"
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JamesKindon/Citrix/master/FSLogix/AppMasking/Start%20Menu.fxr' -Outfile 'C:\Program Files\FSLogix\Apps\Rules\Start Menu.fxr'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JamesKindon/Citrix/master/FSLogix/AppMasking/Start%20Menu.fxa' -Outfile 'C:\Program Files\FSLogix\Apps\Rules\Start Menu.fxa'

Write-Host "====== Configuring Default File Assocs\"
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Phase4-DefaultFileAssocs.ps1'))

#---------PhotoViewer
#---------Desktop Shortcuts

#Phase 3 - Optimize
#---------Windows 10 Script
#Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Windows%2010%20Optimisation/Invoke-RemoveBuiltinApps.ps1" -UseBasicParsing -OutFile "c:\Tools\Invoke-RemoveBuiltinApps.ps1"
#& "C:\Tools\Invoke-RemoveBuiltinApps.ps1"

#---------Autoruns
#---------Citrix Optimizer