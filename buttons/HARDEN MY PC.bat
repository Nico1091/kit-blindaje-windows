@echo off
setlocal EnableExtensions
title Sentinel - Harden my PC

REM ===========================================================================
REM  Just double-click it. This file:
REM    1. Asks for administrator rights (Windows will prompt you: accept).
REM    2. Runs the full hardening in the right order.
REM
REM  It changes nothing without asking you, and if you lose Internet it puts
REM  everything back by itself after 10 minutes.
REM ===========================================================================

REM --- Locate the Security folder -------------------------------------------
set "SECDIR=%USERPROFILE%\Security"
if not exist "%SECDIR%\Run-All.ps1" set "SECDIR=%USERPROFILE%\Security"

if not exist "%SECDIR%\Run-All.ps1" (
    echo.
    echo   Cannot find the Security folder.
    echo   Looked in: %USERPROFILE%\Security
    echo.
    echo   If you moved it, put it back there.
    echo.
    pause
    exit /b 1
)

REM --- Check whether we are already administrator -----------------------------
net session >nul 2>&1
if %errorlevel% equ 0 goto ALREADY_ADMIN

echo.
echo   ============================================================
echo                    S E N T I N E L
echo   ============================================================
echo.
echo   Windows will ask for administrator permission.
echo   That is normal: the firewall cannot be changed without it.
echo.
echo   Click YES on the prompt that appears.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ALREADY_ADMIN
mode con: cols=100 lines=50 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SECDIR%\Run-All.ps1"
set EXITCODE=%errorlevel%

if %EXITCODE% neq 0 (
    echo.
    echo   The process ended with code %EXITCODE%.
    echo   Check the log in: %SECDIR%\Logs
    echo.
    pause
)

endlocal
exit /b %EXITCODE%
