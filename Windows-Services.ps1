<#
.SYNOPSIS
    Apaga servicios de Windows que casi nadie usa. SIN -Apply NO CAMBIA NADA.

.DESCRIPTION
    MapsBroker  mapas sin conexion           TrkWks   rastreo de enlaces en red
    PcaSvc      asistente de compatibilidad  WSearch  indexador de busqueda

    WSearch es el autentico de Windows (firma de Microsoft verificada): se apaga
    porque guarda un indice con nombres y contenido de sus archivos y porque
    llego a calentar el SSD a 79 C. Ademas se borra su base de datos del indice.
    No se arranca el componente de Windows: romperia la busqueda de Inicio y
    Configuracion. Si una actualizacion grande lo reactiva, basta repetir esto.

    -Revert devuelve los servicios a como estaban (el indice se reconstruye solo).
#>

[CmdletBinding()]
param([switch]$Apply, [switch]$Revert)

. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$Simular   = -not ($Apply -or $Revert)
$FichResp  = Join-Path $script:DirResp 'windows-services-state.json'
$Servicios = @('MapsBroker', 'TrkWks', 'PcaSvc', 'WSearch')
$Indice    = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows'

if (-not $Simular) {
    $pasar = @(); if ($Apply) { $pasar += '-Apply' }; if ($Revert) { $pasar += '-Revert' }
    if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos $pasar)) { return }
}

if ($Revert) {
    Write-Titulo 'DEVOLVIENDO LOS SERVICIOS'
    if (-not (Test-Path $FichResp)) { Write-Bitacora 'no hay respaldo' 'WARN'; return }
    foreach ($s in (Get-Content $FichResp -Raw | ConvertFrom-Json)) {
        Set-Service -Name $s.nombre -StartupType $s.inicio -ErrorAction SilentlyContinue
        if ($s.estado -eq 'Running') { Start-Service -Name $s.nombre -ErrorAction SilentlyContinue }
        Write-Bitacora "$($s.nombre) -> $($s.inicio)" 'CHANGE'
    }
    Rename-Item $FichResp ("servicios-windows-revertido-$($script:Sello).json")
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Nombre 'fAllowToGetHelp' -Valor 1 | Out-Null
    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayGroup -match 'Asistencia remota|Remote Assistance' } | Enable-NetFirewallRule
    Write-Bitacora 'Asistencia remota devuelta (la Asistencia rapida se reinstala desde la Tienda)' 'CHANGE'
    return
}

Write-Titulo $(if ($Simular) { 'SIMULACRO -- no se cambia nada' } else { 'APAGANDO SERVICIOS DE WINDOWS' })

if (-not $Simular -and -not (Test-Path $FichResp)) {
    $e = foreach ($n in $Servicios) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($s) { [ordered]@{ nombre = $n; inicio = [string]$s.StartType; estado = [string]$s.Status } }
    }
    @($e) | ConvertTo-Json | Set-Content $FichResp -Encoding UTF8
    Write-Bitacora "estado original respaldado en $FichResp" 'OK'
}

foreach ($n in $Servicios) {
    if (-not (Get-Service -Name $n -ErrorAction SilentlyContinue)) { Write-Bitacora "no existe: $n" 'INFO'; continue }
    Set-EstadoServicio -Nombre $n -Arranque Disabled -Detener -Simular:$Simular | Out-Null
}

# Base de datos del indice: el catalogo de nombres y contenido de sus archivos
if (Test-Path $Indice -ErrorAction SilentlyContinue) {
    $mb = [int]((Get-ChildItem $Indice -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
    if ($Simular) { Write-Bitacora "SIMULACRO -> borrar el indice de busqueda ($mb MB)" 'DRYRUN' }
    else {
        Start-Sleep -Seconds 3   # que SearchIndexer suelte los archivos
        Remove-Item $Indice -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $Indice -ErrorAction SilentlyContinue) { Write-Bitacora 'el indice no se pudo borrar entero (reintenta tras reiniciar)' 'WARN' }
        else { Write-Bitacora "indice de busqueda borrado ($mb MB)" 'CHANGE' }
    }
}

# Asistencia remota y Asistencia rapida: la puerta que usan las estafas de
# "soporte tecnico". Su regla del 135 solo actua en redes de dominio, pero
# se cierra entera por prevencion.
Write-Titulo 'ASISTENCIA REMOTA Y RAPIDA'
$ra = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'
Set-ValorRegistro -Ruta $ra -Nombre 'fAllowToGetHelp'   -Valor 0 -Simular:$Simular -Motivo 'nadie puede pedir entrar a ayudarte' | Out-Null
Set-ValorRegistro -Ruta $ra -Nombre 'fAllowFullControl' -Valor 0 -Simular:$Simular | Out-Null
$reglas = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayGroup -match 'Asistencia remota|Remote Assistance' -and $_.Enabled -eq 'True' })
if ($Simular) { Write-Bitacora "SIMULACRO -> apagar $($reglas.Count) reglas de firewall de Asistencia remota" 'DRYRUN' }
elseif ($reglas.Count) { $reglas | Disable-NetFirewallRule; Write-Bitacora "reglas de Asistencia remota apagadas: $($reglas.Count)" 'CHANGE' }
$qa = Get-AppxPackage -Name 'MicrosoftCorporationII.QuickAssist' -ErrorAction SilentlyContinue
if ($qa) {
    if ($Simular) { Write-Bitacora 'SIMULACRO -> quitar Asistencia rapida' 'DRYRUN' }
    else {
        try { $qa | Remove-AppxPackage -ErrorAction Stop; Write-Bitacora 'Asistencia rapida quitada (se reinstala de la Tienda si algun dia hace falta)' 'CHANGE' }
        catch { Write-Bitacora "Asistencia rapida: $($_.Exception.Message)" 'WARN' }
    }
}

Write-Titulo 'LISTO'
