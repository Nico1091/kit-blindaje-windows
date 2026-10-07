@echo off
setlocal EnableExtensions
title Sentinel - Reparar lo que falto

REM ===========================================================================
REM  La primera pasada del blindaje dejo 78 reglas de firewall sin cerrar por
REM  un fallo en el codigo, ya corregido:
REM
REM    - "Get-NetFirewallRule -DisplayName X -Direction Inbound" es un error de
REM      PowerShell (parametros de conjuntos distintos). Iba dentro de un catch
REM      vacio, asi que tres barridos devolvieron cero SIN avisar.
REM    - Los nombres de grupo de Windows en espanol llevan tildes y el codigo
REM      los buscaba sin ellas.
REM    - Set-SmbServerConfiguration no acepta -EnableInsecureGuestLogons, y eso
REM      hacia fallar el bloque SMB entero.
REM
REM  Esto vuelve a pasar SOLO la capa de ports, ya arreglada. Lo demas que ya
REM  se aplico bien (Defender, locks, privacy, stealth, VM, credentials)
REM  no se toca.
REM
REM  Sigue habiendo respaldo previo y reversor de 10 minutos.
REM ===========================================================================

set "SEGURIDAD=%USERPROFILE%\Security"
if not exist "%SEGURIDAD%\Harden.ps1" set "SEGURIDAD=%USERPROFILE%\Security"

if not exist "%SEGURIDAD%\Harden.ps1" (
    echo.
    echo   No encuentro la carpeta de seguridad.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto YA_ADMIN

echo.
echo   ============================================================
echo            R E P A R A R   L O   Q U E   F A L T O
echo   ============================================================
echo.
echo   Acepta el aviso de administrador.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:YA_ADMIN
mode con: cols=100 lines=50 >nul 2>&1

echo.
echo   Se van a cerrar 78 reglas de firewall que quedaron abiertas:
echo.
echo     36  reglas de descubrimiento en la red (Wi-Fi Direct, proyeccion,
echo         deteccion de redes, P2P de Windows Update, MyASUS)
echo     21  de programas que solo escuchan en tu propio equipo y no
echo         necesitan aceptar conexiones de fuera
echo      6  ELIMINADAS del todo: adb.exe (x2), lolminer.exe (x2),
echo         zephyrd.exe (x2)
echo     15  de juegos, que se quedan en red privada y salen de la publica
echo.
echo   Y se endurece SMB, que la vez pasada fallo entero.
echo.
echo   Tus juegos siguen funcionando en casa. adb y los mineros no pierden
echo   nada: esas reglas solo servian para RECIBIR conexiones, no para salir.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SEGURIDAD%\Harden.ps1" -Apply -Layers ports

echo.
echo   ------------------------------------------------------------------
echo    Comprobando como quedo...
echo   ------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$e=@(Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow); $p=@($e ^| Where-Object { $_.Profile -match 'Public' -or $_.Profile -eq 'Any' }); Write-Host ''; Write-Host ('   Reglas de entrada permitidas : ' + $e.Count) -ForegroundColor Cyan; Write-Host ('   De esas, en perfil publico    : ' + $p.Count) -ForegroundColor Cyan; $mal=@($e ^| Where-Object { $_.DisplayName -match 'adb\.exe^|lolminer^|zephyrd' }); if ($mal.Count -eq 0) { Write-Host '   adb.exe y mineros             : ELIMINADOS' -ForegroundColor Green } else { Write-Host ('   SIGUEN ABIERTAS: ' + $mal.Count) -ForegroundColor Red }"

echo.
echo   Recuerda REINICIAR: el puerto 445 seguira escuchando hasta que lo
echo   hagas, porque el driver de SMB sigue cargado en memoria aunque el
echo   servicio ya este apagado.
echo.
pause
endlocal
