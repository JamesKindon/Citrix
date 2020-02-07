#Phase 0 - Build
Write-Host "====== Disable Windows Defender real time scan\"
Set-MpPreference -DisableRealtimeMonitoring $true
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "====== Configure Regional Settings and Roles\"
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Phase0-SBCRegionalRoles.ps1'))

Write-Host "====== Install VCRedists\"
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Phase0-VCRedists.ps1'))

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
Write-Host "====== Install Microsoft .NET Framework\"
choco install dotnetfx -Y
