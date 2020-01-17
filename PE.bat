@echo on
::**********************************************************************************************************************
::winver
::安装适用于 Windows 10 版本 1607 的 Windows ADK
::ADK https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/download-winpe--windows-pe
::https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview
::http://www.wingwy.com/archives/2012_04_1018.html
::https://tieba.baidu.com/p/4929490231?pn=2
::https://blog.csdn.net/guyan1101/article/details/86507837
::cmd /V:ON
::tree -af /Volumes/Backup/PE/WINPE_X86/{"Program Files","ProgramData","Users"} >> ~/Desktop/a.txt
::tree -af /Volumes/Backup/PE/WINPE_X86/Windows >> ~/Desktop/a.txt
::%s/.*\/Volumes\/Backup\/PE\/WINPE_X86\///g
::%s/\//\\/g
::**********************************************************************************************************************
::init
::**********************************************************************************************************************
::run as admin
::fltmc>nul||cd/d %~dp0&&mshta vbscript:CreateObject("Shell.Application").ShellExecute("%~nx0","%1","","runas",1)(window.close)
call "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
set SCRIPT_DIR=%USERPROFILE%\Desktop\WinPE
set WIN_ISO_PATH=%SCRIPT_DIR%\Windows.iso
set ROOT_DIR_PATH=%USERPROFILE%\Desktop\Win10
set LOG=%SCRIPT_DIR%\log.txt
set BOOT_LIST_PATH=%SCRIPT_DIR%\boot.txt
set PE_DIR_PATH=%ROOT_DIR_PATH%\WinPE
set PE_MOUNT_DIR_PATH=%PE_DIR_PATH%\mount
set PE_MEDIA_DIR_PATH=%PE_DIR_PATH%\media
set PE_ISO_PATH=%SCRIPT_DIR%\WinPE.iso
set WIN_WIM_MOUNT_DIR_PATH=%ROOT_DIR_PATH%\wim
set REG_FILE_TITLE=Windows Registry Editor Version 5.00
set EXPORT_REG_DIR_PATH=%ROOT_DIR_PATH%\regedit\export
set REG_SEPARATOR="    "
set PACKAGE_PATH="C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
call :strLen REG_SEPARATOR_LENGTH %REG_SEPARATOR%
call :PE_prepare
call :PE_init
:continue
call :PE_copySystemFiles
call :PE_copyUserAppFiles
call :PE_modifyRegedit
call :PE_customizeInitFile
call :PE_makeISO
::call :PE_clean
exit /b %ERRORLEVEL%
::**********************************************************************************************************************
:: auxiliary function 
::**********************************************************************************************************************
::%1 len variable to be used to return the string length
::%2 string variable name containing the string being measured for length
:strLen
    setlocal enabledelayedexpansion
    set "str=A%~2"
    set "len=0"
    for /L %%A in (12,-1,0) do (
        set /a "len|=1<<%%A"
        for %%B in (!len!) do (
            if "!str:~%%B,1!"=="" (
                set /a "len &= ~1<<%%A"
            )
        )
    )
    endlocal & IF "%1" NEQ "" SET /a %1=%len%
goto:eof

::%1 isMounted
::%2 path
:PE_hasImageMounted
    setlocal enabledelayedexpansion
    for /f "delims=" %%k in ('dism /get-mountedwiminfo ^| findstr %2') do (
        set "result=true"
        goto :end
    )
    set "result=false"
    :end
    endlocal & set %1=%result%
goto:eof

::1 index
::2 string
::3 searchString
::4 fromIndex
:indexOf
    setlocal enabledelayedexpansion
    call :strLen "strLen" %2
    call :strLen "len" %3
    set "index=%~4"
    set "string=%~2"
    :while
    set temp=!string:~%index%,%len%!
    if "!temp!" neq "%~3" (
        set /a index += 1
        if !index! geq !strLen! (
            set /a index = -1
        ) else (
            goto :while
        )
    )
    (endlocal & if "%1" neq "" set %1=%index%)
