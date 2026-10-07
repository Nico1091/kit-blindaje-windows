@echo off
setlocal EnableExtensions
title Sentinel - What folder protection would block

REM ===========================================================================
REM  Anti-ransomware folder protection starts in WATCH mode:
REM  it records what it would block, but lets everything through.
REM
REM  Use the PC normally for a few days, then run this. It tells you which
REM  programs would have been blocked. If none of yours are on the list, it
REM  offers to switch it to real blocking.
REM ===========================================================================

set "SECDIR=%USERPROFILE%\Security"
if not exist "%SECDIR%\Audit.ps1" set "SECDIR=%USERPROFILE%\Security"

if not exist "%SECDIR%\Audit.ps1" (
    echo.
    echo   Cannot find the Security folder.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto ALREADY_ADMIN

powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ALREADY_ADMIN
mode con: cols=110 lines=45 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SECDIR%\Audit.ps1" -Cfa -Days 14

echo.
echo   ------------------------------------------------------------------
echo    If none of your programs appear above, you can now switch the
echo    protection from WATCH to real BLOCK.
echo   ------------------------------------------------------------------
echo.
set /p ANSWER=   Switch it to block now? (Y/N):

if /i "%ANSWER%"=="Y"   goto ENABLE
if /i "%ANSWER%"=="YES" goto ENABLE
if /i "%ANSWER%"=="S"   goto ENABLE
if /i "%ANSWER%"=="SI"  goto ENABLE
goto QUIT

:ENABLE
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction Stop; if ((Get-MpPreference).EnableControlledFolderAccess -eq 1) { Write-Host '   DONE: your folders are now protected against ransomware.' -ForegroundColor Green } else { Write-Host '   The change was rejected. Likely cause: Tamper Protection.' -ForegroundColor Yellow } } catch { Write-Host ('   Failed: ' + $_.Exception.Message) -ForegroundColor Red }"
echo.
echo   If one of your programs can no longer save, allow it with:
echo      Add-MpPreference -ControlledFolderAccessAllowedApplications "path\to\program.exe"
echo.

:QUIT
echo.
pause
endlocal
