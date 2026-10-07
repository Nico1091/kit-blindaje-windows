<#
.SYNOPSIS
    Sustituye los lanzadores .vbs por equivalentes que no necesitan
    Windows Script Host.

.DESCRIPTION
    Desactivar Windows Script Host es una de las mejores defensas que existen
    contra el ransomware que llega por correo: mata los .vbs y .js de doble
    clic. El problema es que en este equipo hay tres lanzadores propios que
    son .vbs, y apagarlo sin mas los romperia:

      Desktop\Scriptorium\Scriptorium.vbs        ->  pythonw -m scriptorium
      Desktop\Scriptorium-II\Scriptorium.vbs     ->  pythonw -m libro
      ...\Startup\Granja de noticias.vbs  ->  granja.bat

    Los tres hacen exactamente lo mismo: lanzar un programa sin que aparezca
    la ventana negra de consola. Eso no necesita WSH para nada:

      - Los de escritorio pasan a ser accesos directos a pythonw.exe, que por
        definicion no abre consola. Mismo resultado, una pieza menos.
      - El de arranque pasa a ser una tarea programada al iniciar sesion, que
        ademas es mas fiable que la carpeta de Inicio.

    Los .vbs originales NO se borran: se mueven a Respaldos\lanzadores-vbs\.

.EXAMPLE
    .\Migrar-Lanzadores.ps1
    Simulacro: ensena que haria.

.EXAMPLE
    .\Migrar-Lanzadores.ps1 -Aplicar
#>

[CmdletBinding()]
param([switch]$Aplicar)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Nucleo.ps1')
$Simular = -not $Aplicar

Write-Titulo "MIGRACION DE LANZADORES .VBS  ($(if ($Simular) { 'SIMULACRO' } else { 'REAL' }))"

$guardados = Join-Path $script:DirResp 'lanzadores-vbs'
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
    $l.WindowStyle      = 7          # minimizado
    $l.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($w) | Out-Null
}

# ---------------------------------------------------------------------------
# 1) Los dos Scriptorium: acceso directo a pythonw
# ---------------------------------------------------------------------------

