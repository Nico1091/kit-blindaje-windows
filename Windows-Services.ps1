<#
.SYNOPSIS
    Disables Windows services that almost nobody uses. WITHOUT -Apply IT CHANGES NOTHING.

.DESCRIPTION
    MapsBroker  offline maps                  TrkWks   distributed link tracking
    PcaSvc      program compatibility assistant  WSearch  search indexer

    WSearch is the genuine Windows one (Microsoft signature verified): it is turned
    off because it keeps an index with the names and contents of your files and
    because it once heated the SSD to 79 C. Its index database is also deleted.
    The Windows component is not removed: that would break Start and Settings
    search. If a large update turns it back on, just run this again.

    -Revert puts the services back as they were (the index rebuilds itself).
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
    Write-Titulo 'RESTORING THE SERVICES'
    if (-not (Test-Path $FichResp)) { Write-Bitacora 'there is no backup' 'WARN'; return }
    foreach ($s in (Get-Content $FichResp -Raw | ConvertFrom-Json)) {
        Set-Service -Name $s.nombre -StartupType $s.inicio -ErrorAction SilentlyContinue
        if ($s.estado -eq 'Running') { Start-Service -Name $s.nombre -ErrorAction SilentlyContinue }
        Write-Bitacora "$($s.nombre) -> $($s.inicio)" 'CHANGE'
    }
    Rename-Item $FichResp ("windows-services-reverted-$($script:Sello).json")
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Nombre 'fAllowToGetHelp' -Valor 1 | Out-Null
    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayGroup -match 'Asistencia remota|Remote Assistance' } | Enable-NetFirewallRule
    Write-Bitacora 'Remote Assistance restored (Quick Assist can be reinstalled from the Store)' 'CHANGE'
    return
}

Write-Titulo $(if ($Simular) { 'DRY RUN -- nothing is changed' } else { 'DISABLING WINDOWS SERVICES' })

if (-not $Simular -and -not (Test-Path $FichResp)) {
    $e = foreach ($n in $Servicios) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($s) { [ordered]@{ nombre = $n; inicio = [string]$s.StartType; estado = [string]$s.Status } }
    }
    @($e) | ConvertTo-Json | Set-Content $FichResp -Encoding UTF8
    Write-Bitacora "original state backed up to $FichResp" 'OK'
}

foreach ($n in $Servicios) {
    if (-not (Get-Service -Name $n -ErrorAction SilentlyContinue)) { Write-Bitacora "does not exist: $n" 'INFO'; continue }
    Set-EstadoServicio -Nombre $n -Arranque Disabled -Detener -Simular:$Simular | Out-Null
}

# Index database: the catalog of the names and contents of your files
if (Test-Path $Indice -ErrorAction SilentlyContinue) {
    $mb = [int]((Get-ChildItem $Indice -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
    if ($Simular) { Write-Bitacora "DRY RUN -> delete the search index ($mb MB)" 'DRYRUN' }
    else {
        Start-Sleep -Seconds 3   # let SearchIndexer release the files
        Remove-Item $Indice -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $Indice -ErrorAction SilentlyContinue) { Write-Bitacora 'the index could not be fully deleted (try again after a restart)' 'WARN' }
        else { Write-Bitacora "search index deleted ($mb MB)" 'CHANGE' }
    }
}

# Remote Assistance and Quick Assist: the door used by "tech support" scams.
# Its port 135 rule only applies on domain networks, but it is closed
# entirely as a precaution.
Write-Titulo 'REMOTE ASSISTANCE AND QUICK ASSIST'
$ra = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'
Set-ValorRegistro -Ruta $ra -Nombre 'fAllowToGetHelp'   -Valor 0 -Simular:$Simular -Motivo 'nobody can ask to come in and help you' | Out-Null
Set-ValorRegistro -Ruta $ra -Nombre 'fAllowFullControl' -Valor 0 -Simular:$Simular | Out-Null
$reglas = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayGroup -match 'Asistencia remota|Remote Assistance' -and $_.Enabled -eq 'True' })
if ($Simular) { Write-Bitacora "DRY RUN -> disable $($reglas.Count) Remote Assistance firewall rules" 'DRYRUN' }
elseif ($reglas.Count) { $reglas | Disable-NetFirewallRule; Write-Bitacora "Remote Assistance rules disabled: $($reglas.Count)" 'CHANGE' }
$qa = Get-AppxPackage -Name 'MicrosoftCorporationII.QuickAssist' -ErrorAction SilentlyContinue
if ($qa) {
    if ($Simular) { Write-Bitacora 'DRY RUN -> remove Quick Assist' 'DRYRUN' }
    else {
        try { $qa | Remove-AppxPackage -ErrorAction Stop; Write-Bitacora 'Quick Assist removed (it can be reinstalled from the Store if ever needed)' 'CHANGE' }
        catch { Write-Bitacora "Quick Assist: $($_.Exception.Message)" 'WARN' }
    }
}

Write-Titulo 'DONE'
