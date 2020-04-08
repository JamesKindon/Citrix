REM Restart WEM Services on Startup 

REM Check to see which path exists (changed in the 1903 Cloud and 1909 On-Prem release)

REM Check for Norskale Agent Host Service#Pre 1909 and Service 1903
sc query "Norskale Agent Host Service" > nul
IF ERRORLEVEL 1060 (
    echo "Service is not installed"
) else (
    net stop "Norskale Agent Host Service" /y
    taskkill /F /IM "Norskale Agent Host Service.exe"
    net start "Norskale Agent Host Service"
    net start "Netlogon"
    cd "C:\Program Files (x86)\Norskale\Norskale Agent Host\"
    AgentCacheUtility.exe -refreshcache
)

REM Check for Citrix WEM Agent Host Service 1909 and Service 1903 onwards
sc query "WemAgentSvc" > nul
IF ERRORLEVEL 1060 (
    echo "Service is not installed"
) else (
    net stop "Citrix WEM Agent Host Service" /y
    taskkill /F /IM "Citrix.Wem.Agent.Service.exe"
	
    REM Check for Upgraded Install
    IF EXIST "C:\Program Files (x86)\Norskale\Norskale Agent Host\AgentCacheUtility.exe" (
        cd "C:\Program Files (x86)\Norskale\Norskale Agent Host\"
        del "C:\Program Files (x86)\Norskale\Norskale Agent Host\Local Databases\*.*" /s /f /q
        net start "Citrix WEM Agent Host Service" 
        net start "Netlogon"
        TIMEOUT /T 10
        AgentCacheUtility.exe -refreshcache 
    )

    REM Check for Clean Install
    IF EXIST "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\AgentCacheUtility.exe" (
        cd "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\"
        del "C:\Program Files (x86)\Citrix\Workspace Environment Management Agent\Local Databases\*.*" /s /f /q
        net start "Citrix WEM Agent Host Service" 
        net start "Netlogon"
        TIMEOUT /T 10
        AgentCacheUtility.exe -refreshcache
    )
)
