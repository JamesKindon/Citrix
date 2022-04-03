$BISFPrepLocation = "C:\Program Files (x86)\Base Image Script Framework (BIS-F)\Framework\SubCall\Preparation\Custom\"
$BISFPersLocation = "C:\Program Files (x86)\Base Image Script Framework (BIS-F)\Framework\SubCall\Personalization\Custom\"

#// ConnectWiseControlPrep.ps1
$URI = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Sealing/Connectwise/ConnectWiseControlPrep.ps1"
$ScriptName = $URI | Split-Path -Leaf

$dlparams = @{
    uri             = $URI
    UseBasicParsing = $True
    ErrorAction     = "Stop"
    OutFile         = $BISFPrepLocation + $ScriptName
}
Invoke-WebRequest @dlparams

#// ConnectWiseControlPers.ps1
$URI = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Sealing/Connectwise/ConnectWiseControlPers.ps1"
$ScriptName = $URI | Split-Path -Leaf

$dlparams = @{
    uri             = $URI
    UseBasicParsing = $True
    ErrorAction     = "Stop"
    OutFile         = $BISFPersLocation + $ScriptName
}
Invoke-WebRequest @dlparams