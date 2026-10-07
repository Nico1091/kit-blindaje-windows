<#
.SYNOPSIS
    Apaga la telemetria que quedaba (26/09/2026). SIN -Apply NO CAMBIA NADA.

.DESCRIPTION
    Solo interruptores oficiales; no bloquea dominios ni toca activacion,
    Tienda ni Windows Update (para no arriesgar un bloqueo de Windows).
      Usuario (sin admin): Office, consejos y sugerencias de Windows,
                           PowerShell 7, .NET, VS Code y Claude Code.
      Equipo  (con admin): politicas de Edge y 5 tareas de recogida de datos.
    Se quedan a proposito: tareas de compatibilidad de programas,
    actualizaciones de Office, contenedor de NVIDIA y el autoactualizador
    de Claude Code.
    -Revert devuelve todo desde Backups\remaining-telemetry-state.json
#>

[CmdletBinding()]
param([switch]$Apply, [switch]$Revert, [switch]$UserOnly)

. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$Simular  = -not ($Apply -or $Revert)
$FichResp = Join-Path $script:DirResp 'remaining-telemetry-state.json'

$RegUsuario = @(
    # Office
    @('HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry', 'sendtelemetry', 3),
    @('HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry', 'DisableTelemetry', 1),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common', 'qmenable', 0),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common', 'sendcustomerdata', 0),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common\feedback', 'enabled', 0),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common\feedback', 'surveyenabled', 0),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common\privacy', 'controllerconnectedservicesenabled', 2),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\osm', 'enablelogging', 0),
    @('HKCU:\Software\Policies\Microsoft\office\16.0\osm', 'enableupload', 0),
    # Windows: consejos, sugerencias y rastreo de inicio de apps
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'RotatingLockScreenOverlayEnabled', 0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338393Enabled', 0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-353694Enabled', 0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-353696Enabled', 0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338387Enabled', 0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338389Enabled', 0),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_TrackProgs', 0)
)
$EnvUsuario = [ordered]@{ 'POWERSHELL_TELEMETRY_OPTOUT' = '1'; 'DOTNET_CLI_TELEMETRY_OPTOUT' = '1' }
$EnvClaude  = [ordered]@{ 'DISABLE_TELEMETRY' = '1'; 'DISABLE_ERROR_REPORTING' = '1' }

