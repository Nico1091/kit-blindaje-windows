<#
.SYNOPSIS
    Registra la unica tarea programada del Sentinel: el punto de
    restauracion diario.

.DESCRIPTION
    Registra una sola tarea:

      Sentinel-Daily-Restore-Point   un punto de restauracion cada dia a las 13:00

    No cambia nada del sistema y no hay ninguna vigilancia periodica:
    el estado se mira a mano con Audit.ps1 cuando tu quieras.

.EXAMPLE
    .\Install.ps1
.EXAMPLE
    .\Install.ps1 -Remove
#>

[CmdletBinding()]
param(
    [switch]$Remove
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$tareas = @('Sentinel-Daily-Restore-Point')

Write-Host ''
Write-Host '   #############################################################' -ForegroundColor DarkCyan
Write-Host '   #         C E N T I N E L A   --   I N S T A L A R          #' -ForegroundColor White
Write-Host '   #############################################################' -ForegroundColor DarkCyan

if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos @($(if ($Remove) { '-Remove' })))) { return }

# --- Desinstalar ------------------------------------------------------------
if ($Remove) {
    Write-Titulo 'RETIRANDO LAS TAREAS'
    foreach ($t in $tareas) {
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop; Write-Bitacora "retirada: $t" 'CHANGE' }
        catch { Write-Bitacora "no existia: $t" 'INFO' }
    }
    Disable-Reversor -Silencioso
    Write-Host ''
    Write-Host '   Tareas retiradas. Los scripts siguen ahi por si los quieres a mano.' -ForegroundColor Green
    Write-Host ''
    return
}

# --- Tareas -----------------------------------------------------------------
Write-Titulo 'REGISTRANDO LAS TAREAS'

$exe      = if ($PSVersionTable.PSEdition -eq 'Core') { (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source } else { $null }
if (-not $exe) { $exe = 'powershell.exe' }
$opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
              -MultipleInstances IgnoreNew

# Punto de restauracion diario
try {
    $orden = "Enable-ComputerRestore -Drive 'C:\'; Checkpoint-Computer -Description 'Sentinel diario' -RestorePointType 'MODIFY_SETTINGS'"
    $accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$orden`""
    $disparo = New-ScheduledTaskTrigger -Daily -At '13:00'
    $sistema = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'Sentinel-Daily-Restore-Point' -Action $accion -Trigger $disparo `
        -Principal $sistema -Settings $opciones `
        -Description 'Un punto de restauracion al dia. Es la red de seguridad mas barata que existe.' `
        -Force -ErrorAction Stop | Out-Null
    Write-Bitacora 'Sentinel-Daily-Restore-Point registrada: todos los dias a las 13:00' 'CHANGE'
} catch { Write-Bitacora "Sentinel-Daily-Restore-Point fallo: $($_.Exception.Message)" 'ERROR' }

# --- Comprobacion -----------------------------------------------------------
Write-Titulo 'COMPROBACION'
foreach ($t in $tareas) {
    try {
        $o = Get-ScheduledTask -TaskName $t -ErrorAction Stop
        Write-Host ("   OK    {0,-26} {1}" -f $t, $o.State) -ForegroundColor Green
    } catch {
        Write-Host ("   FALLA {0,-26} no registrada" -f $t) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '   Listo. El Sentinel no corre solo: solo queda el punto de' -ForegroundColor Green
Write-Host '   restauracion diario.' -ForegroundColor Green
Write-Host ''
Write-Host '   Comandos que vas a usar:' -ForegroundColor Cyan
Write-Host '     .\Audit.ps1              informe de estado (no cambia nada)' -ForegroundColor Gray
Write-Host '     .\Audit.ps1 -Cfa         que bloquearia el Acceso Controlado a Carpetas' -ForegroundColor Gray
Write-Host '     .\Harden.ps1              simulacro: ensena que haria, sin tocar nada' -ForegroundColor Gray
Write-Host '     .\Harden.ps1 -Apply     blindar de verdad' -ForegroundColor Gray
Write-Host '     .\Restore.ps1 -Emergency   si te quedas sin Internet' -ForegroundColor Gray
Write-Host '     .\Install.ps1 -Remove     retirar las tareas' -ForegroundColor Gray
Write-Host ''
Write-Host ''
