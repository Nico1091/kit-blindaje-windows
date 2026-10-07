@echo off
setlocal EnableExtensions
title Kit de blindaje - Instalar

REM ===========================================================================
REM  Copia el kit a %USERPROFILE%\Seguridad y los botones al Escritorio.
REM  No cambia ninguna configuracion de Windows y no pide administrador.
REM  No borra nada: si la carpeta ya existe, solo actualiza los archivos del kit.
REM ===========================================================================

set "ORIGEN=%~dp0"
set "DESTINO=%USERPROFILE%\Seguridad"
for /f "usebackq tokens=*" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "ESCRITORIO=%%D"
if not defined ESCRITORIO set "ESCRITORIO=%USERPROFILE%\Desktop"
set "BOTONES=%ESCRITORIO%\Kit de blindaje"

echo.
echo   Se va a copiar el kit a:     %DESTINO%
echo   y los botones a:             %BOTONES%
echo.
echo   No se cambia ninguna configuracion. Para seguir pulse una tecla,
echo   o cierre esta ventana para cancelar.
pause >nul

robocopy "%ORIGEN%." "%DESTINO%" /E /XD .git botones __pycache__ /XF INSTALAR-KIT.bat .gitignore /NFL /NDL /NJH /NJS /NP
if %ERRORLEVEL% GEQ 8 (
    echo.
    echo   Fallo la copia del kit. No se cambio nada mas.
    pause
    exit /b 1
)

robocopy "%ORIGEN%botones" "%BOTONES%" *.bat /NFL /NDL /NJH /NJS /NP
if %ERRORLEVEL% GEQ 8 (
    echo.
    echo   El kit se copio, pero fallo la copia de los botones.
    pause
    exit /b 1
)

echo.
echo   Listo.
echo   1. Abra la carpeta "Kit de blindaje" del Escritorio.
echo   2. Ejecute primero VER QUE BLOQUEARIA: no cambia nada.
echo   3. Lea MANUAL.md antes de aplicar cualquier cambio.
echo.
pause