goto:eof

::**********************************************************************************************************************
::  Init
::**********************************************************************************************************************
::extract install.wim from windows.iso
:PE_prepare
    setlocal enabledelayedexpansion
    if not exist "%WIN_WIM_MOUNT_DIR_PATH%" (
        powershell "Mount-DiskImage" "%WIN_ISO_PATH%" ""
        for /f "delims=" %%i in ('powershell " ( Get-DiskImage %WIN_ISO_PATH% | Get-Volume).DriveLetter"') do (
            set isoMountedDiskId=%%i
        )
        if not exist "%WIN_WIM_MOUNT_DIR_PATH%" (
            mkdir "%WIN_WIM_MOUNT_DIR_PATH%"
        )
        if not exist "%ROOT_DIR_PATH%\install.wim" (
            dism /export-image /SourceImageFile:!isoMountedDiskId!:\sources\install.esd /SourceIndex:1 ^
            /DestinationImageFile:%ROOT_DIR_PATH%\install.wim /Compress:max /CheckIntegrity
        )
        powershell "Dismount-DiskImage  -ImagePath %WIN_ISO_PATH%"
    )
    ::check if windows wim is mouted. If not, mount it.
    call :PE_hasImageMounted isMounted "%WIN_WIM_MOUNT_DIR_PATH%"
    if "!isMounted!" neq "true" (
        dism /mount-wim /wimfile:%ROOT_DIR_PATH%\install.wim /index:1 /mountdir:%WIN_WIM_MOUNT_DIR_PATH%
    )
    endlocal
goto:eof

:PE_init
    setlocal enabledelayedexpansion
    call :PE_hasImageMounted isMounted "%PE_MOUNT_DIR_PATH%"
    if "!isMounted!" neq "true" (
        if not exist "%PE_DIR_PATH%" (
            copype amd64 %PE_DIR_PATH%
        )
        if not exist "%PE_MOUNT_DIR_PATH%" (
            mkdir "%PE_MOUNT_DIR_PATH%"
        )
        Dism /Mount-Wim /WimFile:%PE_MEDIA_DIR_PATH%\sources\boot.wim /index:1 /MountDir:%PE_MOUNT_DIR_PATH%
        call :PE_addPackages
        call :PE_removeLanguageFiles
        goto :continue
    )
    endlocal
goto:eof

:PE_addPackages
::https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference#15
    for %%p in (
        WinPE-FontSupport-ZH-CN.cab
        zh-cn\lp.cab
        WinPE-HTA.cab
        zh-cn\WinPE-HTA_zh-cn.cab
        WinPE-Scripting.cab
        zh-cn\WinPE-Scripting_zh-cn.cab
        WinPE-MDAC.cab
        zh-cn\WinPE-MDAC_zh-cn.cab
        WinPE-WMI.cab
        zh-cn\WinPE-WMI_zh-cn.cab
        WinPE-PPPoE.cab
        zh-cn\WinPE-PPPoE_zh-cn.cab
        WinPE-DOT3Svc.cab
        zh-cn\WinPE-DOT3Svc_zh-cn.cab
        WinPE-PowerShell.cab
        zh-cn\WinPE-PowerShell_zh-cn.cab
        WinPE-WiFi-Package
        zh-cn\WinPE-WiFi-Package_zh-cn.cab
    ) do dism /image:%PE_MOUNT_DIR_PATH% /Add-Package /PackagePath:%PACKAGE_PATH%\%%p
    for %%s in (/set-uilang:zh-cn
    /set-syslocale:zh-cn
    /set-userlocale:zh-cn
    /set-inputlocale:0804:00000804
    /set-timezone:"China Standard Time"
    /set-SKUIntlDefaults:zh-cn) do Dism /image:%PE_MOUNT_DIR_PATH% %%s
    ::remove extra languages
    dism /image:%PE_MOUNT_DIR_PATH% /Remove-Package /PackageName:Microsoft-Windows-WinPE-LanguagePack-Package~^
