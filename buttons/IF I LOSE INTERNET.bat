@echo off
setlocal EnableExtensions
title RESTAURAR RED - Sentinel

REM ===========================================================================
REM  EL BOTON DE PANICO.
REM
REM  Doble clic aqui si despues de blindar te quedaste sin Internet.
REM  Devuelve el firewall y los servicios de red exactamente a como estaban.
REM  Tarda menos de un minuto y no toca nada mas.
REM ===========================================================================

set "SEGURIDAD=%USERPROFILE%\Security"
if not exist "%SEGURIDAD%\Restore.ps1" set "SEGURIDAD=%USERPROFILE%\Security"

if not exist "%SEGURIDAD%\Restore.ps1" (
    echo.
    echo   No encuentro la carpeta de seguridad.
    echo.
    echo   Ultimo recurso, escribe esto en PowerShell como administrador:
    echo.
    echo       netsh advfirewall reset
    echo       netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto YA_ADMIN

echo.
echo   Acepta el aviso de administrador para restaurar la red.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:YA_ADMIN
echo.
echo   ============================================================
echo               R E S T A U R A N D O   L A   R E D
echo   ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SEGURIDAD%\Restore.ps1" -Emergency

echo.
pause
endlocal
