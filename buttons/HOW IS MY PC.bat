@echo off
setlocal EnableExtensions
title Sentinel - How is my PC

REM ===========================================================================
REM  Security report. READ ONLY: this never changes anything.
REM  Run it whenever you like, before or after hardening.
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

echo.
echo   Accept the administrator prompt to see the full report.
echo   (Without it you see almost everything, except Defender exclusions.)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ALREADY_ADMIN
mode con: cols=110 lines=50 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SECDIR%\Audit.ps1"

echo.
pause
endlocal