31bf3856ad364e35~amd64~en-US~10.0.14393.0
goto:eof

:PE_removeLanguageFiles
    setlocal enabledelayedexpansion
    for %%p in (%PE_MEDIA_DIR_PATH%
    %PE_MEDIA_DIR_PATH%\Boot
    %PE_MEDIA_DIR_PATH%\EFI\Microsoft\Boot
    %PE_MOUNT_DIR_PATH%\windows\system32) do (
        for %%l in (cs-cz bg-bg da-dk en-us el-gr es-es de-de es-es fi-fi fr-fr hu-hu it-it ja-jp ko-kr nb-no nl-nl
        pl-pl pt-br pt-pt ru-ru sv-se tr-tr zh-hk zh-tw en-gb es-mx et-ee fr-ca hr-hr lt-lt lv-lv ro-ro sk-sk sl-si
        sr-latn-rs uk-ua ) do (
            rd /s /q %%p\%%l
        )
    )
    for %%d in (Boot efi\microsoft\boot) do (
        for %%f in (
            cht_boot.ttf
            jpn_boot.ttf
            kor_boot.ttf
            malgunn_boot.ttf
            malgun_boot.ttf
            meiryon_boot.ttf
            meiryo_boot.ttf
            msjhn_boot.ttf
            msjh_boot.ttf
            msyhn_boot.ttf
            msyh_boot.ttf
            segmono_boot.ttf
            segoen_slboot.ttf
            segoe_slboot.ttf
        ) do del /q %PE_MEDIA_DIR_PATH%\%%d\Fonts\%%f
        rd /s /q %PE_MEDIA_DIR_PATH%\%%d\Resources
        del /q %PE_MEDIA_DIR_PATH%\%%d\memtest.exe
        del /q %PE_MEDIA_DIR_PATH%\%%d\bootfix.bin
        del /q %PE_MEDIA_DIR_PATH%\%%d\memtest.efi
        del /q %PE_MEDIA_DIR_PATH%\%%d\zh-cn\memtest.exe.mui
    )
    rd /s /q %PE_MEDIA_DIR_PATH%\zh-cn
    rd /s /q %PE_MEDIA_DIR_PATH%\EFI\Microsoft\Boot\zh-cn
    ::del /q %PE_MEDIA_DIR_PATH%\bootmgr.efi
    dism /image:%PE_MOUNT_DIR_PATH% /Set-ScratchSpace:512
    for %%p in (system32 syswow64 Boot\EFI Boot\PXE) do (
        for %%l in (cs-cz bg-bg da-dk en-us el-gr es-es de-de es-es fi-fi fr-fr
    hu-hu it-it ja-jp ko-kr nb-no nl-nl pl-pl pt-br pt-pt ru-ru sv-se tr-tr zh-hk
    zh-tw en-gb es-mx et-ee fr-ca hr-hr lt-lt lv-lv ro-ro sk-sk sl-si sr-latn-rs
    uk-ua ar-SA th-TH he-IL sr-Latn-CS ) do (
            set directory="%PE_MOUNT_DIR_PATH%\windows\%%p\%%l"
            if exist !directory! (
                for /f "delims=" %%f in ('dir /b/a-d/s "!directory!\*.mui"') do (
                     takeown /a /f %%f
                     cacls %%f /e /t /g everyone:F
                )
                takeown /a /f !directory!
                cacls  !directory! /e /t /g everyone:F
                rd /s /q !directory!
            )
        )
    )
    endlocal
