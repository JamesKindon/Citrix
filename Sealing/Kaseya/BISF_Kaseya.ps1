$BISFPrepLocation = "C:\Program Files (x86)\Base Image Script Framework (BIS-F)\Framework\SubCall\Preparation\Custom\"
$BISFPersLocation = "C:\Program Files (x86)\Base Image Script Framework (BIS-F)\Framework\SubCall\Personalization\Custom\"

#// KaseyaPrep.ps1
$URI = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Sealing/Kaseya/KaseyaPrep.ps1"
$ScriptName = $URI | Split-Path -Leaf

$dlparams = @{
    uri             = $URI
    UseBasicParsing = $True
    ErrorAction     = "Stop"
    OutFile         = $BISFPrepLocation + $ScriptName
}
Invoke-WebRequest @dlparams

#// KaseyaPers.ps1
$URI = "https://raw.githubusercontent.com/JamesKindon/Citrix/master/Sealing/Kaseya/KaseyaPers.ps1"
$ScriptName = $URI | Split-Path -Leaf

$dlparams = @{
    uri             = $URI
    UseBasicParsing = $True
    ErrorAction     = "Stop"
    OutFile         = $BISFPersLocation + $ScriptName
}
Invoke-WebRequest @dlparams
