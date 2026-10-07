<#
.SYNOPSIS
    Hace todo el blindaje de una sentada, en el orden correcto.

.DESCRIPTION
    Esto es lo que se ejecuta al dar doble clic en "HARDEN MY PC.bat".
    No hay que saber nada ni escribir comandos: una sola pregunta al principio
    y otra al final para confirmar que sigue habiendo Internet.

    Orden, que importa:

      1. Comprobaciones previas. Si no hay Internet ANTES, no se empieza.
      2. Auditoria inicial, para saber de donde partimos.
      3. Simulacro completo, para ver que se va a hacer.
      4. UNA pregunta: seguimos o no.
      5. Blindaje real. Backup -> reversor de 10 min -> capas -> verificacion.
      6. Punto de restauracion diario.
      7. Auditoria final y comparativa.
      8. Boton de emergencia en el Escritorio.

    En cualquier punto donde algo salga mal, se para. No sigue adelante
    "a ver si cuela".

.EXAMPLE
    .\Run-All.ps1
#>

[CmdletBinding()]
param(
    [int]$RevertMinutes = 10,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$inicio = Get-Date

function Show-Paso {
    param([int]$N, [string]$Texto)
    Write-Host ''
    Write-Host ''
    Write-Host ('  ' + ('-' * 72)) -ForegroundColor DarkCyan
    Write-Host ("   PASO $N de 8   ::   $Texto") -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ('  ' + ('-' * 72)) -ForegroundColor DarkCyan
    Write-Host ''
}

function Get-Puntuacion {
    $f = Join-Path $script:DirBase 'ultima-puntuacion.json'
    if (Test-Path $f) { try { return Get-Content $f -Raw | ConvertFrom-Json } catch { } }
    return $null
}

function Stop-ConMensaje {
    param([string]$Texto, [string]$Consejo = '')
    Write-Host ''
    Write-Host '  ##########################################################' -ForegroundColor Red
    Write-Host "   SE PARA AQUI: $Texto" -ForegroundColor Red
    Write-Host '  ##########################################################' -ForegroundColor Red
    if ($Consejo) { Write-Host ''; Write-Host "   $Consejo" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '   Tu equipo NO se ha quedado a medias: cada paso se verifica' -ForegroundColor Gray
    Write-Host '   antes de pasar al siguiente, y si hubo cambios ya tienen su' -ForegroundColor Gray
    Write-Host '   respaldo en la carpeta Backups.' -ForegroundColor Gray
    Write-Host ''
    Read-Host '   Pulsa Intro para cerrar'
    exit 1
}

# ===========================================================================

Clear-Host
Write-Host ''
Write-Host '   ##############################################################' -ForegroundColor DarkCyan
Write-Host '   #                                                            #' -ForegroundColor DarkCyan
Write-Host '   #                  C E N T I N E L A                         #' -ForegroundColor White
Write-Host '   #             Blindaje completo del equipo                   #' -ForegroundColor Cyan
Write-Host '   #                                                            #' -ForegroundColor DarkCyan
Write-Host '   ##############################################################' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '   No tienes que hacer nada mas que leer y contestar dos veces.' -ForegroundColor Gray
Write-Host ''
Write-Host '   Lo importante que debes saber:' -ForegroundColor White
Write-Host ''
Write-Host '     - Antes de tocar la red se arma un reversor: si te quedas sin' -ForegroundColor Gray
Write-Host "       Internet, a los $RevertMinutes minutos todo vuelve solo a como estaba." -ForegroundColor Gray
Write-Host '     - Se hace respaldo completo del firewall y del registro. Si el' -ForegroundColor Gray
Write-Host '       respaldo falla, no se toca nada.' -ForegroundColor Gray
Write-Host '     - Despues de cada capa se comprueba que sigue habiendo salida.' -ForegroundColor Gray
Write-Host '       Si falla, esa capa se revierte sola.' -ForegroundColor Gray
Write-Host ''

# ---------------------------------------------------------------------------
Show-Paso 1 'COMPROBACIONES PREVIAS'
# ---------------------------------------------------------------------------

if (-not (Test-Elevado)) {
    Stop-ConMensaje 'esto no se esta ejecutando como administrador.' `
        'Cierra esta ventana y usa "HARDEN MY PC.bat", que pide el permiso solo.'
}
Write-Host '   OK    Permisos de administrador' -ForegroundColor Green

$piezas = @('Harden.ps1','Audit.ps1','Install.ps1','Restore.ps1','Migrate-Launchers.ps1','lib\Core.ps1')
$faltan = @($piezas | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) })
if ($faltan) { Stop-ConMensaje "faltan piezas: $($faltan -join ', ')" 'La carpeta Security esta incompleta.' }
Write-Host "   OK    Las $($piezas.Count) piezas del sistema estan" -ForegroundColor Green

# Sintaxis: mas vale descubrir un script roto ahora que a mitad del blindaje.
$rotos = 0
foreach ($p in $piezas) {
    $e = $null; $t = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $p), [ref]$t, [ref]$e)
    if ($e -and $e.Count -gt 0) { $rotos++; Write-Host "   FALLA $p" -ForegroundColor Red }
}
if ($rotos) { Stop-ConMensaje "$rotos scripts con errores de sintaxis." 'No se ejecuta nada con codigo roto.' }
Write-Host '   OK    Todos los scripts compilan' -ForegroundColor Green

# Internet ANTES. Si ya no hay, el blindaje no es el problema.
Write-Host ''
Write-Host '   Comprobando la conexion antes de empezar...' -ForegroundColor Gray
$red = Test-Conectividad -Silencioso
if (-not $red.Sano) {
    Stop-ConMensaje 'ya no hay Internet antes de empezar.' `
        'Arregla primero la conexion. Blindar ahora seria confundir causa y efecto.'
}
Write-Host '   OK    Hay conexion a Internet' -ForegroundColor Green

# Espacio para respaldos y punto de restauracion.
$libre = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($libre -lt 5) {
    Stop-ConMensaje "solo quedan $libre GB libres en C:." `
        'Hacen falta al menos 5 GB para el respaldo y el punto de restauracion.'
}
Write-Host "   OK    Espacio libre en C: $libre GB" -ForegroundColor Green

# Aviso si hay una VM corriendo: aislarla mientras esta en marcha la desconecta.
$vmVivas = @(Get-Process -Name 'vmware-vmx' -ErrorAction SilentlyContinue)
if ($vmVivas.Count -gt 0) {
    Write-Host ''
    Write-Host "   WARN  Tienes $($vmVivas.Count) maquina(s) virtual(es) encendida(s)." -ForegroundColor Yellow
    Write-Host '          El aislamiento les va a cortar la red en caliente.' -ForegroundColor Yellow
    Write-Host '          Conviene apagarlas antes. Si sigues, se apagaran solas' -ForegroundColor Yellow
    Write-Host '          de la red, no del sistema.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
Show-Paso 2 'COMO ESTA EL EQUIPO AHORA MISMO'
# ---------------------------------------------------------------------------

# Ojo: "| Out-Null" NO silencia Write-Host, que escribe al flujo de host y no
# al de salida. Habria vomitado la auditoria entera en pantalla. Se redirige
# todo a un fichero y aqui abajo se ensena solo el resumen.
$logAud1 = Join-Path $script:DirLog "audit-before-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Audit.ps1') *>&1 | Out-File -FilePath $logAud1 -Encoding UTF8
$antes = Get-Puntuacion
if ($antes) {
    Write-Host ''
    Write-Host ("   Puntuacion de partida: {0} / 100" -f $antes.puntuacion) -ForegroundColor $(if ($antes.puntuacion -ge 80) { 'Green' } elseif ($antes.puntuacion -ge 60) { 'Yellow' } else { 'Red' })
    Write-Host ("   {0} problemas graves, {1} avisos" -f $antes.graves, $antes.avisos) -ForegroundColor Gray
} else {
    Write-Host '   No se pudo leer la puntuacion, pero seguimos.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
Show-Paso 3 'SIMULACRO: QUE SE VA A HACER'
# ---------------------------------------------------------------------------

Write-Host '   Recorriendo las nueve capas SIN tocar nada...' -ForegroundColor Gray
Write-Host ''

$logSim = Join-Path $script:DirLog "simulacro-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Harden.ps1') -Orchestrated *>&1 | Out-File -FilePath $logSim -Encoding UTF8
$sim = Get-Content $logSim -ErrorAction SilentlyContinue

$nCambios = @($sim | Select-String -SimpleMatch '[DRYRUN]').Count
$nErrores = @($sim | Select-String -SimpleMatch '[ERROR ]').Count

Write-Host ("   Cambios que se aplicarian : {0}" -f $nCambios) -ForegroundColor Cyan
Write-Host ("   Errores en el simulacro   : {0}" -f $nErrores) -ForegroundColor $(if ($nErrores) { 'Red' } else { 'Green' })
Write-Host ("   Detalle completo en       : {0}" -f $logSim) -ForegroundColor DarkGray

if ($nErrores -gt 0) {
    Write-Host ''
    @($sim | Select-String -SimpleMatch '[ERROR ]') | Select-Object -First 5 | ForEach-Object {
        Write-Host ("     " + $_.Line.Trim()) -ForegroundColor Red
    }
    Stop-ConMensaje 'el simulacro dio errores.' 'Si falla en seco, no se aplica de verdad.'
}
if ($nCambios -eq 0) { Stop-ConMensaje 'el simulacro no propone ningun cambio.' 'Algo no cuadra; revisa la bitacora.' }

Write-Host ''
Write-Host '   Resumen de lo que va a pasar:' -ForegroundColor White
Write-Host ''
Write-Host '     1  Defender        Acceso Controlado a Carpetas, Proteccion de Red,' -ForegroundColor Gray
Write-Host '                        y las 19 reglas contra ataques' -ForegroundColor DarkGray
Write-Host '     2  Puertos         Se cierran WinRM y el servidor SMB, y se limpian' -ForegroundColor Gray
Write-Host '                        las reglas de firewall que sobran' -ForegroundColor DarkGray
Write-Host '     3  Cerrojos        UAC al maximo, sin autorun de USB, extensiones' -ForegroundColor Gray
Write-Host '                        visibles. Antes migra tus lanzadores .vbs propios' -ForegroundColor DarkGray
Write-Host '     4  Privacidad      Telemetria al minimo, ubicacion cerrada, DNS cifrado' -ForegroundColor Gray
Write-Host '     5  Sigilo          Dejas de aparecer en la red y de responder a ping' -ForegroundColor Gray
Write-Host '     6  Maquinas virt.  Tu VM de laboratorio deja de estar en tu red' -ForegroundColor Gray
Write-Host '     7  Controladores   Bloqueo de los controladores que usa el ransomware' -ForegroundColor Gray
Write-Host '     8  Credenciales    Sin contrasenas en claro en memoria, solo TLS moderno' -ForegroundColor Gray
Write-Host '     9  Ransomware      Tus carpetas protegidas y puntos de restauracion' -ForegroundColor Gray
Write-Host ''
Write-Host '   Lo que NO se toca: tu Internet, Windows Update, Defender,' -ForegroundColor Green
Write-Host '   ni tus programas propios.' -ForegroundColor Green

if ($DryRun) {
    Write-Host ''
    Write-Host '   Modo solo simulacro. No se ha cambiado nada.' -ForegroundColor Green
    Write-Host ''
    Read-Host '   Pulsa Intro para cerrar'
    exit 0
}

# ---------------------------------------------------------------------------
Show-Paso 4 'TU DECISION'
# ---------------------------------------------------------------------------

Write-Host '   Si sigues:' -ForegroundColor White
Write-Host ''
Write-Host '     - Se hace respaldo completo antes de tocar nada' -ForegroundColor Gray
Write-Host "     - Se arma el reversor de $RevertMinutes minutos" -ForegroundColor Gray
Write-Host '     - Al final te preguntare si sigues teniendo Internet.' -ForegroundColor Gray
Write-Host '       Responde SI solo si de verdad navegas bien.' -ForegroundColor Gray
Write-Host '       Si no respondes, vuelve todo solo a como estaba.' -ForegroundColor Gray
Write-Host ''
Write-Host '   Escribe SI para blindar, o cualquier otra cosa para salir.' -ForegroundColor Yellow
$resp = Read-Host '   >'
if ($resp -notmatch '^\s*(si|s|yes|y)\s*$') {
    Write-Host ''
    Write-Host '   Cancelado. No se ha tocado absolutamente nada.' -ForegroundColor Green
    Write-Host ''
    Read-Host '   Pulsa Intro para cerrar'
    exit 0
}

# ---------------------------------------------------------------------------
Show-Paso 5 'BLINDANDO'
# ---------------------------------------------------------------------------

Write-Host '   Esto tarda unos minutos. No cierres la ventana.' -ForegroundColor Yellow
Write-Host ''

& (Join-Path $PSScriptRoot 'Harden.ps1') -Apply -Orchestrated -RevertMinutes $RevertMinutes

# Lo primero, siempre: seguimos con Internet?
Write-Host ''
$redFinal = Test-Conectividad -Silencioso
if (-not $redFinal.Sano) {
    Write-Host ''
    Write-Host '   ##########################################################' -ForegroundColor Red
    Write-Host '    NO HAY CONEXION. Restaurando ahora mismo.' -ForegroundColor Red
    Write-Host '   ##########################################################' -ForegroundColor Red
    & (Join-Path $PSScriptRoot 'Restore.ps1') -Emergency -NoPrompt
    Write-Host ''
    Read-Host '   Pulsa Intro para cerrar'
    exit 1
}

# Y ahora: se aplico de verdad, o se revirtio?
#
# Ojo con la trampa: el reversor se desarma TANTO si confirmas como si se
# revierte, asi que su ausencia no prueba nada. Hay que mirar el efecto real
# sobre el sistema. Estos tres valores solo pueden estar puestos si las capas
# llegaron hasta el final.
$aplicado = 0
try {
    $mp = Get-MpPreference
    if ($mp.EnableNetworkProtection -ge 1) { $aplicado++ }
    if ($mp.EnableControlledFolderAccess -ge 1) { $aplicado++ }
    if ($mp.AttackSurfaceReductionRules_Ids -and $mp.AttackSurfaceReductionRules_Ids.Count -ge 18) { $aplicado++ }
} catch { }

if ($aplicado -eq 0) {
    Write-Host '   El blindaje no llego a aplicarse, o se revirtio entero.' -ForegroundColor Yellow
    Write-Host '   Tu equipo esta como estaba y con Internet. No se registra nada' -ForegroundColor Yellow
    Write-Host '   sobre un estado a medias.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "   Mira que paso en:  $script:Log" -ForegroundColor Gray
    Write-Host ''
    Read-Host '   Pulsa Intro para cerrar'
    exit 0
}

if ($aplicado -lt 3) {
    Write-Host "   Blindaje aplicado PARCIALMENTE ($aplicado de 3 comprobaciones)." -ForegroundColor Yellow
    Write-Host '   Suele ser la Proteccion contra Manipulaciones rechazando algun' -ForegroundColor Yellow
    Write-Host '   cambio de Defender. Seguimos, pero revisa la bitacora luego.' -ForegroundColor Yellow
} else {
    Write-Host '   OK    Blindaje aplicado y conexion intacta' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Show-Paso 6 'PUNTO DE RESTAURACION DIARIO'
# ---------------------------------------------------------------------------

$logInst = Join-Path $script:DirLog "instalar-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Install.ps1') *>&1 | Out-File -FilePath $logInst -Encoding UTF8

$tareasOK = 0
foreach ($t in @('Sentinel-Daily-Restore-Point')) {
    try { $null = Get-ScheduledTask -TaskName $t -ErrorAction Stop; $tareasOK++; Write-Host "   OK    $t" -ForegroundColor Green }
    catch { Write-Host "   FALLA $t" -ForegroundColor Red }
}
Write-Host ''
Write-Host "   $tareasOK de 1 tarea activa." -ForegroundColor $(if ($tareasOK -eq 1) { 'Green' } else { 'Yellow' })
Write-Host '   Nada corre solo en segundo plano: el estado lo miras tu cuando' -ForegroundColor Gray
Write-Host '   quieras con HOW IS MY PC.bat' -ForegroundColor Gray

# ---------------------------------------------------------------------------
Show-Paso 7 'COMO QUEDO'
# ---------------------------------------------------------------------------

$logAud2 = Join-Path $script:DirLog "auditoria-despues-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Audit.ps1') *>&1 | Out-File -FilePath $logAud2 -Encoding UTF8
$despues = Get-Puntuacion

Write-Host ''
if ($antes -and $despues) {
    $delta = $despues.puntuacion - $antes.puntuacion
    Write-Host '   ==================================================' -ForegroundColor DarkCyan
    Write-Host ("    ANTES    {0,3} / 100    {1} graves, {2} avisos" -f $antes.puntuacion, $antes.graves, $antes.avisos) -ForegroundColor Gray
    Write-Host ("    AHORA    {0,3} / 100    {1} graves, {2} avisos" -f $despues.puntuacion, $despues.graves, $despues.avisos) -ForegroundColor White
    Write-Host ("    MEJORA   {0,+4} puntos" -f $delta) -ForegroundColor $(if ($delta -gt 0) { 'Green' } elseif ($delta -eq 0) { 'Yellow' } else { 'Red' })
    Write-Host '   ==================================================' -ForegroundColor DarkCyan
    if ($despues.graves -gt 0) {
        Write-Host ''
        Write-Host '   Quedan cosas graves. Suelen ser las que necesitan reinicio.' -ForegroundColor Yellow
        Write-Host '   Reinicia y vuelve a mirar con Audit.ps1.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Show-Paso 8 'EL BOTON DE EMERGENCIA'
# ---------------------------------------------------------------------------

# Un acceso directo en el Escritorio, para que si algun dia falla la red no
# tenga que acordarse de nada.
$emergencia = @"
@echo off
title RESTAURAR RED -- Sentinel
echo.
echo   Devolviendo el firewall y los servicios de red al estado anterior...
echo.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\Restore.ps1" -Emergency
echo.
pause
"@
$rutaEmerg = Join-Path ([Environment]::GetFolderPath('Desktop')) 'IF I LOSE INTERNET.bat'
try {
    Set-Content -Path $rutaEmerg -Value $emergencia -Encoding ASCII -ErrorAction Stop
    Write-Host "   OK    Creado en tu Escritorio: 'IF I LOSE INTERNET.bat'" -ForegroundColor Green
    Write-Host '         Doble clic ahi y la red vuelve a como estaba.' -ForegroundColor Gray
} catch {
    Write-Host "   No se pudo crear el boton de emergencia: $($_.Exception.Message)" -ForegroundColor Yellow
}

$ultimoResp = ''
try { $ultimoResp = Get-Content (Join-Path $script:DirResp 'ULTIMO.txt') -Raw -ErrorAction Stop } catch { }

# ---------------------------------------------------------------------------

$minutos = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)

Write-Host ''
Write-Host ''
Write-Host '   ##############################################################' -ForegroundColor Green
Write-Host '   #                        T E R M I N A D O                   #' -ForegroundColor Green
Write-Host '   ##############################################################' -ForegroundColor Green
Write-Host ''
Write-Host "   Tardo $minutos minutos." -ForegroundColor Gray
Write-Host ''
Write-Host '   IMPORTANTE: reinicia cuando puedas.' -ForegroundColor Yellow
Write-Host '   El UAC, los controladores, la auditoria y PowerShell v2 no' -ForegroundColor Yellow
Write-Host '   terminan de aplicarse hasta que reinicies.' -ForegroundColor Yellow
Write-Host ''
Write-Host '   Donde esta cada cosa:' -ForegroundColor White
Write-Host "     Informe    $($despues.informe)" -ForegroundColor Gray
Write-Host "     Backup   $($ultimoResp.Trim())" -ForegroundColor Gray
Write-Host "     Logs   $script:Log" -ForegroundColor Gray
Write-Host ''
Write-Host '   En unos dias, cuando hayas usado el equipo con normalidad:' -ForegroundColor White
Write-Host '     Mira que habria bloqueado la proteccion de carpetas y, si no' -ForegroundColor Gray
Write-Host '     estorba a nada tuyo, pasala de vigilar a bloquear de verdad.' -ForegroundColor Gray
Write-Host '     Se hace con "WHAT WOULD IT BLOCK.bat" en Descargas.' -ForegroundColor Gray
Write-Host ''

$abrir = Read-Host '   Quieres abrir el informe ahora? (S/N)'
if ($abrir -match '^\s*(s|si|y|yes)\s*$' -and $despues.informe -and (Test-Path $despues.informe)) {
    Start-Process $despues.informe
}

Write-Host ''
$reiniciar = Read-Host '   Reiniciar el equipo ahora? (S/N)'
if ($reiniciar -match '^\s*(s|si|y|yes)\s*$') {
    Write-Host ''
    Write-Host '   Reiniciando en 20 segundos. Cierra lo que tengas abierto.' -ForegroundColor Yellow
    Write-Host '   Para cancelar, escribe en otra ventana:  shutdown /a' -ForegroundColor Gray
    & shutdown.exe /r /t 20 /c "Sentinel: reinicio para terminar de aplicar el blindaje"
} else {
    Write-Host ''
    Write-Host '   De acuerdo. Acuerdate de reiniciar mas tarde.' -ForegroundColor Gray
    Write-Host ''
    Read-Host '   Pulsa Intro para cerrar'
}
