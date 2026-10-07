@echo off
setlocal EnableExtensions
title Centinela - Blindar mi PC

REM ===========================================================================
REM  Doble clic aqui y ya. Este archivo:
REM    1. Pide permisos de administrador (Windows te preguntara: acepta).
REM    2. Lanza el blindaje completo en el orden correcto.
REM
REM  No cambia nada sin preguntarte, y si te quedaras sin Internet lo devuelve
REM  todo solo a los 10 minutos.
REM ===========================================================================

REM --- Localizar la carpeta Seguridad ---------------------------------------
set "SEGURIDAD=%USERPROFILE%\Seguridad"
if not exist "%SEGURIDAD%\Todo.ps1" set "SEGURIDAD=%USERPROFILE%\Seguridad"

if not exist "%SEGURIDAD%\Todo.ps1" (
    echo.
    echo   No encuentro la carpeta de seguridad.
    echo   Buscada en: %USERPROFILE%\Seguridad
    echo.
    echo   Si la moviste, vuelve a ponerla ahi.
    echo.
    pause
    exit /b 1
)

REM --- Comprobar si ya somos administrador ----------------------------------
net session >nul 2>&1
if %errorlevel% equ 0 goto YA_ADMIN

echo.
echo   ============================================================
echo                    C E N T I N E L A
echo   ============================================================
echo.
echo   Windows va a pedirte permiso de administrador.
echo   Es normal: sin eso no se puede tocar el firewall.
echo.
echo   Pulsa SI en el aviso que aparece.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:YA_ADMIN
mode con: cols=100 lines=50 >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SEGURIDAD%\Todo.ps1"
set CODIGO=%errorlevel%

if %CODIGO% neq 0 (
    echo.
    echo   El proceso termino con codigo %CODIGO%.
    echo   Revisa la bitacora en: %SEGURIDAD%\Bitacora
    echo.
    pause
)

endlocal
exit /b %CODIGO%
