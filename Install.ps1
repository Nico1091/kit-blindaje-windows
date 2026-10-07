<#
.SYNOPSIS
    Registers the Sentinel's only scheduled task: the daily
    restore point.

.DESCRIPTION
    Registers a single task:

      Sentinel-Daily-Restore-Point   one restore point every day at 13:00

    It changes nothing in the system and there is no periodic monitoring:
    you check the state by hand with Audit.ps1 whenever you want.

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
Write-Host '   #           S E N T I N E L   --   I N S T A L L            #' -ForegroundColor White
Write-Host '   #############################################################' -ForegroundColor DarkCyan

if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos @($(if ($Remove) { '-Remove' })))) { return }

# --- Uninstall --------------------------------------------------------------
if ($Remove) {
    Write-Titulo 'REMOVING THE TASKS'
    foreach ($t in $tareas) {
        try { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop; Write-Bitacora "removed: $t" 'CHANGE' }
        catch { Write-Bitacora "did not exist: $t" 'INFO' }
    }
    Disable-Reversor -Silencioso
    Write-Host ''
    Write-Host '   Tasks removed. The scripts are still there if you want to run them by hand.' -ForegroundColor Green
    Write-Host ''
    return
}

# --- Tasks ------------------------------------------------------------------
Write-Titulo 'REGISTERING THE TASKS'

$exe      = if ($PSVersionTable.PSEdition -eq 'Core') { (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source } else { $null }
if (-not $exe) { $exe = 'powershell.exe' }
$opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
              -MultipleInstances IgnoreNew

# Daily restore point
try {
    $orden = "Enable-ComputerRestore -Drive 'C:\'; Checkpoint-Computer -Description 'Sentinel daily' -RestorePointType 'MODIFY_SETTINGS'"
    $accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$orden`""
    $disparo = New-ScheduledTaskTrigger -Daily -At '13:00'
    $sistema = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'Sentinel-Daily-Restore-Point' -Action $accion -Trigger $disparo `
        -Principal $sistema -Settings $opciones `
        -Description 'One restore point a day. It is the cheapest safety net there is.' `
        -Force -ErrorAction Stop | Out-Null
    Write-Bitacora 'Sentinel-Daily-Restore-Point registered: every day at 13:00' 'CHANGE'
} catch { Write-Bitacora "Sentinel-Daily-Restore-Point failed: $($_.Exception.Message)" 'ERROR' }

# --- Check ------------------------------------------------------------------
Write-Titulo 'CHECK'
foreach ($t in $tareas) {
    try {
        $o = Get-ScheduledTask -TaskName $t -ErrorAction Stop
        Write-Host ("   OK    {0,-26} {1}" -f $t, $o.State) -ForegroundColor Green
    } catch {
        Write-Host ("   FAIL  {0,-26} not registered" -f $t) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '   Done. The Sentinel does not run on its own: only the daily' -ForegroundColor Green
Write-Host '   restore point remains.' -ForegroundColor Green
Write-Host ''
Write-Host '   Commands you will use:' -ForegroundColor Cyan
Write-Host '     .\Audit.ps1                status report (changes nothing)' -ForegroundColor Gray
Write-Host '     .\Audit.ps1 -Cfa           what Controlled Folder Access would block' -ForegroundColor Gray
Write-Host '     .\Harden.ps1               dry run: shows what it would do, touches nothing' -ForegroundColor Gray
Write-Host '     .\Harden.ps1 -Apply        harden for real' -ForegroundColor Gray
Write-Host '     .\Restore.ps1 -Emergency   if you lose internet' -ForegroundColor Gray
Write-Host '     .\Install.ps1 -Remove      remove the tasks' -ForegroundColor Gray
Write-Host ''
Write-Host ''
