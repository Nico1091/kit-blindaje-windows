<#
.SYNOPSIS
    Deshace lo que hizo Blindar.ps1.

.DESCRIPTION
    Tres modos:

      -Emergencia   Solo la red. Rapido, sin preguntas, sin elegir respaldo.
                    Es lo que ejecutas si te has quedado sin Internet.

      (sin nada)    Muestra los respaldos y restaura el ultimo por completo:
                    firewall, registro y servicios.

      -Respaldo X   Restaura una carpeta de respaldo concreta.

.EXAMPLE
    .\Restaurar.ps1 -Emergencia
    Devuelve el firewall y los servicios de red y comprueba que hay Internet.

.EXAMPLE
    .\Restaurar.ps1 -Listar
    Muestra que respaldos hay disponibles.
#>

[CmdletBinding()]
param(
    [switch]$Emergencia,
    [switch]$Listar,
    [string]$Respaldo,
    [switch]$SinPreguntar
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Nucleo.ps1')

# ---------------------------------------------------------------------------

function Get-Respaldos {
    Get-ChildItem -Path $script:DirResp -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'firewall.wfw') } |
        Sort-Object Name -Descending
}

function Show-Respaldos {
    $r = Get-Respaldos
    if (-not $r) { Write-Host '  No hay ningun respaldo.' -ForegroundColor Yellow; return $null }
    Write-Host ''
    Write-Host '  Respaldos disponibles:' -ForegroundColor Cyan
    $i = 0
    foreach ($x in $r) {
        $i++
        $fw  = Get-Item (Join-Path $x.FullName 'firewall.wfw') -ErrorAction SilentlyContinue
        $reg = (Get-ChildItem $x.FullName -Filter '*.reg' -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("   [{0}]  {1}   firewall {2} KB, {3} claves de registro" -f `
            $i, $x.Name, [math]::Round($fw.Length/1KB), $reg) -ForegroundColor Gray
    }
    Write-Host ''
    return $r
}

# ===========================================================================
# MODO EMERGENCIA
# ===========================================================================

function Invoke-Emergencia {
    Write-Titulo 'RESTAURACION DE EMERGENCIA -- SOLO RED'

    $ultimo = Get-Respaldos | Select-Object -First 1
    if (-not $ultimo) {
        Write-Bitacora 'no hay respaldo de firewall. Se aplica la configuracion segura de fabrica.' 'AVISO'
        & netsh.exe advfirewall reset > $null 2>&1
    } else {
        $wfw = Join-Path $ultimo.FullName 'firewall.wfw'
        Write-Bitacora "importando firewall desde $($ultimo.Name)" 'INFO'
        & netsh.exe advfirewall reset > $null 2>&1
        $r = & netsh.exe advfirewall import "$wfw" 2>&1
        Write-Bitacora "netsh import: $r" 'INFO'
    }

    # Estado seguro y funcional pase lo que pase.
    & netsh.exe advfirewall set allprofiles state on > $null 2>&1
    & netsh.exe advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound > $null 2>&1
    Write-Bitacora 'firewall: entrada bloqueada, SALIDA PERMITIDA' 'CAMBIO'

    # Fuera las reglas que puso el Centinela y que pueden estorbar.
    foreach ($n in @('Centinela-Sin-Ping-IPv4','Centinela-Sin-Ping-IPv6',
                     'Centinela-Blindaje-Subred-Local')) {
        try { Remove-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-NetFirewallRule -DisplayName 'Centinela-VM-Aislada-*' -ErrorAction SilentlyContinue } catch { }
    Write-Bitacora 'reglas propias del Centinela retiradas' 'CAMBIO'

    # Servicios de red arriba.
    foreach ($s in @('Dhcp','Dnscache','nsi','NlaSvc','netprofm','WlanSvc','Wcmsvc','BFE','mpssvc','LanmanWorkstation')) {
        try {
            Set-Service -Name $s -StartupType Automatic -ErrorAction Stop
            if ((Get-Service $s).Status -ne 'Running') { Start-Service -Name $s -ErrorAction SilentlyContinue }
            Write-Bitacora "servicio $s arriba" 'OK'
        } catch { Write-Bitacora "servicio $s : $($_.Exception.Message)" 'AVISO' }
    }

    # Adaptadores de red activos.
    try {
        Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Disabled' } | ForEach-Object {
            Enable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue
            Write-Bitacora "adaptador $($_.Name) reactivado" 'CAMBIO'
        }
    } catch { }

    # Resolucion de nombres al estado que funcionaba.
    try {
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Nombre 'EnableMulticast' -Valor 1 | Out-Null
        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
        Write-Bitacora 'DNS devuelto al que reparta la red (DHCP)' 'CAMBIO'
    } catch { }

    & ipconfig.exe /flushdns > $null 2>&1
    Disable-Reversor -Silencioso

    Write-Host ''
    Write-Titulo 'COMPROBANDO'
    $chk = Test-Conectividad
    Write-Host ''
    if ($chk.Sano) {
        Write-Host '  Internet restaurado.' -ForegroundColor Green
    } else {
        Write-Host '  SIGUE SIN HABER SALIDA. Prueba, en este orden:' -ForegroundColor Red
        Write-Host '    1. Desconecta y vuelve a conectar el Wi-Fi.' -ForegroundColor Yellow
        Write-Host '    2. Reinicia el equipo.' -ForegroundColor Yellow
        Write-Host '    3. Como ultimo recurso, en PowerShell como administrador:' -ForegroundColor Yellow
        Write-Host '         netsh winsock reset' -ForegroundColor White
        Write-Host '         netsh int ip reset' -ForegroundColor White
        Write-Host '       y REINICIA (esos dos dejan la pila de red a medias hasta reiniciar).' -ForegroundColor Yellow
        Write-Host '    4. Restauracion del sistema al punto "Centinela".' -ForegroundColor Yellow
    }
    Write-Host ''
}

# ===========================================================================
# RESTAURACION COMPLETA
# ===========================================================================

function Invoke-RestauracionCompleta {
    param([string]$Carpeta)

    Write-Titulo "RESTAURACION COMPLETA DESDE $(Split-Path $Carpeta -Leaf)"

    # 1) Firewall
    $wfw = Join-Path $Carpeta 'firewall.wfw'
    if (Test-Path $wfw) {
        & netsh.exe advfirewall reset > $null 2>&1
        $r = & netsh.exe advfirewall import "$wfw" 2>&1
        Write-Bitacora "firewall restaurado ($r)" 'CAMBIO'
    } else { Write-Bitacora 'no hay firewall.wfw en este respaldo' 'ERROR' }

    foreach ($n in @('Centinela-Sin-Ping-IPv4','Centinela-Sin-Ping-IPv6','Centinela-Blindaje-Subred-Local')) {
        try { Remove-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-NetFirewallRule -DisplayName 'Centinela-VM-Aislada-*' -ErrorAction SilentlyContinue } catch { }

    # 2) Registro
    $n = 0
    foreach ($f in Get-ChildItem $Carpeta -Filter '*.reg' -ErrorAction SilentlyContinue) {
        & reg.exe import "$($f.FullName)" > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $n++; Write-Bitacora "registro restaurado: $($f.BaseName)" 'CAMBIO' }
        else { Write-Bitacora "no se pudo importar $($f.BaseName)" 'AVISO' }
    }
    Write-Bitacora "claves de registro restauradas: $n" 'OK'

    # 3) Servicios, al estado exacto que tenian
    $js = Join-Path $Carpeta 'estado.json'
    if (Test-Path $js) {
        try {
            $est = Get-Content $js -Raw | ConvertFrom-Json
            $n = 0
            foreach ($s in $est.servicios) {
                try {
                    $actual = Get-Service -Name $s.Name -ErrorAction Stop
                    if ($actual.StartType -ne $s.StartType) {
                        Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction Stop
                        $n++
                    }
                    if ($s.Status -eq 'Running' -and $actual.Status -ne 'Running') {
                        Start-Service -Name $s.Name -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
            Write-Bitacora "servicios devueltos a su estado original: $n corregidos" 'CAMBIO'

            # DNS
            foreach ($d in $est.dns) {
                try {
                    if ($d.ServerAddresses -and $d.ServerAddresses.Count -gt 0) {
                        Set-DnsClientServerAddress -InterfaceIndex $d.InterfaceIndex -ServerAddresses $d.ServerAddresses -ErrorAction Stop
                        Write-Bitacora "DNS de $($d.InterfaceAlias) devuelto a $($d.ServerAddresses -join ', ')" 'CAMBIO'
                    }
                } catch { }
            }

            # NetBIOS
            foreach ($nb in $est.netbios) {
                try {
                    $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "SettingID='$($nb.SettingID)'" -ErrorAction Stop
                    if ($cfg) { Invoke-CimMethod -InputObject $cfg -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]$nb.TcpipNetbiosOptions } -ErrorAction SilentlyContinue | Out-Null }
                } catch { }
            }
        } catch { Write-Bitacora "estado.json ilegible: $($_.Exception.Message)" 'ERROR' }
    }

    # 4) Adaptadores de VMware
    foreach ($vmnet in @('VMware Network Adapter VMnet1','VMware Network Adapter VMnet8')) {
        try { Enable-NetAdapter -Name $vmnet -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    }

    # 5) Ficheros .vmx: si hay copia del Centinela, se devuelve.
    $n = 0
    foreach ($base in @("$env:USERPROFILE\Documents\Virtual Machines", "$env:USERPROFILE\vmware", 'D:\VMs')) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -Filter '*.vmx.centinela-copia' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $orig = $_.FullName -replace '\.centinela-copia$',''
            try { Copy-Item $_.FullName $orig -Force -ErrorAction Stop; $n++ } catch { }
        }
    }
    if ($n) { Write-Bitacora "ficheros .vmx devueltos a su version original: $n" 'CAMBIO' }

    Disable-Reversor -Silencioso

    Write-Host ''
    Write-Titulo 'COMPROBANDO'
    Test-Conectividad | Out-Null
    Write-Host ''
    Write-Host '  Restauracion terminada. REINICIA para que todo vuelva a su sitio.' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Nota: las preferencias de Defender (CFA, reglas ASR, proteccion de red)' -ForegroundColor DarkGray
    Write-Host '  NO se revierten aqui a proposito: son protecciones, no configuracion' -ForegroundColor DarkGray
    Write-Host '  de sistema, y quitarlas te deja peor de lo que estabas. Si de verdad' -ForegroundColor DarkGray
    Write-Host '  quieres deshacerlas:' -ForegroundColor DarkGray
    Write-Host '     Set-MpPreference -EnableControlledFolderAccess Disabled' -ForegroundColor White
    Write-Host ''
}

# ===========================================================================
# PRINCIPAL
# ===========================================================================

Write-Host ''
Write-Host '   #############################################################' -ForegroundColor DarkCyan
Write-Host '   #        C E N T I N E L A   --   R E S T A U R A R         #' -ForegroundColor White
Write-Host '   #############################################################' -ForegroundColor DarkCyan

if ($Listar) { Show-Respaldos | Out-Null; return }

if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos @(
    $(if ($Emergencia)   { '-Emergencia' })
    $(if ($SinPreguntar) { '-SinPreguntar' })
    $(if ($Respaldo)     { '-Respaldo'; $Respaldo })
) )) { return }

if ($Emergencia) { Invoke-Emergencia; return }

$destino = $null
if ($Respaldo) {
    $destino = if (Test-Path $Respaldo) { $Respaldo } else { Join-Path $script:DirResp $Respaldo }
    if (-not (Test-Path $destino)) { Write-Host "  No existe: $destino" -ForegroundColor Red; return }
} else {
    $lista = Show-Respaldos
    if (-not $lista) { return }
    if ($SinPreguntar) {
        $destino = $lista[0].FullName
    } else {
        $sel = Read-Host '  Numero a restaurar (Intro = el mas reciente, X = salir)'
        if ($sel -match '^[xX]') { Write-Host '  Cancelado.' -ForegroundColor Green; return }

        if ([string]::IsNullOrWhiteSpace($sel)) {
            $destino = $lista[0].FullName
        } elseif ($sel -match '^\s*\d+\s*$' -and ([int]$sel) -ge 1 -and ([int]$sel) -le $lista.Count) {
            $destino = $lista[[int]$sel - 1].FullName
        } else {
            # Restaurar es una operacion delicada: ante una respuesta que no se
            # entiende, se sale. Adivinar aqui seria restaurar un respaldo que
            # el usuario no pidio.
            Write-Host "  '$sel' no es una opcion valida (hay $($lista.Count) respaldos)." -ForegroundColor Red
            Write-Host '  No se toca nada. Vuelve a lanzarlo y elige un numero de la lista.' -ForegroundColor Yellow
            return
        }
    }
}

Write-Host ''
Write-Host "  Se va a restaurar: $destino" -ForegroundColor Yellow
if (-not $SinPreguntar) {
    if ((Read-Host '  Escribe RESTAURAR para confirmar') -ne 'RESTAURAR') {
        Write-Host '  Cancelado. No se ha tocado nada.' -ForegroundColor Green; return
    }
}

Invoke-RestauracionCompleta -Carpeta $destino
