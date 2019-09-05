<#
.SYNOPSIS
Citrix WEM changes in the Cloud 1903 and On-Prem 1909 release in relation to pathings
This script caters for the changes and allows the correct service and agent cache utility to be found and executed on startup

.DESCRIPTION
Pre WEM 1903 (Cloud) and Pre WEM 1909
Service Name = "Norskale Agent Host Service"
Process Name = "Norskale Agent Host Service"
Agent Cache Utility = "C:\Program Files (x86)\Norskale\Norskale Agent Host\AgentCacheUtility.exe"

Post WEM 1903 (Cloud) and Post WEM 1909
Service Name = "Citrix WEM Agent Host Service"
Process Name = "Citrix.Wem.Agent.Service"
Agent Cache Utility = "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\AgentCacheUtility.exe"

.NOTES

Important to note, if an upgrade of an existing agent has occured, the path to the Agent Cache utility will not be changed
On a clean install, the Agent Cache utility path will reflect the new locations

.LINK
#>

# Restart WEM Services on Startup 
function RestartWEMServices {
    Write-Verbose "Stopping WEM Services" -Verbose
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Write-Verbose "Killing WEM Process" -Verbose
    Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
    Write-Verbose "Starting WEM Services" -Verbose
    Start-Service -Name $ServiceName
    Start-Service -Name "Netlogon"
    Write-Verbose "Refreshing WEM Cache" -Verbose
    Start-Process $AgentPath -ArgumentList "-refreshcache"
}

$OldService = "Norskale Agent Host Service"
$OldProcess = "Norskale Agent Host Service"
$OldPath = "C:\Program Files (x86)\Norskale\Norskale Agent Host\AgentCacheUtility.exe"

$NewService = "Citrix WEM Agent Host Service"
$NewProcess = "Citrix.Wem.Agent.Service"
$NewPath = "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\AgentCacheUtility.exe"

# Check to see which path exists (changed in the 1903 Cloud and 1909 On-Prem release)

if (Get-Service -Name $OldService -ErrorAction SilentlyContinue) {
    $ServiceName = $OldService
    $ProcessName = $OldProcess
    $AgentPath = $OldPath
    Write-Verbose "This is an old install of WEM pre cloud release 1903 and on-prem 1909" -Verbose
    RestartWEMServices
}
else {
    Write-Verbose "$($OldService) not found, looking for $($NewService)" -Verbose
}

if (Get-Service -Name $NewService -ErrorAction SilentlyContinue) {
    $ServiceName = $NewService
    $ProcessName = $NewProcess
    Write-Verbose "This is a new install of WEM post cloud release 1903 and on-prem 1909" -Verbose
    # Check for Upgraded Install
    if (Test-Path -Path $OldPath -ErrorAction SilentlyContinue) {
        $AgentPath = $OldPath
        Write-Verbose "This is an upgraded install of WEM" -Verbose
        RestartWEMServices
    }
    # Check for Clean Install
    if (Test-Path -Path $NewPath -ErrorAction SilentlyContinue) {
        $AgentPath = $NewPath
        Write-Verbose "This is a new install of WEM" -Verbose
        RestartWEMServices
    }
}
else {
    Write-Verbose "$($NewService) not found" -Verbose
    Write-Warning "Doesn't appear to be a WEM server" -Verbose
    Break
} 
