# Restart WEM Services on Startup 

# Check to see which path exists (changed in the 1903 Cloud and 1909 On-Prem release)

if (Get-Service -Name "Norskale Agent Host Service" -ErrorAction SilentlyContinue) {
    Stop-Service -Name "Norskale Agent Host Service" -Force
    Stop-Process -Name "Norskale Agent Host Service" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "Norskale Agent Host Service"
    Start-Service -Name "Netlogon"
    Start-Process "C:\Program Files (x86)\Norskale\Norskale Agent Host\AgentCacheUtility.exe" -ArgumentList "-refreshcache"
}

if (Get-Service -Name "Citrix WEM Agent Host Service" -ErrorAction SilentlyContinue) {
    Stop-Service -Name "Citrix WEM Agent Host Service" -Force
    Stop-Process -Name "Citrix.Wem.Agent.Service" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "Citrix WEM Agent Host Service"
    Start-Service -Name "Netlogon"
    # Check for Upgraded Install
    if (Test-Path -Path "C:\Program Files (x86)\Norskale\Norskale Agent Host\AgentCacheUtility.exe" -ErrorAction SilentlyContinue) {
        Start-Process "C:\Program Files (x86)\Norskale\Norskale Agent Host\AgentCacheUtility.exe" -ArgumentList "-refreshcache"
    }
    # Check for Clean Install
    if (Test-Path -Path "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\AgentCacheUtility.exe" -ErrorAction SilentlyContinue) {
        Start-Process "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\AgentCacheUtility.exe" -ArgumentList "-refreshcache"
    }   
}
