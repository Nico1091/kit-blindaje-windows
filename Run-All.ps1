<#
.SYNOPSIS
    Does the whole hardening in one go, in the right order.

.DESCRIPTION
    This is what runs when you double-click "HARDEN MY PC.bat".
    You do not need to know anything or type commands: one question at the start
    and another at the end to confirm there is still internet.

    The order matters:

      1. Pre-checks. If there is no internet BEFORE, nothing starts.
      2. Initial audit, to know where we start from.
      3. Full dry run, to see what is going to be done.
      4. ONE question: continue or not.
      5. Real hardening. Backup -> 10-minute reverter -> layers -> verification.
      6. Daily restore point.
      7. Final audit and comparison.
      8. Emergency button on the Desktop.

    Wherever something goes wrong, it stops. It does not carry on
    "hoping it works".

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
    Write-Host ("   STEP $N of 8   ::   $Texto") -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ('  ' + ('-' * 72)) -ForegroundColor DarkCyan
    Write-Host ''
}

function Get-Puntuacion {
    $f = Join-Path $script:DirBase 'latest-score.json'
    if (Test-Path $f) { try { return Get-Content $f -Raw | ConvertFrom-Json } catch { } }
    return $null
}

function Stop-ConMensaje {
    param([string]$Texto, [string]$Consejo = '')
    Write-Host ''
    Write-Host '  ##########################################################' -ForegroundColor Red
    Write-Host "   STOPPING HERE: $Texto" -ForegroundColor Red
    Write-Host '  ##########################################################' -ForegroundColor Red
    if ($Consejo) { Write-Host ''; Write-Host "   $Consejo" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '   Your computer has NOT been left half-done: every step is checked' -ForegroundColor Gray
    Write-Host '   before moving to the next, and any changes already have their' -ForegroundColor Gray
    Write-Host '   backup in the Backups folder.' -ForegroundColor Gray
    Write-Host ''
    Read-Host '   Press Enter to close'
    exit 1
}

# ===========================================================================

Clear-Host
Write-Host ''
Write-Host '   ##############################################################' -ForegroundColor DarkCyan
Write-Host '   #                                                            #' -ForegroundColor DarkCyan
Write-Host '   #                    S E N T I N E L                         #' -ForegroundColor White
Write-Host '   #              Full hardening of this computer               #' -ForegroundColor Cyan
Write-Host '   #                                                            #' -ForegroundColor DarkCyan
Write-Host '   ##############################################################' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '   You only have to read and answer twice.' -ForegroundColor Gray
Write-Host ''
Write-Host '   What you should know:' -ForegroundColor White
Write-Host ''
Write-Host '     - Before touching the network a reverter is armed: if you lose' -ForegroundColor Gray
Write-Host "       internet, after $RevertMinutes minutes everything goes back by itself." -ForegroundColor Gray
Write-Host '     - A full backup of the firewall and registry is made. If the' -ForegroundColor Gray
Write-Host '       backup fails, nothing is touched.' -ForegroundColor Gray
Write-Host '     - After each layer it checks that there is still connectivity.' -ForegroundColor Gray
Write-Host '       If not, that layer is reverted by itself.' -ForegroundColor Gray
Write-Host ''

# ---------------------------------------------------------------------------
Show-Paso 1 'PRE-CHECKS'
# ---------------------------------------------------------------------------

if (-not (Test-Elevado)) {
    Stop-ConMensaje 'this is not running as administrator.' `
        'Close this window and use "HARDEN MY PC.bat", which asks for the permission by itself.'
}
Write-Host '   OK    Administrator rights' -ForegroundColor Green

$piezas = @('Harden.ps1','Audit.ps1','Install.ps1','Restore.ps1','Migrate-Launchers.ps1','lib\Core.ps1')
$faltan = @($piezas | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) })
if ($faltan) { Stop-ConMensaje "missing pieces: $($faltan -join ', ')" 'The Security folder is incomplete.' }
Write-Host "   OK    All $($piezas.Count) pieces of the system are present" -ForegroundColor Green

# Syntax: better to find a broken script now than halfway through the hardening.
$rotos = 0
foreach ($p in $piezas) {
    $e = $null; $t = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $p), [ref]$t, [ref]$e)
    if ($e -and $e.Count -gt 0) { $rotos++; Write-Host "   FAIL  $p" -ForegroundColor Red }
}
if ($rotos) { Stop-ConMensaje "$rotos scripts with syntax errors." 'Nothing runs with broken code.' }
Write-Host '   OK    All scripts compile' -ForegroundColor Green

# Internet BEFORE. If there is none already, the hardening is not the problem.
Write-Host ''
Write-Host '   Checking the connection before starting...' -ForegroundColor Gray
$red = Test-Conectividad -Silencioso
if (-not $red.Sano) {
    Stop-ConMensaje 'there is no internet before starting.' `
        'Fix the connection first. Hardening now would confuse cause and effect.'
}
Write-Host '   OK    Internet connection available' -ForegroundColor Green

# Space for backups and the restore point.
$libre = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($libre -lt 5) {
    Stop-ConMensaje "only $libre GB free on C:." `
        'At least 5 GB are needed for the backup and the restore point.'
}
Write-Host "   OK    Free space on C: $libre GB" -ForegroundColor Green

# Warning if a VM is running: isolating it while running disconnects it.
$vmVivas = @(Get-Process -Name 'vmware-vmx' -ErrorAction SilentlyContinue)
if ($vmVivas.Count -gt 0) {
    Write-Host ''
    Write-Host "   WARN  You have $($vmVivas.Count) virtual machine(s) running." -ForegroundColor Yellow
    Write-Host '          Isolation will cut their network while they run.' -ForegroundColor Yellow
    Write-Host '          Better to shut them down first. If you continue, they lose' -ForegroundColor Yellow
    Write-Host '          the network, not the system.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
Show-Paso 2 'HOW THE COMPUTER IS RIGHT NOW'
# ---------------------------------------------------------------------------

# Careful: "| Out-Null" does NOT silence Write-Host, which writes to the host stream
# and not to the output stream. It would have dumped the whole audit on screen.
# Everything is redirected to a file and only the summary is shown below.
$logAud1 = Join-Path $script:DirLog "audit-before-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Audit.ps1') *>&1 | Out-File -FilePath $logAud1 -Encoding UTF8
$antes = Get-Puntuacion
if ($antes) {
    Write-Host ''
    Write-Host ("   Starting score: {0} / 100" -f $antes.puntuacion) -ForegroundColor $(if ($antes.puntuacion -ge 80) { 'Green' } elseif ($antes.puntuacion -ge 60) { 'Yellow' } else { 'Red' })
    Write-Host ("   {0} serious problems, {1} warnings" -f $antes.graves, $antes.avisos) -ForegroundColor Gray
} else {
    Write-Host '   Could not read the score, but we continue.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
Show-Paso 3 'DRY RUN: WHAT WILL BE DONE'
# ---------------------------------------------------------------------------

Write-Host '   Going through the nine layers WITHOUT touching anything...' -ForegroundColor Gray
Write-Host ''

$logSim = Join-Path $script:DirLog "dryrun-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Harden.ps1') -Orchestrated *>&1 | Out-File -FilePath $logSim -Encoding UTF8
$sim = Get-Content $logSim -ErrorAction SilentlyContinue

$nCambios = @($sim | Select-String -SimpleMatch '[DRYRUN]').Count
$nErrores = @($sim | Select-String -SimpleMatch '[ERROR ]').Count

Write-Host ("   Changes that would be applied : {0}" -f $nCambios) -ForegroundColor Cyan
Write-Host ("   Errors in the dry run         : {0}" -f $nErrores) -ForegroundColor $(if ($nErrores) { 'Red' } else { 'Green' })
Write-Host ("   Full detail in                : {0}" -f $logSim) -ForegroundColor DarkGray

if ($nErrores -gt 0) {
    Write-Host ''
    @($sim | Select-String -SimpleMatch '[ERROR ]') | Select-Object -First 5 | ForEach-Object {
        Write-Host ("     " + $_.Line.Trim()) -ForegroundColor Red
    }
    Stop-ConMensaje 'the dry run produced errors.' 'If it fails on a dry run, it is not applied for real.'
}
if ($nCambios -eq 0) { Stop-ConMensaje 'the dry run proposes no changes.' 'Something does not add up; check the log.' }

Write-Host ''
Write-Host '   Summary of what will happen:' -ForegroundColor White
Write-Host ''
Write-Host '     1  Defender        Controlled Folder Access, Network Protection,' -ForegroundColor Gray
Write-Host '                        and the 19 attack surface reduction rules' -ForegroundColor DarkGray
Write-Host '     2  Ports           WinRM and the SMB server are closed, and' -ForegroundColor Gray
Write-Host '                        unneeded firewall rules are cleaned up' -ForegroundColor DarkGray
Write-Host '     3  Locks           UAC at maximum, no USB autorun, visible' -ForegroundColor Gray
Write-Host '                        extensions. Your own .vbs launchers are migrated first' -ForegroundColor DarkGray
Write-Host '     4  Privacy         Minimum telemetry, location closed, encrypted DNS' -ForegroundColor Gray
Write-Host '     5  Stealth         You stop appearing on the network and answering ping' -ForegroundColor Gray
Write-Host '     6  Virtual mach.   Your lab VM is no longer on your network' -ForegroundColor Gray
Write-Host '     7  Drivers         Blocks the drivers ransomware uses' -ForegroundColor Gray
Write-Host '     8  Credentials     No clear-text passwords in memory, modern TLS only' -ForegroundColor Gray
Write-Host '     9  Ransomware      Your folders protected and restore points' -ForegroundColor Gray
Write-Host ''
Write-Host '   What is NOT touched: your internet, Windows Update, Defender,' -ForegroundColor Green
Write-Host '   or your own programs.' -ForegroundColor Green

if ($DryRun) {
    Write-Host ''
    Write-Host '   Dry run only. Nothing was changed.' -ForegroundColor Green
    Write-Host ''
    Read-Host '   Press Enter to close'
    exit 0
}

# ---------------------------------------------------------------------------
Show-Paso 4 'YOUR DECISION'
# ---------------------------------------------------------------------------

Write-Host '   If you continue:' -ForegroundColor White
Write-Host ''
Write-Host '     - A full backup is made before touching anything' -ForegroundColor Gray
Write-Host "     - The $RevertMinutes-minute reverter is armed" -ForegroundColor Gray
Write-Host '     - At the end I will ask whether you still have internet.' -ForegroundColor Gray
Write-Host '       Answer YES only if you really can browse.' -ForegroundColor Gray
Write-Host '       If you do not answer, everything goes back by itself.' -ForegroundColor Gray
Write-Host ''
Write-Host '   Type YES to harden, or anything else to exit.' -ForegroundColor Yellow
$resp = Read-Host '   >'
if ($resp -notmatch '^\s*(si|s|yes|y)\s*$') {
    Write-Host ''
    Write-Host '   Cancelled. Absolutely nothing was touched.' -ForegroundColor Green
    Write-Host ''
    Read-Host '   Press Enter to close'
    exit 0
}

# ---------------------------------------------------------------------------
Show-Paso 5 'HARDENING'
# ---------------------------------------------------------------------------

Write-Host '   This takes a few minutes. Do not close the window.' -ForegroundColor Yellow
Write-Host ''

& (Join-Path $PSScriptRoot 'Harden.ps1') -Apply -Orchestrated -RevertMinutes $RevertMinutes

# First thing, always: do we still have internet?
Write-Host ''
$redFinal = Test-Conectividad -Silencioso
if (-not $redFinal.Sano) {
    Write-Host ''
    Write-Host '   ##########################################################' -ForegroundColor Red
    Write-Host '    NO CONNECTION. Restoring right now.' -ForegroundColor Red
    Write-Host '   ##########################################################' -ForegroundColor Red
    & (Join-Path $PSScriptRoot 'Restore.ps1') -Emergency -NoPrompt
    Write-Host ''
    Read-Host '   Press Enter to close'
    exit 1
}

# And now: was it really applied, or was it reverted?
#
# Watch out for the trap: the reverter is disarmed BOTH when you confirm and when
# it reverts, so its absence proves nothing. The real effect on the system has to be
# checked. These three values can only be set if the layers got all the way through.
$aplicado = 0
try {
    $mp = Get-MpPreference
    if ($mp.EnableNetworkProtection -ge 1) { $aplicado++ }
    if ($mp.EnableControlledFolderAccess -ge 1) { $aplicado++ }
    if ($mp.AttackSurfaceReductionRules_Ids -and $mp.AttackSurfaceReductionRules_Ids.Count -ge 18) { $aplicado++ }
} catch { }

if ($aplicado -eq 0) {
    Write-Host '   The hardening was not applied, or it was fully reverted.' -ForegroundColor Yellow
    Write-Host '   Your computer is as it was, with internet. Nothing is recorded' -ForegroundColor Yellow
    Write-Host '   about a half-done state.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "   See what happened in:  $script:Log" -ForegroundColor Gray
    Write-Host ''
    Read-Host '   Press Enter to close'
    exit 0
}

if ($aplicado -lt 3) {
    Write-Host "   Hardening applied PARTIALLY ($aplicado of 3 checks)." -ForegroundColor Yellow
    Write-Host '   This is usually Tamper Protection rejecting some Defender' -ForegroundColor Yellow
    Write-Host '   change. We continue, but check the log afterwards.' -ForegroundColor Yellow
} else {
    Write-Host '   OK    Hardening applied and connection intact' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Show-Paso 6 'DAILY RESTORE POINT'
# ---------------------------------------------------------------------------

$logInst = Join-Path $script:DirLog "install-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Install.ps1') *>&1 | Out-File -FilePath $logInst -Encoding UTF8

$tareasOK = 0
foreach ($t in @('Sentinel-Daily-Restore-Point')) {
    try { $null = Get-ScheduledTask -TaskName $t -ErrorAction Stop; $tareasOK++; Write-Host "   OK    $t" -ForegroundColor Green }
    catch { Write-Host "   FAIL  $t" -ForegroundColor Red }
}
Write-Host ''
Write-Host "   $tareasOK of 1 task active." -ForegroundColor $(if ($tareasOK -eq 1) { 'Green' } else { 'Yellow' })
Write-Host '   Nothing runs on its own in the background: you check the state' -ForegroundColor Gray
Write-Host '   whenever you want with HOW IS MY PC.bat' -ForegroundColor Gray

# ---------------------------------------------------------------------------
Show-Paso 7 'HOW IT ENDED UP'
# ---------------------------------------------------------------------------

$logAud2 = Join-Path $script:DirLog "audit-after-$script:Sello.log"
& (Join-Path $PSScriptRoot 'Audit.ps1') *>&1 | Out-File -FilePath $logAud2 -Encoding UTF8
$despues = Get-Puntuacion

Write-Host ''
if ($antes -and $despues) {
    $delta = $despues.puntuacion - $antes.puntuacion
    Write-Host '   ==================================================' -ForegroundColor DarkCyan
    Write-Host ("    BEFORE   {0,3} / 100    {1} serious, {2} warnings" -f $antes.puntuacion, $antes.graves, $antes.avisos) -ForegroundColor Gray
    Write-Host ("    NOW      {0,3} / 100    {1} serious, {2} warnings" -f $despues.puntuacion, $despues.graves, $despues.avisos) -ForegroundColor White
    Write-Host ("    GAIN     {0,+4} points" -f $delta) -ForegroundColor $(if ($delta -gt 0) { 'Green' } elseif ($delta -eq 0) { 'Yellow' } else { 'Red' })
    Write-Host '   ==================================================' -ForegroundColor DarkCyan
    if ($despues.graves -gt 0) {
        Write-Host ''
        Write-Host '   Serious items remain. They are usually the ones that need a restart.' -ForegroundColor Yellow
        Write-Host '   Restart and check again with Audit.ps1.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Show-Paso 8 'THE EMERGENCY BUTTON'
# ---------------------------------------------------------------------------

# A shortcut on the Desktop, so that if the network ever fails there is
# nothing to remember.
$emergencia = @"
@echo off
title RESTORE NETWORK -- Sentinel
echo.
echo   Restoring the firewall and network services to the previous state...
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
    Write-Host "   OK    Created on your Desktop: 'IF I LOSE INTERNET.bat'" -ForegroundColor Green
    Write-Host '         Double-click it and the network goes back to how it was.' -ForegroundColor Gray
} catch {
    Write-Host "   Could not create the emergency button: $($_.Exception.Message)" -ForegroundColor Yellow
}

$ultimoResp = ''
try { $ultimoResp = Get-Content (Join-Path $script:DirResp 'LATEST.txt') -Raw -ErrorAction Stop } catch { }

# ---------------------------------------------------------------------------

$minutos = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)

Write-Host ''
Write-Host ''
Write-Host '   ##############################################################' -ForegroundColor Green
Write-Host '   #                         F I N I S H E D                    #' -ForegroundColor Green
Write-Host '   ##############################################################' -ForegroundColor Green
Write-Host ''
Write-Host "   It took $minutos minutes." -ForegroundColor Gray
Write-Host ''
Write-Host '   IMPORTANT: restart when you can.' -ForegroundColor Yellow
Write-Host '   UAC, drivers, auditing and PowerShell v2 do not finish' -ForegroundColor Yellow
Write-Host '   applying until you restart.' -ForegroundColor Yellow
Write-Host ''
Write-Host '   Where everything is:' -ForegroundColor White
Write-Host "     Report     $($despues.informe)" -ForegroundColor Gray
Write-Host "     Backup     $($ultimoResp.Trim())" -ForegroundColor Gray
Write-Host "     Log        $script:Log" -ForegroundColor Gray
Write-Host ''
Write-Host '   In a few days, once you have used the computer normally:' -ForegroundColor White
Write-Host '     Check what folder protection would have blocked and, if it does not' -ForegroundColor Gray
Write-Host '     get in the way of anything of yours, switch it from audit to real blocking.' -ForegroundColor Gray
Write-Host '     That is done with "WHAT WOULD IT BLOCK.bat".' -ForegroundColor Gray
Write-Host ''

$abrir = Read-Host '   Open the report now? (Y/N)'
if ($abrir -match '^\s*(s|si|y|yes)\s*$' -and $despues.informe -and (Test-Path $despues.informe)) {
    Start-Process $despues.informe
}

Write-Host ''
$reiniciar = Read-Host '   Restart the computer now? (Y/N)'
if ($reiniciar -match '^\s*(s|si|y|yes)\s*$') {
    Write-Host ''
    Write-Host '   Restarting in 20 seconds. Close whatever you have open.' -ForegroundColor Yellow
    Write-Host '   To cancel, type in another window:  shutdown /a' -ForegroundColor Gray
    & shutdown.exe /r /t 20 /c "Sentinel: restart to finish applying the hardening"
} else {
    Write-Host ''
    Write-Host '   All right. Remember to restart later.' -ForegroundColor Gray
    Write-Host ''
    Read-Host '   Press Enter to close'
}
