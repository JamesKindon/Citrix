<#
.SYNOPSIS
Startup Script to deal with Application pre-launch at machine startup

.DESCRIPTION
Helps speed up application launch by dealing with App Pre Fetch at machine Startup.

Customise the ProcsAndWaits Hash table with your executables and timesouts

.EXAMPLE


.NOTES
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

Write-Verbose "Stop logging" -Verbose
$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalSeconds) Seconds" -Verbose
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose
Stop-Transcript  | Out-Null
