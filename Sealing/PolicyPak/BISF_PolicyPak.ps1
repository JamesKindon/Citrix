$BISFPrepLocation = "C:\Program Files (x86)\Base Image Script Framework (BIS-F)\Framework\SubCall\Preparation\Custom\"
$BISFPersLocation = "C:\Program Files (x86)\Base Image Script Framework (BIS-F)\Framework\SubCall\Personalization\Custom\"

#// PolicyPakPrep.ps1
$URI = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Sealing/PolicyPak/PolicyPakPrep.ps1"
$ScriptName = $URI | Split-Path -Leaf

$dlparams = @{
    uri             = $URI
    UseBasicParsing = $True
    ErrorAction     = "Stop"
    OutFile         = $BISFPrepLocation + $ScriptName
}
Invoke-WebRequest @dlparams

#// PolicyPakPers.ps1
$URI = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Sealing/PolicyPak/PolicyPakPers.ps1"
$ScriptName = $URI | Split-Path -Leaf

$dlparams = @{
    uri             = $URI
    UseBasicParsing = $True
    ErrorAction     = "Stop"
    OutFile         = $BISFPersLocation + $ScriptName
}
Invoke-WebRequest @dlparams