goto:eof
::**********************************************************************************************************************
:: copy files
::**********************************************************************************************************************
:PE_copySystemFiles
    takeown /f  %WIN_WIM_MOUNT_DIR_PATH%\Windows /a
    icacls  %WIN_WIM_MOUNT_DIR_PATH%\Windows  /grant:r everyone:f
    takeown /f  %WIN_WIM_MOUNT_DIR_PATH%\Windows\system32 /a
    icacls  %WIN_WIM_MOUNT_DIR_PATH%\Windows\system32 /grant:r everyone:f
    takeown /f  %WIN_WIM_MOUNT_DIR_PATH%\Windows\syswow64 /a
    icacls  %WIN_WIM_MOUNT_DIR_PATH%\Windows\syswow64 /grant:r everyone:f
    takeown /f  %PE_MOUNT_DIR_PATH%\Windows /a
    icacls  %PE_MOUNT_DIR_PATH%\Windows  /grant:r everyone:f
    takeown /f  %PE_MOUNT_DIR_PATH%\Windows\system32 /a
    icacls  %PE_MOUNT_DIR_PATH%\Windows\system32 /grant:r everyone:f
    takeown /f  %PE_MOUNT_DIR_PATH%\Windows\syswow64 /a
    icacls  %PE_MOUNT_DIR_PATH%\Windows\syswow64 /grant:r everyone:f
    if exist %LOG% (
        del %LOG%
    )
    del /f "%PE_MOUNT_DIR_PATH%\windows\system32\taskmgr.exe"
    del /f "%PE_MOUNT_DIR_PATH%\Windows\system32\zh-cn\taskmgr.exe.mui"
    for /f "delims=" %%f in (%BOOT_LIST_PATH%) do (
        if not exist "%PE_MOUNT_DIR_PATH%\%%f" (
            if exist "%WIN_WIM_MOUNT_DIR_PATH%\%%f" (
                if exist "%WIN_WIM_MOUNT_DIR_PATH%\%%f\*" (
                    mkdir "%PE_MOUNT_DIR_PATH%\%%f"
                    echo  mkdir "%PE_MOUNT_DIR_PATH%\%%f"  >> %LOG%
                )else (
                    echo f|xcopy "%WIN_WIM_MOUNT_DIR_PATH%\%%f" "%PE_MOUNT_DIR_PATH%\%%f" /a /y /d /h
                    echo copy "%WIN_WIM_MOUNT_DIR_PATH%\%%f" into "%PE_MOUNT_DIR_PATH%\%%f" >> %LOG%
                )
            ) else (
                echo  "%WIN_WIM_MOUNT_DIR_PATH%\%%f does not exist" >> %LOG%
            )
        )
    )
    if not exist "%PE_MOUNT_DIR_PATH%\Users\Default\Desktop\shutdown.bat" (
        echo wpeutil shutdown > "%PE_MOUNT_DIR_PATH%\Users\Default\Desktop\shutdown.bat"
    )
    if not exist "%PE_MOUNT_DIR_PATH%\Users\Default\Desktop\reboot.bat" (
        echo wpeutil reboot  > "%PE_MOUNT_DIR_PATH%\Users\Default\Desktop\reboot.bat"
    )
goto:eof

:PE_copyUserAppFiles
    ::"Program Files (x86)\QtWeb"
    setlocal enabledelayedexpansion
    for %%p in (
        7-Zip
        Vim
        testdisk-7.0
    ) do (
        if exist "%SCRIPT_DIR%\App\%%p" if not exist "%PE_MOUNT_DIR_PATH%\Program Files\%%p" (
             echo d|xcopy "%SCRIPT_DIR%\App\%%p" "%PE_MOUNT_DIR_PATH%\Program Files\%%p" /y /d /h /e
        )
    )
    if not exist "%PE_MOUNT_DIR_PATH%\Users\Default\Desktop" (
        mkdir "%PE_MOUNT_DIR_PATH%\Users\Default\Desktop"
    )
    ::create shortcut
    ::mklink !shortcutPath! %%p PE无法识别创建出来的快捷方式
    ::"X:\Program Files (x86)\QtWeb\QtWeb.exe"
    set script="%TEMP%\%RANDOM%-%RANDOM%-%RANDOM%-%RANDOM%.vbs"
    for %%p in (
        7-Zip\7zFM.exe
        Vim\vim81\gvim.exe
        testdisk-7.0\qphotorec_win.exe
    ) do (
        set name=%%~np.lnk
        set shortcutPath="%PE_MOUNT_DIR_PATH%\Users\Default\Desktop\!name!"
        if not exist !shortcutPath! (
            echo Set wsShell = WScript.CreateObject^("WScript.Shell"^) >> %script%
            echo shortcutFile = !shortcutPath! >> %script%
            echo Set shortcut = wsShell.CreateShortcut^(shortcutFile^) >> %script%
            echo shortcut.TargetPath = "%%" + "programfiles" + ^"%%\%%p^" >> %script%
            echo shortcut.Save >> %script%
        )
    )
    if exist %script% (
       cscript /nologo %script%
        del %script%
    )
    endlocal
