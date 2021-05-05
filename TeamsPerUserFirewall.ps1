<#
.SYNOPSIS
   Creates firewall rules for Teams.
.DESCRIPTION
   Must be run with elevated permissions.
   The script will create a new inbound firewall rule for the user folder.
   Requires PowerShell 3.0.
#>

#Requires -Version 3
$User = $Env:username
$ProgPath = $env:LOCALAPPDATA + "\Microsoft\Teams\Current\Teams.exe"
if (Test-Path $progPath) {
    if (-not (Get-NetFirewallApplicationFilter -Program $progPath -ErrorAction SilentlyContinue)) {
        $ruleName = "Teams.exe for user $User"
        "UDP", "TCP" | ForEach-Object { New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Profile Domain,Private -Program $progPath -Action Allow -Protocol $_ }
        Clear-Variable ruleName
    }
}