<#
.SYNOPSIS
Startup Script to deal with Application pre-launch at machine startup

.DESCRIPTION
Helps speed up application launch by dealing with App Pre Fetch at machine Startup.

Customise the ProcsAndWaits Hash table with your executables and timesouts

.EXAMPLE

.NOTES
    30.08.2019 - James Kindon Initial Release
    20.08.2020 - James Kindon - Added Teams function to kill additional processes that teams launches

.LINK
#>


# Enter Path and Timeout Pair
[hashtable]$ProcsAndWaits = @{
    'C:\windows\notepad.exe' = 3
    'C:\Program Files\Internet Explorer\iexplore.exe' = 3
    'C:\Program Files (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe' = 3
    'C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE' = 5
    'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE' = 5
    'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE' = 5
    'C:\Program Files\Microsoft Office\root\Office16\VISIO.EXE' = 5
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe' = 4
    'C:\Program Files\Mozilla Firefox\firefox.exe' = 4
}

function StartProcess {
    Write-Verbose "Starting Process $($process.key)" -Verbose
    $proc = Start-Process -FilePath $process.key -PassThru
    Write-Verbose "Started Process $($proc.ProcessName)" -Verbose
    Write-Verbose "Sleeping for $($process.Value) Seconds" -Verbose
    Start-Sleep -Seconds $process.Value
    Write-Verbose "Stopping Process $($proc.ProcessName) with ID $($proc.Id)" -Verbose
    Stop-Process -Id $proc.Id
}

function KillTeams {
    $TeamsProcs = Get-Process -ProcessName "Teams"
    if ($null -ne $TeamsProcs) {
        Write-Verbose "There are $($TeamsProcs.Count) Teams processes running. Attempting to terminate" -Verbose
        foreach ($Proc in $TeamsProcs) {
            Write-Verbose "Stopping Teams Process with PID: $($Proc.Id)" -Verbose
            try {
                Stop-Process -Id $Proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "$_"
            }
        }    
    }
    else {
        Write-Verbose "There are no Teams processes running" -Verbose
    }
}

Clear-Host
Write-Verbose "Setting Arguments" -Verbose
$StartDTM = (Get-Date)

$LogPS = "${env:SystemRoot}" + "\Temp\Warmup.log"

Write-Verbose "Start Logging" -Verbose
Start-Transcript $LogPS | Out-Null

$ProcsAndWaits.GetEnumerator() | ForEach-Object {
    $process = $_
    if (Test-Path $process.key) {
        StartProcess
    }
    else {
        Write-Warning "Process Path not Found for $($process.Key). Ignoring. Please Check Path"
    }
}

KillTeams

Write-Verbose "Stop logging" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript  | Out-Null