$RegEquipo = @(
    'DiagnosticData=0', 'PersonalizationReportingEnabled=0', 'UserFeedbackAllowed=0',
    'EdgeShoppingAssistantEnabled=0', 'SpotlightExperiencesAndRecommendationsEnabled=0',
    'ShowRecommendationsEnabled=0', 'AlternateErrorPagesEnabled=0',
    'ResolveNavigationErrorsUseWebService=0', 'ConfigureDoNotTrack=1', 'EdgeFollowEnabled=0',
    'ShowMicrosoftRewards=0', 'NewTabPageContentEnabled=0', 'NewTabPageQuickLinksEnabled=0',
    'CopilotPageContext=0', 'HubsSidebarEnabled=0', 'TrackingPrevention=3'
) | ForEach-Object { $p = $_.Split('='); ,@('HKLM:\SOFTWARE\Policies\Microsoft\Edge', $p[0], [int]$p[1]) }
$Tareas = @(
    @('\Microsoft\Windows\Application Experience\', 'MareBackup'),
    @('\Microsoft\Windows\Autochk\', 'Proxy'),
    @('\Microsoft\Windows\Device Information\', 'Device'),
    @('\Microsoft\Windows\Device Information\', 'Device User'),
    @('\Microsoft\Windows\Maps\', 'MapsToastTask')
)

$necesitaAdmin = -not $UserOnly
if (-not $Simular -and $necesitaAdmin) {
    $pasar = @(); if ($Apply) { $pasar += '-Apply' }; if ($Revert) { $pasar += '-Revert' }
    if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos $pasar)) { return }
}

function Leer($k, $n) { try { (Get-ItemProperty -Path $k -Name $n -ErrorAction Stop).$n } catch { $null } }
$vsc = Join-Path $env:APPDATA 'Code\User\settings.json'
$cls = Join-Path $env:USERPROFILE '.claude\settings.json'

# --- Backup (una vez) --------------------------------------------------------
if (-not $Simular -and -not $Revert) {
    $e = if (Test-Path $FichResp) { Get-Content $FichResp -Raw | ConvertFrom-Json } else { $null }
    if (-not $e) {
        $e = [ordered]@{ reg = @(); env = @(); tareas = @(); vscode = $null; claude = $null }
        foreach ($r in $RegUsuario + $RegEquipo) { $e.reg += [ordered]@{ k = $r[0]; n = $r[1]; v = (Leer $r[0] $r[1]) } }
        foreach ($n in $EnvUsuario.Keys) { $e.env += [ordered]@{ n = $n; v = [Environment]::GetEnvironmentVariable($n, 'User') } }
        foreach ($t in $Tareas) { $x = Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue; if ($x) { $e.tareas += [ordered]@{ p = $t[0]; n = $t[1]; s = [string]$x.State } } }
        if (Test-Path $vsc) { $e.vscode = [string](Get-Content $vsc -Raw) }
        if (Test-Path $cls) { $e.claude = [string](Get-Content $cls -Raw) }
        $e | ConvertTo-Json -Depth 6 | Set-Content $FichResp -Encoding UTF8
        Write-Bitacora "valores anteriores respaldados en $FichResp" 'OK'
    }
}

# --- Revert -------------------------------------------------------------------
if ($Revert) {
    Write-Titulo 'DEVOLVIENDO LA TELEMETRIA A COMO ESTABA'
    if (-not (Test-Path $FichResp)) { Write-Bitacora 'no hay respaldo' 'WARN'; return }
    $e = Get-Content $FichResp -Raw | ConvertFrom-Json
    foreach ($r in $e.reg) { if ($null -eq $r.v) { Remove-ItemProperty -Path $r.k -Name $r.n -ErrorAction SilentlyContinue } else { Set-ValorRegistro -Ruta $r.k -Nombre $r.n -Valor $r.v | Out-Null } }
    foreach ($v in $e.env) { [Environment]::SetEnvironmentVariable($v.n, $v.v, 'User') }
    foreach ($t in $e.tareas) { if ($t.s -ne 'Disabled') { Enable-ScheduledTask -TaskPath $t.p -TaskName $t.n -ErrorAction SilentlyContinue | Out-Null } }
    # El primer respaldo guardo el texto como objeto de PowerShell (con .value)
    foreach ($par in @(@($e.vscode, $vsc), @($e.claude, $cls))) {
        $txt = if ($par[0].value) { $par[0].value } else { $par[0] }
        if ($txt) { Set-Content $par[1] $txt -Encoding UTF8 -NoNewline }
    }
    Rename-Item $FichResp ("telemetria-restante-revertido-$($script:Sello).json")
    Write-Bitacora 'telemetria devuelta' 'OK'
    return
}

Write-Titulo $(if ($Simular) { 'SIMULACRO -- no se cambia nada' } else { 'APAGANDO TELEMETRIA RESTANTE' })

# --- Usuario ------------------------------------------------------------------------
foreach ($r in $RegUsuario) { Set-ValorRegistro -Ruta $r[0] -Nombre $r[1] -Valor $r[2] -Simular:$Simular | Out-Null }
foreach ($n in $EnvUsuario.Keys) {
    if ($Simular) { Write-Bitacora "SIMULACRO -> variable $n=$($EnvUsuario[$n])" 'DRYRUN'; continue }
    [Environment]::SetEnvironmentVariable($n, $EnvUsuario[$n], 'User'); Write-Bitacora "variable $n=$($EnvUsuario[$n])" 'CHANGE'
}
# VS Code: settings.json admite comentarios, asi que se inserta la linea en vez de reescribirlo
if (Test-Path $vsc) {
    $txt = Get-Content $vsc -Raw
    if ($txt -notmatch '"telemetry\.telemetryLevel"') {
        if ($Simular) { Write-Bitacora 'SIMULACRO -> VS Code telemetry.telemetryLevel = off' 'DRYRUN' }
        else {
            $sep = if ($txt -match '\{\s*\}') { '' } else { ',' }
            # Solo la PRIMERA llave: el metodo estatico no admite limite y las cambiaba todas
            $i = $txt.IndexOf('{')
            $txt = $txt.Substring(0, $i + 1) + "`r`n    `"telemetry.telemetryLevel`": `"off`"$sep" + $txt.Substring($i + 1)
            Set-Content $vsc $txt -Encoding UTF8 -NoNewline; Write-Bitacora 'VS Code: telemetria off' 'CHANGE'
        }
    }
} elseif (Test-Path (Split-Path $vsc)) {
    if (-not $Simular) { Set-Content $vsc "{`r`n    `"telemetry.telemetryLevel`": `"off`"`r`n}" -Encoding UTF8; Write-Bitacora 'VS Code: telemetria off (settings.json nuevo)' 'CHANGE' }
}
# Claude Code: variables en settings.json (se mantiene el autoactualizador)
if (Test-Path $cls) {
    $j = Get-Content $cls -Raw | ConvertFrom-Json
    if (-not $j.env) { $j | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
    foreach ($n in $EnvClaude.Keys) {
        if ($j.env.$n -eq $EnvClaude[$n]) { continue }
        if ($Simular) { Write-Bitacora "SIMULACRO -> Claude Code env $n=1" 'DRYRUN'; continue }
        $j.env | Add-Member -NotePropertyName $n -NotePropertyValue $EnvClaude[$n] -Force
        Write-Bitacora "Claude Code: $n=1" 'CHANGE'
    }
    if (-not $Simular) { $j | ConvertTo-Json -Depth 20 | Set-Content $cls -Encoding UTF8 }
}

if ($UserOnly) { Write-Titulo 'LISTO (solo usuario)'; return }

# --- Equipo -----------------------------------------------------------------------
foreach ($r in $RegEquipo) { Set-ValorRegistro -Ruta $r[0] -Nombre $r[1] -Valor $r[2] -Simular:$Simular | Out-Null }
foreach ($t in $Tareas) {
    $x = Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue
    if (-not $x -or $x.State -eq 'Disabled') { continue }
    if ($Simular) { Write-Bitacora "SIMULACRO -> apagar tarea $($t[0])$($t[1])" 'DRYRUN'; continue }
    try { Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction Stop | Out-Null; Write-Bitacora "tarea apagada: $($t[1])" 'CHANGE' }
    catch { Write-Bitacora "tarea $($t[1]): $($_.Exception.Message)" 'WARN' }
}
Write-Titulo 'LISTO'
