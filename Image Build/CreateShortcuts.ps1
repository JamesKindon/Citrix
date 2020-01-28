<#
.SYNOPSIS
Script to create shortcuts

.DESCRIPTION
Creates shortcuts as required 

.EXAMPLE
Set-Shortcut -Lnk "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk" -DestinationPath "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" -IconLocation $DestinationPath -IconIndex 0

Above example creates a shortcut for Microsoft Word in in the Common Start Menu 
#>


function Set-Shortcut {
    param (
        [Parameter(Mandatory=$True,ValueFromPipeline=$true)] 
        [string]$Lnk,
        [Parameter(Mandatory=$True,ValueFromPipeline=$true)]
        [string]$DestinationPath,
        [Parameter(Mandatory=$False,ValueFromPipeline=$true)]
        [string]$IconLocation,
        [Parameter(Mandatory=$False,ValueFromPipeline=$true)]
        [string]$IconIndex
    )
    $Shell = New-Object -ComObject ("WScript.Shell")
    $Shortcut = $Shell.CreateShortcut($Lnk)
    $Shortcut.TargetPath = $DestinationPath
    $Shortcut.IconLocation = $IconLocation+","+$IconIndex
    Write-Verbose "Attempting to create shortcut $($Lnk)" -Verbose
    try {
        $Shortcut.Save()
        Write-Verbose "Shortcut Created" -Verbose
    }
    catch {
        Write-Warning $Error[0].FullyQualifiedErrorId
    }
    
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
}

$ShortcutHome = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\"

Set-Shortcut -Lnk "$ShortcutHome\Word.lnk" -DestinationPath "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE" -IconLocation $DestinationPath -IconIndex 0
Set-Shortcut -Lnk "$ShortcutHome\Excel.lnk" -DestinationPath "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE" -IconLocation $DestinationPath -IconIndex 0
Set-Shortcut -Lnk "$ShortcutHome\Outlook.lnk" -DestinationPath "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE" -IconLocation $DestinationPath -IconIndex 0
Set-Shortcut -Lnk "$ShortcutHome\Microsoft Edge.lnk" -DestinationPath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -IconLocation $DestinationPath -IconIndex 0
Set-Shortcut -Lnk "$ShortcutHome\Log Off.lnk" -DestinationPath "C:\windows\System32\logoff.exe" -IconLocation "%SystemRoot%\System32\SHELL32.dll" -IconIndex 27
Set-Shortcut -Lnk "$ShortcutHome\File Explorer.lnk" -DestinationPath "%windir%\explorer.exe" -IconLocation $DestinationPath -IconIndex 0
