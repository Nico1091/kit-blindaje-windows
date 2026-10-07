param([switch]$Revertir, [switch]$SinPausa)
# Configura el cortafuegos de Windows completo en una sola pasada (04/10/2026).
# Reune lo que antes estaba repartido en Blindar.ps1 (capas puertos, sigilo y vm),
# Servicios-Windows.ps1 (asistencia remota), Nivel-Pelicula.ps1 (usbipd) e
# IP-Siempre-Oculta.ps1 (candado del Buscador). Se puede repetir sin dano.
#
# Seguridad: antes de tocar nada exporta la politica entera y arma un reversor
# que la reimporta a los 10 minutos. Solo se desarma si hay internet y el
# usuario lo confirma. -Revertir reimporta el ultimo respaldo a mano.
# Exige administrador. Texto en ASCII a proposito (PowerShell 5 y tildes).

$ErrorActionPreference = 'Continue'
$resp    = "$env:USERPROFILE\Seguridad\Respaldos"
$ultimo  = "$resp\cortafuegos-ULTIMO.txt"
$tarea   = 'Cortafuegos - Reversor 10 min'
$navegador = 'C:\Program Files\LibreWolf\librewolf.exe'
$cambios = 0; $avisos = 0

function Paso($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
function Hecho($t) { Write-Host "   [OK] $t" -ForegroundColor Green; $script:cambios++ }
function Aviso($t) { Write-Host "   [!!] $t" -ForegroundColor Yellow; $script:avisos++ }
function Fin($t) {
    Write-Host ''; Write-Host $t
    if (-not $SinPausa) { Read-Host 'Pulsa Enter para cerrar' | Out-Null }
    exit
}
# Compara sin tildes ni mayusculas: los grupos de Windows en espanol llevan tildes
# y una comparacion literal no coincidia con ninguno (fallo del 26/08).
function Plano($s) {
    if (-not $s) { return '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormD)
    (-join ($d.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })).ToLower()
}
function HayInternet {
    # TCP crudo al 443: msftconnecttest falla con redes que inspeccionan TLS.
    foreach ($ip in '1.1.1.1', '9.9.9.9', '8.8.8.8') {
        $c = New-Object Net.Sockets.TcpClient
        try { if ($c.ConnectAsync($ip, 443).Wait(4000) -and $c.Connected) { return $true } }
        catch { } finally { $c.Dispose() }
    }
    return $false
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fin 'Hace falta abrirlo como administrador (el .bat lo hace solo).' }
New-Item -ItemType Directory -Force $resp | Out-Null

if ($Revertir) {
    if (-not (Test-Path $ultimo)) { Fin 'No hay respaldo del cortafuegos.' }
    $f = (Get-Content $ultimo -Raw).Trim()
    netsh advfirewall import "$f" | Out-Null
    Unregister-ScheduledTask $tarea -Confirm:$false -EA 0
    Fin "Cortafuegos devuelto al estado de $f"
}

# ---------------------------------------------------------------- 0. Respaldo
Paso '0. Respaldo y reversor de 10 minutos'
$wfw = "$resp\cortafuegos-$(Get-Date -Format yyyyMMdd-HHmmss).wfw"
netsh advfirewall export "$wfw" | Out-Null
if (-not (Test-Path $wfw)) { Fin 'No se pudo exportar el cortafuegos: no se toca nada.' }
Set-Content $ultimo $wfw -Encoding ASCII
$acc = New-ScheduledTaskAction -Execute 'netsh.exe' -Argument "advfirewall import `"$wfw`""
$dis = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)
Register-ScheduledTask $tarea -Action $acc -Trigger $dis -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Hecho "politica guardada en $wfw; reversor armado"

# ---------------------------------------------------------------- 1. Perfiles
Paso '1. Perfiles: entrada bloqueada, salida libre, registro de bloqueos'
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -DefaultInboundAction Block `
    -DefaultOutboundAction Allow -NotifyOnListen True -LogBlocked True -LogAllowed False `
    -LogMaxSizeKilobytes 32767 -LogFileName '%systemroot%\system32\LogFiles\Firewall\pfirewall.log'
Hecho 'Dominio, Privado y Publico'
Get-NetConnectionProfile -EA 0 | Where-Object NetworkCategory -ne 'Public' | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Public -EA 0
    Hecho "red '$($_.Name)' pasada a Publica"
}

# ---------------------------------------------------------------- 2. Barrido de entrada
Paso '2. Reglas de entrada que sobran (se desactivan, no se borran)'
# Una sola consulta y filtro despues: combinar -DisplayName con -Direction es un error
# de PowerShell que, dentro de un catch vacio, dejo 78 reglas abiertas el 26/08.
$entrada = @(Get-NetFirewallRule -Direction Inbound -Enabled True -EA Stop)
# Guardia: nunca tocar la red basica ni el DHCP, o el equipo se queda sin IP.
$intocable = { param($r) (Plano "$($r.DisplayGroup) $($r.DisplayName)") -match 'redes principales|core networking|dhcp|iphttps' }
$grupos = 'deteccion de redes', 'network discovery', 'wi-fi direct', 'wfd', 'servicio wlan',
    'proyeccion inalambrica', 'projection', 'optimizacion de distribucion', 'delivery optimization',
    'plataforma de dispositivos conectados', 'connected devices platform', 'myasus', 'cast to device',
    'transmitir en dispositivo', 'teredo', 'mdns', 'uso compartido de proximidad', 'proximity sharing',
    'media foundation', 'uso compartido de archivos e impresoras', 'file and printer sharing',
    'alljoyn', 'deteccion de funcion', 'function discovery', 'experiencia de caracteristicas de windows',
    'windows feature experience', 'asistencia remota', 'remote assistance', 'escritorio remoto',
    'remote desktop', 'monitor de eventos remotos', 'remote event monitor', 'reproductor de windows media',
    'windows media player', 'administracion remota', 'remote management', 'usbipd'
# Programas que solo escuchan en 127.0.0.1: el cortafuegos no filtra el bucle local,
# asi que su regla de entrada solo anade superficie.
$soloLocal = 'python.exe', 'node.js', 'lm studio', 'postman', 'packet tracer', 'podman desktop',
    'outlook', 'asusswitchnet'
$n = 0
foreach ($r in $entrada) {
    if (& $intocable $r) { continue }
    $texto = Plano "$($r.DisplayGroup) $($r.DisplayName)"
    if ($grupos + $soloLocal | Where-Object { $texto.Contains($_) }) {
        Disable-NetFirewallRule -Name $r.Name -EA 0; $n++
    }
}
Hecho "$n reglas de descubrimiento, acceso remoto y servicios locales desactivadas"

# Lo que no debe aceptar conexiones nunca: adb en una carpeta temporal y mineros.
$n = 0
foreach ($r in @(Get-NetFirewallRule -Direction Inbound -EA 0)) {
    if ((Plano $r.DisplayName) -match 'adb\.exe|lolminer|zephyrd') { Remove-NetFirewallRule -Name $r.Name -EA 0; $n++ }
}
Hecho "$n reglas de adb y mineros eliminadas"

# Juegos: se quedan en red privada, fuera de la publica.
$n = 0
foreach ($r in $entrada) {
    if ((Plano $r.DisplayName) -match 'steam|grand theft auto|god of war|fallout|game bar' -and
        ($r.Profile -match 'Public' -or "$($r.Profile)" -eq 'Any')) {
        Set-NetFirewallRule -Name $r.Name -Profile Domain, Private -EA 0; $n++
    }
}
Hecho "$n reglas de juegos retiradas del perfil publico"

# ---------------------------------------------------------------- 3. Reglas propias
Paso '3. Reglas propias de bloqueo'
function Regla($nombre, [hashtable]$p) {
    # Se crea la nueva antes de borrar la vieja: si la creacion falla, la vieja se queda.
    $viejas = @(Get-NetFirewallRule -DisplayName $nombre -EA 0)
    try { $n = New-NetFirewallRule -DisplayName $nombre -Enabled True -EA Stop @p }
    catch { Aviso "$nombre : $($_.Exception.Message)"; return }
    $viejas | Where-Object Name -ne $n.Name | Remove-NetFirewallRule
    Hecho $nombre
}
# Solo el eco: los tipos 3 y 11 siguen pasando, sin ellos se rompe el descubrimiento de MTU.
# Estas dos reglas faltaban en el equipo al revisarlo el 04/10/2026.
Regla 'Centinela-Sin-Ping-IPv4' @{ Direction = 'Inbound'; Action = 'Block'; Protocol = 'ICMPv4'; IcmpType = '8'; Profile = 'Any' }
Regla 'Centinela-Sin-Ping-IPv6' @{ Direction = 'Inbound'; Action = 'Block'; Protocol = 'ICMPv6'; IcmpType = '128'; Profile = 'Any' }
Regla 'Centinela-Blindaje-Subred-Local' @{ Direction = 'Inbound'; Action = 'Block'; RemoteAddress = 'LocalSubnet'; Profile = 'Public', 'Private'
    Description = 'Nadie de la red local inicia conexiones hacia este equipo; las respuestas a lo que el equipo pide siguen pasando.' }

# Maquinas virtuales: ni entran ni se les habla (solo si existen los adaptadores de VMware).
$i = 0
foreach ($vmnet in 'VMware Network Adapter VMnet1', 'VMware Network Adapter VMnet8') {
    # Con VMware sin sus adaptadores ("Not Present") Windows no acepta reglas sobre ellos;
    # en ese caso las VMs tampoco tienen red, y las reglas existentes se dejan como estan.
    $ad = Get-NetAdapter -Name $vmnet -EA 0
    if (-not $ad -or $ad.Status -eq 'Not Present') { continue }
    $i++
    Regla "Centinela-VM-Aislada-Entrada-$i" @{ Direction = 'Inbound'; Action = 'Block'; InterfaceAlias = $vmnet; Profile = 'Any' }
    Regla "Centinela-VM-Aislada-Salida-$i" @{ Direction = 'Outbound'; Action = 'Block'; InterfaceAlias = $vmnet; Profile = 'Any' }
}
if ($i -eq 0) { Write-Host '   (adaptadores de VMware ausentes: reglas de VM sin tocar)' }

# Candado del Buscador: LibreWolf no puede hablar con ninguna direccion de internet;
# solo con este equipo (tunel de Tor en 127.0.0.1:9050) y con la red de la casa.
if (Test-Path $navegador) {
    Regla 'Buscador: solo por Tor (IP siempre oculta)' @{ Direction = 'Outbound'; Action = 'Block'; Program = $navegador; Profile = 'Any'
        RemoteAddress = '0.0.0.0-9.255.255.255', '11.0.0.0-126.255.255.255', '128.0.0.0-169.253.255.255',
                        '169.255.0.0-172.15.255.255', '172.32.0.0-192.167.255.255', '192.169.0.0-255.255.255.255', '2000::/3'
        Description = 'Configurar-Cortafuegos.ps1' }
} else { Aviso 'LibreWolf no esta instalado: candado del Buscador omitido' }

# ---------------------------------------------------------------- 4. Servicios expuestos
Paso '4. Servicios que abren puertos'
foreach ($s in 'WinRM', 'LanmanServer', 'SSDPSRV', 'upnphost', 'RemoteRegistry', 'RemoteAccess', 'SessionEnv',
               'TermService', 'UmRdpService', 'WMPNetworkSvc', 'FDResPub', 'fdPHost', 'lltdsvc', 'CDPSvc',
               'PNRPsvc', 'p2psvc', 'p2pimsvc', 'PNRPAutoReg', 'iphlpsvc') {
    $sv = Get-Service $s -EA 0
    if (-not $sv) { continue }
    if ($sv.StartType -ne 'Disabled' -or $sv.Status -ne 'Stopped') {
        Stop-Service $s -Force -EA 0; Set-Service $s -StartupType Disabled -EA 0; Hecho "$s detenido y deshabilitado"
    }
}
$ts = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty $ts fDenyTSConnections 1 -Type DWord
Set-ItemProperty $ts fAllowToGetHelp 0 -Type DWord
Hecho 'escritorio remoto y asistencia remota denegados'

# ---------------------------------------------------------------- 5. Comprobacion
Paso '5. Comprobacion de internet'
$red = HayInternet
$dns = [bool](Resolve-DnsName example.com -Server 127.0.0.1 -DnsOnly -EA 0)
Write-Host ("   internet (TCP 443): {0}   DNS local (Unbound): {1}" -f $(if ($red) { 'SI' } else { 'NO' }), $(if ($dns) { 'SI' } else { 'NO' }))
if (-not $red) {
    Aviso 'Sin internet tras el cambio: se devuelve el cortafuegos ahora mismo.'
    netsh advfirewall import "$wfw" | Out-Null
    Unregister-ScheduledTask $tarea -Confirm:$false -EA 0
    Fin 'Cortafuegos restaurado. No se perdio nada.'
}
$ok = Read-Host 'Abre una pagina en el Buscador. Si funciona escribe SI (si no contestas, en 10 min se deshace todo)'
if ($ok -match '^\s*s') {
    Unregister-ScheduledTask $tarea -Confirm:$false -EA 0
    Fin ("LISTO. {0} cambios, {1} avisos. Reversor desarmado. Respaldo: {2}" -f $cambios, $avisos, $wfw)
}
Fin 'No confirmaste: el reversor devolvera el cortafuegos dentro de 10 minutos.'
