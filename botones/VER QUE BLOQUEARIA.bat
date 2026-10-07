@echo off
setlocal EnableExtensions
title Centinela - Que bloquearia la proteccion de carpetas

REM ===========================================================================
REM  La proteccion anti-ransomware de tus carpetas arranca en modo VIGILAR:
REM  apunta lo que bloquearia, pero deja pasar todo.
REM
REM  Usa el equipo con normalidad unos dias y luego ejecuta esto. Te dira que
REM  programas se habrian bloqueado. Si no hay ninguno tuyo en la lista, te
REM  ofrece pasarla a bloquear de verdad.
REM ===========================================================================

set "SEGURIDAD=%USERPROFILE%\Seguridad"
if not exist "%SEGURIDAD%\Auditar.ps1" set "SEGURIDAD=%USERPROFILE%\Seguridad"

if not exist "%SEGURIDAD%\Auditar.ps1" (
    echo.
    echo   No encuentro la carpeta de seguridad.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto YA_ADMIN

powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:YA_ADMIN
mode con: cols=110 lines=45 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SEGURIDAD%\Auditar.ps1" -Cfa -Dias 14

echo.
echo   ------------------------------------------------------------------
echo    Si arriba no aparece ningun programa tuyo, ya puedes pasar la
echo    proteccion de VIGILAR a BLOQUEAR de verdad.
echo   ------------------------------------------------------------------
echo.
set /p RESPUESTA=   Pasarla a bloquear ahora? (S/N):

if /i "%RESPUESTA%"=="S"  goto ACTIVAR
if /i "%RESPUESTA%"=="SI" goto ACTIVAR
goto SALIR

:ACTIVAR
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction Stop; if ((Get-MpPreference).EnableControlledFolderAccess -eq 1) { Write-Host '   HECHO: tus carpetas quedan protegidas contra ransomware.' -ForegroundColor Green } else { Write-Host '   El cambio fue rechazado. Causa probable: Proteccion contra Manipulaciones.' -ForegroundColor Yellow } } catch { Write-Host ('   Fallo: ' + $_.Exception.Message) -ForegroundColor Red }"
echo.
echo   Si algun programa tuyo deja de poder guardar, permitelo con:
echo      Add-MpPreference -ControlledFolderAccessAllowedApplications "ruta\del\programa.exe"
echo.

:SALIR
echo.
pause
endlocal
