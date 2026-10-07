<#
.SYNOPSIS
    Replaces .vbs launchers with equivalents that do not need
    Windows Script Host.

.DESCRIPTION
    Disabling Windows Script Host is one of the best defenses there is
    against ransomware that arrives by email: it kills double-click .vbs and
    .js files. The problem is that some computers have their own launchers
    written as .vbs, and turning it off outright would break them. This script
    knows these cases:

      Desktop\Scriptorium\Scriptorium.vbs        ->  pythonw -m scriptorium
      Desktop\Scriptorium-II\Scriptorium.vbs     ->  pythonw -m libro
      ...\Startup\News farm.vbs                  ->  the .bat it launches

    All three do exactly the same thing: start a program without the black
    console window appearing. That does not need WSH at all:

      - The desktop ones become shortcuts to pythonw.exe, which by
        definition opens no console. Same result, one less piece.
      - The startup one becomes a scheduled task at sign-in, which is also
        more reliable than the Startup folder.

    The original .vbs files are NOT deleted: they are moved to Backups\vbs-launchers\.
    If none of these launchers exist, nothing is done.

.EXAMPLE
    .\Migrate-Launchers.ps1
    Dry run: shows what it would do.

.EXAMPLE
    .\Migrate-Launchers.ps1 -Apply
#>

