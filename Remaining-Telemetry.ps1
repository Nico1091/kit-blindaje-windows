<#
.SYNOPSIS
    Turns off the telemetry that was left. WITHOUT -Apply IT CHANGES NOTHING.

.DESCRIPTION
    Official switches only; it does not block domains or touch activation,
    the Store or Windows Update (so as not to risk Windows being locked).
      User     (no admin):   Office, Windows tips and suggestions,
                             PowerShell 7, .NET, VS Code and Claude Code.
      Computer (admin):      Edge policies and 5 data collection tasks.
    Left on purpose: program compatibility tasks, Office updates,
    the NVIDIA container and the Claude Code auto-updater.
    -Revert restores everything from Backups\remaining-telemetry-state.json
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
    # Windows: tips, suggestions and app launch tracking
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

# --- Backup (once) -------------------------------------------------------------
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
        Write-Bitacora "previous values backed up to $FichResp" 'OK'
    }
}

# --- Revert -------------------------------------------------------------------
if ($Revert) {
    Write-Titulo 'PUTTING TELEMETRY BACK AS IT WAS'
    if (-not (Test-Path $FichResp)) { Write-Bitacora 'there is no backup' 'WARN'; return }
    $e = Get-Content $FichResp -Raw | ConvertFrom-Json
    foreach ($r in $e.reg) { if ($null -eq $r.v) { Remove-ItemProperty -Path $r.k -Name $r.n -ErrorAction SilentlyContinue } else { Set-ValorRegistro -Ruta $r.k -Nombre $r.n -Valor $r.v | Out-Null } }
    foreach ($v in $e.env) { [Environment]::SetEnvironmentVariable($v.n, $v.v, 'User') }
    foreach ($t in $e.tareas) { if ($t.s -ne 'Disabled') { Enable-ScheduledTask -TaskPath $t.p -TaskName $t.n -ErrorAction SilentlyContinue | Out-Null } }
    # The first backup stored the text as a PowerShell object (with .value)
    foreach ($par in @(@($e.vscode, $vsc), @($e.claude, $cls))) {
        $txt = if ($par[0].value) { $par[0].value } else { $par[0] }
        if ($txt) { Set-Content $par[1] $txt -Encoding UTF8 -NoNewline }
    }
    Rename-Item $FichResp ("remaining-telemetry-reverted-$($script:Sello).json")
    Write-Bitacora 'telemetry restored' 'OK'
    return
}

Write-Titulo $(if ($Simular) { 'DRY RUN -- nothing is changed' } else { 'TURNING OFF REMAINING TELEMETRY' })

# --- User --------------------------------------------------------------------------
foreach ($r in $RegUsuario) { Set-ValorRegistro -Ruta $r[0] -Nombre $r[1] -Valor $r[2] -Simular:$Simular | Out-Null }
foreach ($n in $EnvUsuario.Keys) {
    if ($Simular) { Write-Bitacora "DRY RUN -> variable $n=$($EnvUsuario[$n])" 'DRYRUN'; continue }
    [Environment]::SetEnvironmentVariable($n, $EnvUsuario[$n], 'User'); Write-Bitacora "variable $n=$($EnvUsuario[$n])" 'CHANGE'
}
# VS Code: settings.json allows comments, so the line is inserted instead of rewriting the file
if (Test-Path $vsc) {
    $txt = Get-Content $vsc -Raw
    if ($txt -notmatch '"telemetry\.telemetryLevel"') {
        if ($Simular) { Write-Bitacora 'DRY RUN -> VS Code telemetry.telemetryLevel = off' 'DRYRUN' }
        else {
            $sep = if ($txt -match '\{\s*\}') { '' } else { ',' }
            # Only the FIRST brace: the static method takes no limit and replaced all of them
            $i = $txt.IndexOf('{')
            $txt = $txt.Substring(0, $i + 1) + "`r`n    `"telemetry.telemetryLevel`": `"off`"$sep" + $txt.Substring($i + 1)
            Set-Content $vsc $txt -Encoding UTF8 -NoNewline; Write-Bitacora 'VS Code: telemetry off' 'CHANGE'
        }
    }
} elseif (Test-Path (Split-Path $vsc)) {
    if (-not $Simular) { Set-Content $vsc "{`r`n    `"telemetry.telemetryLevel`": `"off`"`r`n}" -Encoding UTF8; Write-Bitacora 'VS Code: telemetry off (new settings.json)' 'CHANGE' }
}
# Claude Code: variables in settings.json (the auto-updater is kept)
if (Test-Path $cls) {
    $j = Get-Content $cls -Raw | ConvertFrom-Json
    if (-not $j.env) { $j | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
    foreach ($n in $EnvClaude.Keys) {
        if ($j.env.$n -eq $EnvClaude[$n]) { continue }
        if ($Simular) { Write-Bitacora "DRY RUN -> Claude Code env $n=1" 'DRYRUN'; continue }
        $j.env | Add-Member -NotePropertyName $n -NotePropertyValue $EnvClaude[$n] -Force
        Write-Bitacora "Claude Code: $n=1" 'CHANGE'
    }
    if (-not $Simular) { $j | ConvertTo-Json -Depth 20 | Set-Content $cls -Encoding UTF8 }
}

if ($UserOnly) { Write-Titulo 'DONE (user only)'; return }

# --- Computer ---------------------------------------------------------------------
foreach ($r in $RegEquipo) { Set-ValorRegistro -Ruta $r[0] -Nombre $r[1] -Valor $r[2] -Simular:$Simular | Out-Null }
foreach ($t in $Tareas) {
    $x = Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue
    if (-not $x -or $x.State -eq 'Disabled') { continue }
    if ($Simular) { Write-Bitacora "DRY RUN -> disable task $($t[0])$($t[1])" 'DRYRUN'; continue }
    try { Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction Stop | Out-Null; Write-Bitacora "task disabled: $($t[1])" 'CHANGE' }
    catch { Write-Bitacora "task $($t[1]): $($_.Exception.Message)" 'WARN' }
}
Write-Titulo 'DONE'
