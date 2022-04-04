<#
.SYNOPSIS
    Personalises Kaseya for Provisioning
.DESCRIPTION
    https://techtalkpro.net/2017/06/02/how-to-install-the-kaseya-vsa-agent-on-a-non-persistent-machine/ 
.EXAMPLE
.NOTES
    You MUST change the 
#>

# ============================================================================
# Parameters
# ============================================================================
#region Params
param (
    [Parameter(Mandatory = $false)]
    [string]$LogPath = [System.Environment]::GetEnvironmentVariable('TEMP','Machine') + "\KaseyaSealPers.log",

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $false)]
    [string]$GroupID = ".group.fun" # keep the preceeding "." - this could be an ADMX value in BISF
)
#endregion

# ============================================================================
# Functions
# ============================================================================
#region Functions
function Write-Log {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = $LogPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoClobber
    )

    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
        
        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
        }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }

        else {
            # Nothing to see here yet.
        }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "dd-MM-yyyy HH:mm:ss" #this is in AU time

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

function RollOverlog {
    $LogFile = $LogPath
    $LogOld = Test-Path $LogFile -OlderThan (Get-Date).AddDays(-$LogRollover)
    $RolloverDate = (Get-Date -Format "dd-MM-yyyy")
    if ($LogOld) {
        Write-Log -Message "$LogFile is older than $LogRollover days, rolling over" -Level Info
        $NewName = [io.path]::GetFileNameWithoutExtension($LogFile)
        $NewName = $NewName + "_$RolloverDate.log"
        Rename-Item -Path $LogFile -NewName $NewName
        Write-Log -Message "Old logfile name is now $NewName" -Level Info
    }    
}
#endregion

# ============================================================================
# Variables
# ============================================================================
#region Variables
$RootPath = "HKLM:\SOFTWARE\WOW6432Node\Kaseya\Agent\"
$CustomerKey = (Get-ChildItem -Path $RootPath -Recurse).Name | Split-Path -Leaf # Find Customer ID
$InstallPath = (Get-ItemProperty -Path ($RootPath + $CustomerKey)).Path # Find custom install location for INI
$IniLocation = $InstallPath + "\" + "KaseyaD.ini"
$PathName = "AgentMon.exe" # Custom support service executable

$FinalID = $env:COMPUTERNAME + $GroupID
$Ini = Get-Content $IniLocation

#endregion

# ============================================================================
# Execute
# ============================================================================
#Region Execute

# Backup the INI file just in case
if (!(Test-Path -Path (($IniLocation) + "_backup"))) {
    Copy-Item -Path $IniLocation -Destination (($IniLocation) + "_backup")
}

try {
    Write-Log -Message "Attempting to alter KaseyaD ini file" -Level Info
    # Alter the INI file
    $ini = $ini -replace '^(User_Name\s+).*$' , "`$1$FinalID"
    $ini = $ini -replace '^(Password\s+).*$' , "`$1NewKaseyaAgent-"
    #$ini = $ini -replace '^(Agent_Guid\s+).*$' , "`$1TBD-"
    #$ini = $ini -replace '^(KServer_Bind_ID\s+).*$' , "`$1TBD-"
    $ini | Out-File $IniLocation -Force
    Write-Log -message  "Success" Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
    Write-Log -Message "Failed to alter ini file" -Level Warn
}


# Handle Service Start
Write-Log -Message "Attempting to enable and start services" -Level Info
$Services = Get-Service -DisplayName "Kaseya Agent*"
if ($Null -ne $Services) {
    foreach ($Service in $Services) {
        try {
            Write-Log -message "Actioning service $($Service.Name)" -Level Info
            Set-Service -Name $Service.Name -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $Service.Name -ErrorAction Stop
            Write-Log -message  "Success" Level Info
        }
        catch {
            Write-Log -Message $_ -Level Warn
            Write-Log -Message "Failed to start service $($Service.Name)" -Level Warn
        }
    }
} else {
    Write-Log -Message "No services found" -Level Warn
}

# Handle Custom Service
$CustomServiceName = (Get-WmiObject win32_service | Where-Object {$_.PathName -like "*$PathName*"}).Name
if ($null -ne $CustomServiceName) {
    try {
        Write-Log -message "Actioning service $($CustomServiceName)" -Level Info
        Set-Service -Name $CustomServiceName -StartupType Automatic -ErrorAction Stop
        Start-Service -Name $CustomServiceName -ErrorAction Stop
        Write-Log -message  "Success" Level Info
    }
    catch {
        Write-Log -Message $_ -Level Warn
        Write-Log -Message "Failed to start service $($CustomServiceName)" -Level Warn
    }
} else {
    Write-Log -Message "No services found" -Level Warn
}

#endregion