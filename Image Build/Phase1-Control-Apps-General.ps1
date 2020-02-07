#Phase 1 - Apps
Write-Host "====== Install 7zip\"
choco install 7zip.install -Y

Write-Host "====== Install Notepad ++\"
choco install notepadplusplus -Y

Write-Host "====== Install VLC\"
choco install vlc -Y

Write-Host "====== Install FSLogix Components\"
choco install fslogix -Y
choco install fslogix-rule -Y

Write-Host "====== Install BIS-F\"
choco install bis-f -Y

Write-Host "====== Install Microsoft Edge\"
choco install microsoft-edge -Y
#---------Preferences

Write-Host "====== Install Google Chrome Enterprise\"
choco install googlechrome -Y

Write-Host "====== Install Adobe Reader DC\"
choco install adobereader -Y

Write-Host "====== Install Microsoft Teams\"
choco install microsoft-teams.install -Y

Write-Host "====== Install Microsoft Office 365 ProPlus\"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Phase1-MicrosofOffice.ps1'))

Write-Host "====== Install Microsoft OneDrive\"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Phase1-MicrosoftOneDrive.ps1'))

#---------OldCalc
#Start-Process -FilePath "\\\Citrix\oldcalcwin10\Old Calculator for Windows 10.exe" -Wait -PassThru

