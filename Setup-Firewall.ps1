param([switch]$Revert, [switch]$NoPause)
# Configures the whole Windows firewall in a single pass.
# Brings together what used to be spread over Harden.ps1 (ports, stealth and vm layers),
# Windows-Services.ps1 (remote assistance), Movie-Grade.ps1 (usbipd) and
# IP-Always-Hidden.ps1 (Browser lock). It can be run again without harm.
#
# Safety: before touching anything it exports the whole policy and arms a reverter
# that re-imports it after 10 minutes. It is only disarmed if there is internet and the
# user confirms. -Revert re-imports the latest backup by hand.
# Requires administrator. ASCII text on purpose (PowerShell 5 and accented characters).

$ErrorActionPreference = 'Continue'
$resp    = "$env:USERPROFILE\Security\Backups"
$ultimo  = "$resp\firewall-LATEST.txt"
$tarea   = 'Firewall - 10 min reverter'
$navegador = 'C:\Program Files\LibreWolf\librewolf.exe'
$cambios = 0; $avisos = 0

function Paso($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
function Hecho($t) { Write-Host "   [OK] $t" -ForegroundColor Green; $script:cambios++ }
function Aviso($t) { Write-Host "   [!!] $t" -ForegroundColor Yellow; $script:avisos++ }
function Fin($t) {
    Write-Host ''; Write-Host $t
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit
}
# Compares without accents or case: Windows group names in Spanish carry accents
# and a literal comparison matched none of them (a bug found while building this).
function Plano($s) {
    if (-not $s) { return '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormD)
    (-join ($d.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })).ToLower()
}
function HayInternet {
    # Raw TCP to 443: msftconnecttest fails on networks that inspect TLS.
    foreach ($ip in '1.1.1.1', '9.9.9.9', '8.8.8.8') {
        $c = New-Object Net.Sockets.TcpClient
        try { if ($c.ConnectAsync($ip, 443).Wait(4000) -and $c.Connected) { return $true } }
        catch { } finally { $c.Dispose() }
    }
    return $false
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fin 'It must be run as administrator (the .bat does it by itself).' }
New-Item -ItemType Directory -Force $resp | Out-Null

if ($Revert) {
    if (-not (Test-Path $ultimo)) { Fin 'There is no firewall backup.' }
    $f = (Get-Content $ultimo -Raw).Trim()
    netsh advfirewall import "$f" | Out-Null
    Unregister-ScheduledTask $tarea -Confirm:$false -EA 0
    Fin "Firewall restored to the state in $f"
}

# ---------------------------------------------------------------- 0. Backup
Paso '0. Backup and 10-minute reverter'
$wfw = "$resp\firewall-$(Get-Date -Format yyyyMMdd-HHmmss).wfw"
netsh advfirewall export "$wfw" | Out-Null
if (-not (Test-Path $wfw)) { Fin 'The firewall could not be exported: nothing is touched.' }
Set-Content $ultimo $wfw -Encoding ASCII
$acc = New-ScheduledTaskAction -Execute 'netsh.exe' -Argument "advfirewall import `"$wfw`""
$dis = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)
Register-ScheduledTask $tarea -Action $acc -Trigger $dis -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Hecho "policy saved to $wfw; reverter armed"

# ---------------------------------------------------------------- 1. Profiles
Paso '1. Profiles: inbound blocked, outbound allowed, blocked connections logged'
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -DefaultInboundAction Block `
    -DefaultOutboundAction Allow -NotifyOnListen True -LogBlocked True -LogAllowed False `
    -LogMaxSizeKilobytes 32767 -LogFileName '%systemroot%\system32\LogFiles\Firewall\pfirewall.log'
Hecho 'Domain, Private and Public'
Get-NetConnectionProfile -EA 0 | Where-Object NetworkCategory -ne 'Public' | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Public -EA 0
    Hecho "network '$($_.Name)' set to Public"
}

# ---------------------------------------------------------------- 2. Inbound sweep
Paso '2. Unneeded inbound rules (disabled, not deleted)'
# A single query and filtering afterwards: combining -DisplayName with -Direction is a PowerShell
# error that, inside an empty catch, once left 78 rules open.
$entrada = @(Get-NetFirewallRule -Direction Inbound -Enabled True -EA Stop)
# Guard: never touch core networking or DHCP, or the computer is left without an IP.
# The group names below are matched in Spanish and English because Windows shows them in its own language.
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
# Programs that only listen on 127.0.0.1: the firewall does not filter loopback,
# so their inbound rule only adds attack surface.
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
Hecho "$n discovery, remote access and local service rules disabled"

# What must never accept connections: adb in a temporary folder and crypto miners.
$n = 0
foreach ($r in @(Get-NetFirewallRule -Direction Inbound -EA 0)) {
    if ((Plano $r.DisplayName) -match 'adb\.exe|lolminer|zephyrd') { Remove-NetFirewallRule -Name $r.Name -EA 0; $n++ }
}
Hecho "$n adb and miner rules removed"

# Games: they stay on private networks, out of the public profile.
$n = 0
foreach ($r in $entrada) {
    if ((Plano $r.DisplayName) -match 'steam|grand theft auto|god of war|fallout|game bar' -and
        ($r.Profile -match 'Public' -or "$($r.Profile)" -eq 'Any')) {
        Set-NetFirewallRule -Name $r.Name -Profile Domain, Private -EA 0; $n++
    }
}
Hecho "$n game rules taken out of the public profile"

# ---------------------------------------------------------------- 3. Own rules
Paso '3. Own blocking rules'
function Regla($nombre, [hashtable]$p) {
    # The new rule is created before the old one is deleted: if creation fails, the old one stays.
    $viejas = @(Get-NetFirewallRule -DisplayName $nombre -EA 0)
    try { $n = New-NetFirewallRule -DisplayName $nombre -Enabled True -EA Stop @p }
    catch { Aviso "$nombre : $($_.Exception.Message)"; return }
    $viejas | Where-Object Name -ne $n.Name | Remove-NetFirewallRule
    Hecho $nombre
}
# Echo only: ICMP types 3 and 11 still pass; without them path MTU discovery breaks.
Regla 'Sentinel-No-Ping-IPv4' @{ Direction = 'Inbound'; Action = 'Block'; Protocol = 'ICMPv4'; IcmpType = '8'; Profile = 'Any' }
Regla 'Sentinel-No-Ping-IPv6' @{ Direction = 'Inbound'; Action = 'Block'; Protocol = 'ICMPv6'; IcmpType = '128'; Profile = 'Any' }
Regla 'Sentinel-Hardening-Local-Subnet' @{ Direction = 'Inbound'; Action = 'Block'; RemoteAddress = 'LocalSubnet'; Profile = 'Public', 'Private'
    Description = 'Nobody on the local network starts connections to this computer; replies to what the computer requests still pass.' }

# Virtual machines: nothing comes in and nothing talks to them (only if the VMware adapters exist).
$i = 0
foreach ($vmnet in 'VMware Network Adapter VMnet1', 'VMware Network Adapter VMnet8') {
    # With VMware but without its adapters ("Not Present") Windows does not accept rules on them;
    # in that case the VMs have no network either, and existing rules are left as they are.
    $ad = Get-NetAdapter -Name $vmnet -EA 0
    if (-not $ad -or $ad.Status -eq 'Not Present') { continue }
    $i++
    Regla "Sentinel-VM-Isolated-In-$i" @{ Direction = 'Inbound'; Action = 'Block'; InterfaceAlias = $vmnet; Profile = 'Any' }
    Regla "Sentinel-VM-Isolated-Out-$i" @{ Direction = 'Outbound'; Action = 'Block'; InterfaceAlias = $vmnet; Profile = 'Any' }
}
if ($i -eq 0) { Write-Host '   (VMware adapters absent: VM rules left untouched)' }

# Browser lock: LibreWolf cannot talk to any internet address;
# only to this computer (Tor tunnel at 127.0.0.1:9050) and to the home network.
if (Test-Path $navegador) {
    Regla 'Browser: Tor only (IP always hidden)' @{ Direction = 'Outbound'; Action = 'Block'; Program = $navegador; Profile = 'Any'
        RemoteAddress = '0.0.0.0-9.255.255.255', '11.0.0.0-126.255.255.255', '128.0.0.0-169.253.255.255',
                        '169.255.0.0-172.15.255.255', '172.32.0.0-192.167.255.255', '192.169.0.0-255.255.255.255', '2000::/3'
        Description = 'Setup-Firewall.ps1' }
} else { Aviso 'LibreWolf is not installed: Browser lock skipped' }

# ---------------------------------------------------------------- 4. Exposed services
Paso '4. Services that open ports'
foreach ($s in 'WinRM', 'LanmanServer', 'SSDPSRV', 'upnphost', 'RemoteRegistry', 'RemoteAccess', 'SessionEnv',
               'TermService', 'UmRdpService', 'WMPNetworkSvc', 'FDResPub', 'fdPHost', 'lltdsvc', 'CDPSvc',
               'PNRPsvc', 'p2psvc', 'p2pimsvc', 'PNRPAutoReg', 'iphlpsvc') {
    $sv = Get-Service $s -EA 0
    if (-not $sv) { continue }
    if ($sv.StartType -ne 'Disabled' -or $sv.Status -ne 'Stopped') {
        Stop-Service $s -Force -EA 0; Set-Service $s -StartupType Disabled -EA 0; Hecho "$s stopped and disabled"
    }
}
$ts = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty $ts fDenyTSConnections 1 -Type DWord
Set-ItemProperty $ts fAllowToGetHelp 0 -Type DWord
Hecho 'remote desktop and remote assistance denied'

# ---------------------------------------------------------------- 5. Check
Paso '5. Internet check'
$red = HayInternet
$dns = [bool](Resolve-DnsName example.com -Server 127.0.0.1 -DnsOnly -EA 0)
Write-Host ("   internet (TCP 443): {0}   local DNS (Unbound): {1}" -f $(if ($red) { 'YES' } else { 'NO' }), $(if ($dns) { 'YES' } else { 'NO' }))
if (-not $red) {
    Aviso 'No internet after the change: the firewall is restored right now.'
    netsh advfirewall import "$wfw" | Out-Null
    Unregister-ScheduledTask $tarea -Confirm:$false -EA 0
    Fin 'Firewall restored. Nothing was lost.'
}
$ok = Read-Host 'Open a page in the Browser. If it works, type YES (if you do not answer, everything is undone in 10 min)'
if ($ok -match '^\s*[sy]') {
    Unregister-ScheduledTask $tarea -Confirm:$false -EA 0
    Fin ("DONE. {0} changes, {1} warnings. Reverter disarmed. Backup: {2}" -f $cambios, $avisos, $wfw)
}
Fin 'You did not confirm: the reverter will restore the firewall within 10 minutes.'
