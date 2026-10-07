@echo off
setlocal EnableExtensions
title Centinela - Como esta mi PC

REM ===========================================================================
REM  Informe de seguridad. SOLO LECTURA: esto no cambia nada, nunca.
REM  Puedes ejecutarlo cuando quieras, antes o despues de blindar.
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

echo.
echo   Acepta el aviso de administrador para ver el informe completo.
echo   (Sin el se ve casi todo, pero faltan las exclusiones de Defender.)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:YA_ADMIN
mode con: cols=110 lines=50 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SEGURIDAD%\Auditar.ps1"

echo.
pause
endlocal
