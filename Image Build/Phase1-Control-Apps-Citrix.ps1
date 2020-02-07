#Phase 1 - Apps - Citrix
Write-Host "====== Install Citrix VDA\"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/JamesKindon/Citrix/master/Image%20Build/Phase1-Control-Apps-CitrixVDA.ps1'))
#---------WEM
#Start-Process -FilePath "\\\Citrix\Workspace-Environment-Management-v-1912-01-00-01\Citrix Workspace Environment Management Agent Setup.exe" -ArgumentList "/install /quiet Cloud=0" -wait -PassThru

#---------CQI
#Start-Process -FilePath msiexec.exe -ArgumentList '/i "\\\Citrix\CitrixCQI\CitrixCQI.msi" OPTIONS="DISABLE_CEIP=1" /q' -wait -PassThru

#---------Optimizer + templates
#New-Item -Type Directory -Path "C:\Tools\CitrixOptimizer" -Force
#Copy-Item -Path "\\\Citrix\CitrixOptimizer\*" -Destination "C:\Tools\CitrixOptimizer\" -Recurse
#Set-ExecutionPolicy Bypass -Force
#& "C:\Tools\CitrixOptimizer\CtxOptimizerEngine.ps1" -mode Execute
##Use 3rd Party Optimizations
#Invoke-WebRequest -Uri "https://raw.githubusercontent.com/j81blog/Citrix_Optimizer_Community_Template_Marketplace/master/templates/John%20Billekens/JohnBillekens_3rd_Party_Components.xml" -UseBasicParsing -OutFile "C:\Tools\CitrixOptimizer\Templates\JohnBillekens_3rd_Party_Components.xml"
#& "C:\Tools\CitrixOptimizer\CtxOptimizerEngine.ps1" -Template "C:\Tools\CitrixOptimizer\Templates\JohnBillekens_3rd_Party_Components.xml" -mode Execute