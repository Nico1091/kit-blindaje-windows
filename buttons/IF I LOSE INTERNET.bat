@echo off
setlocal EnableExtensions
title RESTORE NETWORK - Sentinel

REM ===========================================================================
REM  THE PANIC BUTTON.
REM
REM  Double-click this if you lost Internet after hardening.
REM  Puts the firewall and network services back exactly as they were.
REM  Takes under a minute and touches nothing else.
REM ===========================================================================

set "SECDIR=%USERPROFILE%\Security"
if not exist "%SECDIR%\Restore.ps1" set "SECDIR=%USERPROFILE%\Security"

if not exist "%SECDIR%\Restore.ps1" (
    echo.
    echo   Cannot find the Security folder.
    echo.
    echo   Last resort: type this in PowerShell as administrator:
    echo.
    echo       netsh advfirewall reset
    echo       netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto ALREADY_ADMIN

echo.
echo   Accept the administrator prompt to restore the network.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ALREADY_ADMIN
echo.
echo   ============================================================
echo            R E S T O R I N G   T H E   N E T W O R K
echo   ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SECDIR%\Restore.ps1" -Emergency

echo.
pause
endlocal