goto:eof

:PE_customizeInitFile
    set winpeshl=%PE_MOUNT_DIR_PATH%\Windows\System32\winpeshl.ini
    echo [LaunchApps] > %winpeshl%
    echo wpeinit.exe >> %winpeshl%
    echo x:\windows\system32\taskkill /IM WallpaperHost.exe >> %winpeshl%
    echo x:\windows\explorer.exe >> %winpeshl%
    if exist %PE_MOUNT_DIR_PATH%\Windows\system32\startnet.cmd (
        del %PE_MOUNT_DIR_PATH%\Windows\system32\startnet.cmd
    )
    if not exist %PE_MOUNT_DIR_PATH%\Users\Default\Desktop\InstallWindows.bat (
        echo f|xcopy %SCRIPT_DIR%\InstallWindows.bat %PE_MOUNT_DIR_PATH%\Users\Default\Desktop\
    )
goto:eof
::**********************************************************************************************************************
::regedit
::**********************************************************************************************************************
:PE_backupAndLoadRegedit
	set /a hour=100+%TIME:~0,2%
	set timestamp=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%%hour:~1,2%%TIME:~3,2%%TIME:~6,2%%TIME:~9,3%
	for %%k in (DEFAULT SYSTEM SOFTWARE) do (
	    if not exist %ROOT_DIR_PATH%\regedit\SOFTWARE.reg (
            echo f|xcopy %PE_MOUNT_DIR_PATH%\Windows\System32\config\%%k %ROOT_DIR_PATH%\regedit\%%k_%timestamp%
            if %%k == SOFTWARE (
                ::export PE SOFTWARE native reg
                reg load hklm\PE_%%k %PE_MOUNT_DIR_PATH%\Windows\System32\config\%%k
                reg export hklm\PE_%%k %ROOT_DIR_PATH%\regedit\%%k.reg /y
                reg unload hklm\PE_%%k
                echo a|xcopy %WIN_WIM_MOUNT_DIR_PATH%\Windows\System32\config\%%k^
                 %PE_MOUNT_DIR_PATH%\Windows\System32\config\%%k
                echo f|xcopy %WIN_WIM_MOUNT_DIR_PATH%\Windows\System32\config\%%k %ROOT_DIR_PATH%\regedit\%%k.wim
            )
	    )
	    reg load hklm\PE_%%k %PE_MOUNT_DIR_PATH%\Windows\System32\config\%%k
	)
	::1 set owner as Administrators and check replace subcontainer and owner of object 2 check use auth inherited from
	echo please 1. set owner of hklm\PE_XXXXX as administrators,check replace the owner of subcontainer and object 2. ^
use the authority inherited from this item to PE_XXXXX with inheritance from this object.Then exit regedit to continue.^
Currently,hklm\PE_SOFTWARE hklm\PE_DEFAULT is enough!
	regedit
	pause
goto:eof

