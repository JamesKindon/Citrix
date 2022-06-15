#$StartDate = "2022-05-25"
$StartTime = "01:00:00"
$Days = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday") # Array of days to create schedules for
$DesktopGroupNames = @("") # Array of Delivery Groups to create schedules for

###--------------------------------------------------------
# Create Tags
###--------------------------------------------------------
foreach ($Day in $Days) {
    if (-not(Get-BrokerTag -Name "Reboot_$Day" -ErrorAction SilentlyContinue)) {
        Write-Verbose "Creating Tag: Reboot_$Day" -Verbose
        New-BrokerTag -Name "Reboot_$Day" -Description "Reboot Schedule"
    }
}

###--------------------------------------------------------
# Create Schedules
###--------------------------------------------------------
foreach ($DesktopGroupName in $DesktopGroupNames) {
    foreach ($Day in $Days) {
        ###--------------------------------------------------------
        # Set  Params
        ###--------------------------------------------------------
        $Day = $Day
        $DesktopGroupName = $DesktopGroupName
        $Description = "Reboot all machines tagged for $Day reboot"
        #$StartDate = $StartDate
        $StartTime = $StartTime
        $RebootDuration = 120
        $WarningMessage = "This machine will reboot in %m% minutes. Please save your work and logoff. You can continue working by launching a new session"
        $WarningTitle = "Weekly Maintenance Restart Alert!"
        $WarningDuration = 15
        $WarningRepeatInterval = 5
        $Name = ($DesktopGroupName + "_Weekly_Reboot_Schedule_$Day")
        $RestrictToTag = "Reboot_$Day"
        $Frequency = "Weekly"
    
        ###--------------------------------------------------------
        # Splat reboot params - change enabled status as required
        ###--------------------------------------------------------
        $RebootParams = @{
            Name                  = $Name
            Enabled               = $False
            RestrictToTag         = $RestrictToTag
            Day                   = $Day
            Frequency             = $Frequency
            DesktopGroupName      = $DesktopGroupName
            WarningMessage        = $WarningMessage
            WarningTitle          = $WarningTitle
            WarningDuration       = $WarningDuration
            WarningRepeatInterval = $WarningRepeatInterval
            Description           = $Description
            #StartDate             = $StartDate
            StartTime             = $StartTime
            RebootDuration        = $RebootDuration
            IgnoreMaintenanceMode = $False
            UseNaturalReboot      = $False
    
        }
        ###--------------------------------------------------------
        # Execute creation of schedule
        ###--------------------------------------------------------
        New-BrokerRebootScheduleV2 @RebootParams
    }
}