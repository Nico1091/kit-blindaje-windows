@echo off
setlocal EnableExtensions
title Remove movie-grade protection

REM ===========================================================================
REM  Just double-click it. This file:
REM    1. Asks for administrator rights (Windows will prompt you: accept).
REM    2. Puts the network and settings back as they were before.
REM
REM ===========================================================================

set "SECDIR=%USERPROFILE%\Security"
if not exist "%SECDIR%\Movie-Grade.ps1" set "SECDIR=%USERPROFILE%\Security"
if not exist "%SECDIR%\Movie-Grade.ps1" (
    echo.
    echo   Cannot find the Security folder.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto ALREADY_ADMIN
echo.
echo   Windows will ask for administrator permission. Click YES.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ALREADY_ADMIN
mode con: cols=100 lines=50 >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%SECDIR%\Movie-Grade.ps1" -Revert
echo.
echo   Done. The log is in %SECDIR%\Logs
echo.
pause
endlocal
