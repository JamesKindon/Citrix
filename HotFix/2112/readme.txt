This private binary contains the fix of CVADHELP-18859 and HDX-36884， which can resolve the ghost sessions issue and the status message bar issue(CVADHELP-17138)

1. locate the 2112 VDA, backup and replace the binary from C:\Program Files\Citrix\HDX\bin\;
2. if you want to hide the status message, please configure registry "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System HideStatusMessages => 1"
3. reboot the VDA
4. enable Appliation Verifier(X64 version) for LogonUI.exe, remember to: (checked attached screenshot)
        check the option of "Locks" and "SRWLock" from "Basics" only
		check the option of "DangerousAPIs" from "Miscellaneous" only, and mark the "Verifier Stop" option for "00000100" with "Log to File, Log Stack Trace, No Break" checked. 
5. start CDFControl tracing and select "Trace Categories" = "Session Connectivity->All"
6. verify if issue still occurs, and if so, please
        stop CDF tracing and collect trace
	    collect app + system event log(.evtx format)
		collect the process dump of winlogon.exe and logonui.exe from problematic sessions, and record context data.
		collect the full memory dump if session hangs