:PE_replaceRegedit
    setlocal enabledelayedexpansion
    set key=%~2
    set record=%~3
    set oldValue=%~4
    set newValue=%~5
    set /a beginIndex=%REG_SEPARATOR_LENGTH%
    set isReplaced=false
    call :indexOf endIndex "!record!" !REG_SEPARATOR! !beginIndex!
    if !endIndex! geq 0 (
        set /a stringLength=!endIndex! - !beginIndex!
        for %%b in (!beginIndex!) do (
            for %%l in (!stringLength!) do (
                set subKey=!record:~%%b,%%l!
            )
        )
        set /a beginIndex=!endIndex! + !REG_SEPARATOR_LENGTH!
        call :indexOf endIndex "!record!" !REG_SEPARATOR! !beginIndex!
        echo *************************
        echo 2 key=!key! subKey=!subKey! type=!type! value=!value! beginIndex=!beginIndex! endIndex=!endIndex!
        echo record=!record!
        echo *************************
        if !endIndex! geq 0 (
            set /a stringLength=!endIndex! - !beginIndex!
            for %%b in (!beginIndex!) do (
                for %%l in (!stringLength!) do (
                    set type=!record:~%%b,%%l!
                )
            )
            set /a beginIndex=!endIndex! + !REG_SEPARATOR_LENGTH!
            call :strlen endIndex "!record!"
            set /a stringLength=!endIndex! - !beginIndex!
            for %%b in (!beginIndex!) do (
                for %%l in (!stringLength!) do (
                    set value=!record:~%%b,%%l!
                )
            )
            set oldsubKey=!subKey!
            if  defined oldValue (
                if !oldValue! == !value! (
                    set value=!newValue!
                ) else (
                    if defined newValue (
                        for %%o in (!oldValue!) do (
                            for %%n in (!newValue!) do (
                                set subKey=!subKey:%%o=%%n!
                                set value=!value:%%o=%%n!
                            )
                        )
                    )
                )
            )
            reg delete "!key!" /f /v !oldsubKey!
            reg add "!key!" /v "!subKey!" /t "!type!" /d "!value!" /f
            echo key=!key! subKey=!subKey!
            echo ************************* >> %LOG%
            echo after key=!key! subKey=!subKey! type=!type! value=!value! >> %LOG%
            echo ************************* >> %LOG%
            set isReplaced=true
        ) else (
            echo ************************* >> %LOG%
            echo skip key=!key!  record=!record! !newValue! !oldValue! >> %LOG%
            echo ************************* >> %LOG%
        )
    ) else (
        echo ************************* >> %LOG%
        echo skip key=!key!  record=!record! !newValue! !oldValue! >> %LOG%
        echo ************************* >> %LOG%
    )
    (endlocal & if "%1" neq "" set %1=%isReplaced%)
goto:eof

:PE_modifyRegeditCommonItem
    setlocal enabledelayedexpansion
    set type=%~1
    ::delete "interactive user"
    for /f %%i in ('reg query hklm\PE_%type% /f "interactive user" /s') do (
        echo %%i|findstr "^HKEY_LOCAL_MACHINE\\PE_%type%" > null
        if !errorlevel! == 0 (
            ::echo %%i [1 7] > %windir%\temp\auth.txt &&  regini -b %windir%\temp\auth.txt
            reg delete %%i /v RunAs /f
        )
    )
    ::replace C:\ and D:\ with X:\ also clear $windows.~bt\ $Windows.~BT
    for %%o in (C:\ D:\ ) do (
        if %%o == $Windows.~BT (
            set newValue=""
        ) else (
            set newValue=X:\
        )
        for /f "delims=" %%i in ('reg query hklm\PE_%type% /f %%o /s') do (
            echo %%i|findstr "^HKEY_LOCAL_MACHINE\\PE_%type%" > null
            if !errorlevel! == 0 (
                 ::echo %%i [1 7] > %windir%\temp\auth.txt && regini -b %windir%\temp\auth.txt
                 set key=%%i
            ) else (
                ::check if oldvalue exists
                echo "%%i"|findstr /i %%o  > null
                if !errorlevel! == 0 (
                    call :PE_replaceRegedit isReplaced "!key!" "%%i" "%%o"  "!newValue!"
                )
            )
        )
    )
    endlocal
goto:eof

