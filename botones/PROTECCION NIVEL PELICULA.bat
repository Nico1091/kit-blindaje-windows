@echo off
setlocal EnableExtensions
title Proteccion nivel pelicula

REM ===========================================================================
REM  Doble clic aqui y ya. Este archivo:
REM    1. Pide permisos de administrador (Windows te preguntara: acepta).
REM    2. Instala el Buscador, el DNS local y deja los errores en local.
REM
REM  Si te quedaras sin Internet, la red vuelve sola a los 10 minutos.
REM  Volver a pulsarlo actualiza el Buscador.
REM ===========================================================================

set "SEGURIDAD=%USERPROFILE%\Seguridad"
if not exist "%SEGURIDAD%\Nivel-Pelicula.ps1" set "SEGURIDAD=%USERPROFILE%\Seguridad"
if not exist "%SEGURIDAD%\Nivel-Pelicula.ps1" (
    echo.
    echo   No encuentro la carpeta de seguridad.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto YA_ADMIN
echo.
echo   Windows va a pedirte permiso de administrador. Pulsa SI.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:YA_ADMIN
mode con: cols=100 lines=50 >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%SEGURIDAD%\Nivel-Pelicula.ps1" -Aplicar
echo.
echo   Terminado. La bitacora esta en %SEGURIDAD%\Bitacora
echo.
pause
endlocal
