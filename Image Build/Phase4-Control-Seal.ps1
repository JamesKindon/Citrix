#Phase 4 - Seal 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Get-InstalledSoftware.ps1'))

Write-Host \"====== Enable Windows Defender real time scan\"
Set-MpPreference -DisableRealtimeMonitoring $false

Write-Host \"====== Sysprep\"
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit
while ($true) { 
    $imageState = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State | Select-Object ImageState
    if ($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { 
        Write-Output $imageState.ImageState; Start-Sleep -s 10 
    }
    else { 
        break 
    } 
}