:PE_extractAppRegistry
    setlocal enabledelayedexpansion
    for %%l in (hklm hkcu) do (
        for %%k in (
            7z.exe
            7zFM.exe
            7zG.exe
            vim.exe
            tee.exe
            xxd.exe
            diff.exe
        ) do (
            for /f "delims=" %%i in ('reg query %%l /f %%k /s') do (
                echo %%i|findstr "^HKEY_CURRENT_USER" > null
                if !errorlevel! == 0 (
                    set key=%%i
                    set key=!key:HKEY_CURRENT_USER=HKEY_LOCAL_MACHINE\PE_DEFAULT!
                ) else (
                    echo %%i|findstr "^HKEY_LOCAL_MACHINE" > null
                    if !errorlevel! == 0 (
                        set key=%%i
                        set key=!key:SOFTWARE=PE_SOFTWARE!
                    ) else (
                        call :PE_replaceRegedit isReplaced "!key!" "%%i" ""  ""
                    )
                )
            )
        )
    )
    endlocal
goto:eof

:PE_modifySoftwareRegedit
    setlocal enabledelayedexpansion
    ::dwm依赖CoreMessagingRegistrar服务，在Svchost中添加LocalServiceNoNetwork项即可启动服务
    ::        HKLM\Software\Microsoft\WindowsRuntime
    ::        HKLM\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel
    ::        HKLM\Software\Microsoft\Windows\CurrentVersion\AppModel
    ::        HKLM\Software\Microsoft\Windows\CurrentVersion\AppX
    for %%k in (
        HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Personalization
        HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons
        "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost"
    ) do (
        for /f "delims=" %%i in ('reg query %%k /s') do (
             echo %%i|findstr "^HKEY_LOCAL_MACHINE" > null
             if !errorlevel! == 0 (
                set key=%%i
                set key=!key:SOFTWARE=PE_SOFTWARE!
             ) else (
                call :PE_replaceRegedit isReplaced "!key!" "%%i" ""  ""
             )
        )
    )
    call :PE_modifyRegeditCommonItem "Software"
    ::change cmd.exe /k start cmd.exe to explorer.exe
    for /f "delims=" %%i in (
    'reg query "HKEY_LOCAL_MACHINE\PE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /f shell /v /e'
    ) do (
         echo %%i|findstr "^HKEY_LOCAL_MACHINE" > null
         if !errorlevel! == 0 (
            set key=%%i
         ) else (
            echo "%%i"|findstr "Shell"  > null
            if !errorlevel! == 0 (
                call :PE_replaceRegedit isReplaced "!key!" "%%i" "cmd.exe /k start cmd.exe"  "explorer.exe"
            )
        )
    )
    ::change %SystemRoot%\system32\CompMgmtLauncher.exe to
    ::"%SystemRoot%\system32\mmc.exe %SystemRoot%\system32\compmgmt.msc /s"
    for /f "delims=" %%i in (
    'reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{20D04FE0-3AEA-1069-A2D8-08002B30309D}\shell\Manage" /s'
    ) do (
         echo %%i|findstr "^HKEY_LOCAL_MACHINE" > null
         if !errorlevel! == 0 (
            set key=%%i
            set key=!key:SOFTWARE=PE_SOFTWARE!
         ) else (
            call :PE_replaceRegedit isReplaced "!key!" "%%i" "%SystemRoot%\system32\CompMgmtLauncher.exe"  ^
                            "^%SystemRoot^%\system32\mmc.exe ^%SystemRoot^%\system32\compmgmt.msc /s"
         )
    )

    reg add "HKEY_LOCAL_MACHINE\PE_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" ^
/v {20D04FE0-3AEA-1069-A2D8-08002B30309D} /t reg_dword /d 00000000 /f
    ::reg import %ROOT_DIR_PATH%\regedit\SOFTWARE.reg
    ::change %systemroot%\system32\config\systemprofile to X:\Users\Default
    ::^%systemroot^% failed
    for /f "delims=" %%i in (
    'reg query "HKEY_LOCAL_MACHINE\PE_SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\S-1-5-18" /f ProfileImagePath /v /e'
    ) do (
         echo %%i|findstr "^HKEY_LOCAL_MACHINE" > null
         if !errorlevel! == 0 (
            set key=%%i
         ) else (
                echo "%%i"|findstr "ProfileImagePath"  > null
                if !errorlevel! == 0 (
                    call :PE_replaceRegedit isReplaced "!key!" "%%i" "%systemroot%\system32\config\systemprofile" ^
                      "X:\Users\Default"
                )
         )
    )
    endlocal