$pythonw = Find-Pythonw
if (-not $pythonw) {
    Write-Bitacora 'NO SE ENCUENTRA pythonw.exe. No se migra nada de Scriptorium.' 'ERROR'
    Write-Bitacora 'Sin sustituto verificado no se toca un lanzador que funciona.' 'ERROR'
    $fallos++
} else {
    Write-Bitacora "pythonw encontrado: $pythonw" 'OK'

    $casos = @(
        @{ Carpeta = "$env:USERPROFILE\Desktop\Scriptorium";    Modulo = 'scriptorium'; Nombre = 'Scriptorium' }
        @{ Carpeta = "$env:USERPROFILE\Desktop\Scriptorium-II"; Modulo = 'libro';       Nombre = 'Scriptorium II' }
    )

    foreach ($c in $casos) {
        $vbs = Join-Path $c.Carpeta 'Scriptorium.vbs'
        if (-not (Test-Path $vbs)) { Write-Bitacora "no existe: $vbs" 'INFO'; continue }

        $lnk = Join-Path $c.Carpeta ("$($c.Nombre).lnk")
        if ($Simular) {
            Write-Bitacora "SIMULACRO -> crear '$($c.Nombre).lnk' -> pythonw -m $($c.Modulo)" 'SIMULA'
            Write-Bitacora "SIMULACRO -> guardar el .vbs original en Respaldos\lanzadores-vbs\" 'SIMULA'
            $migrados++
            continue
        }

        try {
            New-AccesoDirecto -Destino $lnk -Programa $pythonw -Argumentos "-m $($c.Modulo)" `
                -Carpeta $c.Carpeta -Descripcion "Abre $($c.Nombre) sin ventana de consola. Sustituye al lanzador .vbs."
            if (-not (Test-Path $lnk)) { throw 'el acceso directo no se creo' }

            Move-Item -Path $vbs -Destination (Join-Path $guardados "$($c.Nombre)-Scriptorium.vbs") -Force -ErrorAction Stop
            Write-Bitacora "$($c.Nombre): acceso directo creado, .vbs guardado" 'CAMBIO'
            $migrados++
        } catch {
            Write-Bitacora "$($c.Nombre) FALLO: $($_.Exception.Message)" 'ERROR'
            $fallos++
        }
    }
}

# ---------------------------------------------------------------------------
# 2) La granja de noticias: tarea programada al iniciar sesion
# ---------------------------------------------------------------------------

$vbsGranja = Join-Path $inicio 'Granja de noticias.vbs'
if (Test-Path $vbsGranja) {
    # Se saca el destino real del propio .vbs en vez de suponerlo.
    $contenido = Get-Content $vbsGranja -Raw
    $bat = $null
    if ($contenido -match '"{2,3}([A-Za-z]:\\[^"]+\.(?:bat|cmd))"{2,3}') { $bat = $Matches[1] }

    if (-not $bat -or -not (Test-Path $bat)) {
        Write-Bitacora "no se pudo leer el destino de la granja (o ya no existe): $bat" 'AVISO'
        Write-Bitacora 'el .vbs se deja donde esta. Windows Script Host NO se desactivara.' 'AVISO'
        $fallos++
    } elseif ($Simular) {
        Write-Bitacora "SIMULACRO -> tarea 'Granja-Noticias' al iniciar sesion -> $bat" 'SIMULA'
        $migrados++
    } else {
        try {
            $accion  = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$bat`"" -WorkingDirectory (Split-Path $bat -Parent)
            $disparo = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
            $disparo.Delay = 'PT1M'
            $ppal    = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
            $opts    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                         -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

            Register-ScheduledTask -TaskName 'Granja-Noticias' -Action $accion -Trigger $disparo `
                -Principal $ppal -Settings $opts `
                -Description 'Arranca la granja de noticias al iniciar sesion. Sustituye al lanzador .vbs para poder desactivar Windows Script Host.' `
                -Force -ErrorAction Stop | Out-Null

            Move-Item -Path $vbsGranja -Destination (Join-Path $guardados 'Granja de noticias.vbs') -Force -ErrorAction Stop
            Write-Bitacora "granja de noticias: ahora es la tarea 'Granja-Noticias'" 'CAMBIO'
            $migrados++
        } catch {
            Write-Bitacora "granja de noticias FALLO: $($_.Exception.Message)" 'ERROR'
            $fallos++
        }
    }
} else {
    Write-Bitacora 'no hay .vbs de la granja en la carpeta de Inicio' 'INFO'
}

# ---------------------------------------------------------------------------
# Veredicto: solo se puede apagar WSH si NO queda ningun .vbs en uso.
# ---------------------------------------------------------------------------

Write-Host ''
$pendientes = @()
foreach ($r in @("$env:USERPROFILE\Desktop", $inicio)) {
    if (Test-Path $r) {
        $pendientes += Get-ChildItem $r -Include '*.vbs','*.wsf' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                       Where-Object { $_.DirectoryName -notlike "*\Respaldos\*" }
    }
}

if ($fallos -gt 0) {
    Write-Bitacora "$fallos migraciones fallaron. NO desactives Windows Script Host todavia." 'ERROR'
} elseif ($pendientes.Count -gt 0 -and -not $Simular) {
    Write-Bitacora "quedan $($pendientes.Count) ficheros .vbs que podrian estar en uso:" 'AVISO'
    $pendientes | ForEach-Object { Write-Bitacora "   $($_.FullName)" 'AVISO' }
    Write-Bitacora 'revisalos antes de desactivar Windows Script Host.' 'AVISO'
} else {
    Write-Bitacora "$migrados lanzadores migrados. Ya se puede desactivar Windows Script Host sin romper nada." 'OK'
}

if ($Simular) {
    Write-Host ''
    Write-Host '  Simulacro. Para hacerlo de verdad:  .\Migrar-Lanzadores.ps1 -Aplicar' -ForegroundColor Green
    Write-Host ''
}

# Devuelve si es seguro apagar WSH, para que Blindar.ps1 lo consulte.
return ($fallos -eq 0)