[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')
$Simular = -not $Apply

Write-Titulo "MIGRATION OF .VBS LAUNCHERS  ($(if ($Simular) { 'DRY RUN' } else { 'REAL' }))"

$guardados = Join-Path $script:DirResp 'vbs-launchers'
if (-not $Simular -and -not (Test-Path $guardados)) { New-Item -ItemType Directory -Path $guardados -Force | Out-Null }

$inicio = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$migrados = 0
$fallos   = 0

function Find-Pythonw {
    foreach ($c in @("$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe",
                     'C:\Python311\pythonw.exe',
                     "$env:ProgramFiles\Python311\pythonw.exe")) {
        if (Test-Path $c) { return $c }
    }
    $g = Get-Command pythonw.exe -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $null
}

function New-AccesoDirecto {
    param([string]$Destino, [string]$Programa, [string]$Argumentos, [string]$Carpeta, [string]$Descripcion)
    $w = New-Object -ComObject WScript.Shell
    $l = $w.CreateShortcut($Destino)
    $l.TargetPath       = $Programa
    $l.Arguments        = $Argumentos
    $l.WorkingDirectory = $Carpeta
    $l.Description      = $Descripcion
    $l.WindowStyle      = 7          # minimized
    $l.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($w) | Out-Null
}

# ---------------------------------------------------------------------------
# 1) The two Scriptorium launchers: shortcut to pythonw
# ---------------------------------------------------------------------------

$pythonw = Find-Pythonw
if (-not $pythonw) {
    Write-Bitacora 'pythonw.exe NOT FOUND. Nothing from Scriptorium is migrated.' 'ERROR'
    Write-Bitacora 'Without a verified replacement, a working launcher is not touched.' 'ERROR'
    $fallos++
} else {
    Write-Bitacora "pythonw found: $pythonw" 'OK'

    $casos = @(
        @{ Carpeta = "$env:USERPROFILE\Desktop\Scriptorium";    Modulo = 'scriptorium'; Nombre = 'Scriptorium' }
        @{ Carpeta = "$env:USERPROFILE\Desktop\Scriptorium-II"; Modulo = 'libro';       Nombre = 'Scriptorium II' }
    )

    foreach ($c in $casos) {
        $vbs = Join-Path $c.Carpeta 'Scriptorium.vbs'
        if (-not (Test-Path $vbs)) { Write-Bitacora "does not exist: $vbs" 'INFO'; continue }

        $lnk = Join-Path $c.Carpeta ("$($c.Nombre).lnk")
        if ($Simular) {
            Write-Bitacora "DRY RUN -> create '$($c.Nombre).lnk' -> pythonw -m $($c.Modulo)" 'DRYRUN'
            Write-Bitacora "DRY RUN -> keep the original .vbs in Backups\vbs-launchers\" 'DRYRUN'
            $migrados++
            continue
        }

        try {
            New-AccesoDirecto -Destino $lnk -Programa $pythonw -Argumentos "-m $($c.Modulo)" `
                -Carpeta $c.Carpeta -Descripcion "Opens $($c.Nombre) without a console window. Replaces the .vbs launcher."
            if (-not (Test-Path $lnk)) { throw 'the shortcut was not created' }

            Move-Item -Path $vbs -Destination (Join-Path $guardados "$($c.Nombre)-Scriptorium.vbs") -Force -ErrorAction Stop
            Write-Bitacora "$($c.Nombre): shortcut created, .vbs kept" 'CHANGE'
            $migrados++
        } catch {
            Write-Bitacora "$($c.Nombre) FAILED: $($_.Exception.Message)" 'ERROR'
            $fallos++
        }
    }
}

# ---------------------------------------------------------------------------
# 2) The news farm: scheduled task at sign-in
# ---------------------------------------------------------------------------

$vbsGranja = Join-Path $inicio 'News farm.vbs'
if (Test-Path $vbsGranja) {
    # The real target is read from the .vbs itself instead of being assumed.
    $contenido = Get-Content $vbsGranja -Raw
    $bat = $null
    if ($contenido -match '"{2,3}([A-Za-z]:\\[^"]+\.(?:bat|cmd))"{2,3}') { $bat = $Matches[1] }

    if (-not $bat -or -not (Test-Path $bat)) {
        Write-Bitacora "could not read the news farm target (or it no longer exists): $bat" 'WARN'
        Write-Bitacora 'the .vbs stays where it is. Windows Script Host will NOT be disabled.' 'WARN'
        $fallos++
    } elseif ($Simular) {
        Write-Bitacora "DRY RUN -> task 'News-Farm' at sign-in -> $bat" 'DRYRUN'
        $migrados++
    } else {
        try {
            $accion  = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$bat`"" -WorkingDirectory (Split-Path $bat -Parent)
            $disparo = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
            $disparo.Delay = 'PT1M'
            $ppal    = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
            $opts    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                         -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

            Register-ScheduledTask -TaskName 'News-Farm' -Action $accion -Trigger $disparo `
                -Principal $ppal -Settings $opts `
                -Description 'Starts the news farm at sign-in. Replaces the .vbs launcher so Windows Script Host can be disabled.' `
                -Force -ErrorAction Stop | Out-Null

            Move-Item -Path $vbsGranja -Destination (Join-Path $guardados 'News farm.vbs') -Force -ErrorAction Stop
            Write-Bitacora "news farm: it is now the 'News-Farm' task" 'CHANGE'
            $migrados++
        } catch {
            Write-Bitacora "news farm FAILED: $($_.Exception.Message)" 'ERROR'
            $fallos++
        }
    }
} else {
    Write-Bitacora 'no news farm .vbs in the Startup folder' 'INFO'
}

# ---------------------------------------------------------------------------
# Verdict: WSH can only be turned off if NO .vbs is still in use.
# ---------------------------------------------------------------------------

Write-Host ''
$pendientes = @()
foreach ($r in @("$env:USERPROFILE\Desktop", $inicio)) {
    if (Test-Path $r) {
        $pendientes += Get-ChildItem $r -Include '*.vbs','*.wsf' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                       Where-Object { $_.DirectoryName -notlike "*\Backups\*" }
    }
}

if ($fallos -gt 0) {
    Write-Bitacora "$fallos migrations failed. Do NOT disable Windows Script Host yet." 'ERROR'
} elseif ($pendientes.Count -gt 0 -and -not $Simular) {
    Write-Bitacora "$($pendientes.Count) .vbs files remain that could be in use:" 'WARN'
    $pendientes | ForEach-Object { Write-Bitacora "   $($_.FullName)" 'WARN' }
    Write-Bitacora 'check them before disabling Windows Script Host.' 'WARN'
} else {
    Write-Bitacora "$migrados launchers migrated. Windows Script Host can now be disabled without breaking anything." 'OK'
}

if ($Simular) {
    Write-Host ''
    Write-Host '  Dry run. To do it for real:  .\Migrate-Launchers.ps1 -Apply' -ForegroundColor Green
    Write-Host ''
}

# Returns whether it is safe to turn off WSH, so Harden.ps1 can check it.
return ($fallos -eq 0)