goto:eof

:PE_modifySystemRegedit
    setlocal enabledelayedexpansion
    ::HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\UxSms
    ::HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\vga
    ::需要显卡驱动，无法载入从而大大增加启动时间
    for %%k in (
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\Themes
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\msiserver
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\Schedule
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\monitor
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\services\DXGKrnl
        HKEY_LOCAL_MACHINE\System\ControlSet001\Control\ProductOptions
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\SafeBoot\Minimal\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\SafeBoot\Network\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\Setup\AllowStart\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\Setup\AllowStart\Themes
        HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SafeBoot\Minimal\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SafeBoot\Network\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CoreMessagingRegistrar
        HKEY_LOCAL_MACHINE\SYSTEM\RNG
    ) do (
        for /f "delims=" %%i in ('reg query %%k /s') do (
             echo %%i|findstr "^HKEY_LOCAL_MACHINE" > null
             if !errorlevel! == 0 (
                set key=%%i
                set key=!key:SYSTEM=PE_SYSTEM!
             ) else (
                call :PE_replaceRegedit isReplaced "!key!" "%%i" ""  ""
             )
        )
    )
    reg add HKEY_LOCAL_MACHINE\System\ControlSet001\Control\Lsa /v LmCompatibilityLevel /t reg_dword /d 00000002 /f
    call :PE_modifyRegeditCommonItem "System"
    endlocal
goto:eof

:PE_modifyDefaultRegedit
    setlocal enabledelayedexpansion
    ::DEFAULT
    for %%k in (
        HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
        HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons
        HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Personalization
        HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM
        "HKEY_CURRENT_USER\Control Panel\Personalization"
        "HKEY_CURRENT_USER\Control Panel\Appearance"
        "HKEY_CURRENT_USER\Control Panel\Desktop"
    ) do (
        for /f "delims=" %%i in ('reg query %%k /s') do (
             echo %%i|findstr "^HKEY_CURRENT_USER" > null
             if !errorlevel! == 0 (
                set key=%%i
                set key=!key:HKEY_CURRENT_USER=HKEY_LOCAL_MACHINE\PE_DEFAULT!
             ) else (
                call :PE_replaceRegedit isReplaced "!key!" "%%i" ""  ""
             )
        )
    )
    call :PE_modifyRegeditCommonItem "Default"
    endlocal
goto:eof

:PE_modifyRegedit
    call :PE_backupAndLoadRegedit
    call :PE_modifyDefaultRegedit
    call :PE_modifySoftwareRegedit
    ::call :PE_modifySystemRegedit
    ::使用save有信息损失，直接import或写入注册表内容再unload即可
    ::reg save hklm\PE_%%k %PE_MOUNT_DIR_PATH%\Windows\System32\config\%%k /y
    for %%k in (SOFTWARE DEFAULT SYSTEM) do (
        reg unload hklm\PE_%%k
    )
goto:eof
::**********************************************************************************************************************
::finalize
::**********************************************************************************************************************
:PE_makeISO
    dism /Commit-Wim /MountDir:%PE_MOUNT_DIR_PATH%
    echo "y"|MakeWinPEMedia /ISO %PE_DIR_PATH% %PE_ISO_PATH%
goto:eof

:PE_clean
    dism /unmount-wim /MountDir:%PE_MOUNT_DIR_PATH%  /discard
    dism /unmount-wim /MountDir:%WIN_WIM_MOUNT_DIR_PATH% /discard
    dism /cleanup-wim
    dism /cleanup-mountpoints
    rd /s /q %PE_DIR_PATH%
    rd /s /q %ROOT_DIR_PATH%\regedit
goto:eof
