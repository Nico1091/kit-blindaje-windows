<#
    Core.ps1 -- shared functions of the hardening system.
    No accented characters on purpose: the Windows console mangles them depending
    on the active code page, and this code must run the same on PowerShell 5.1
    and 7.x.

    Nothing in here changes the system by itself. These are tools.
#>

# No StrictMode: this script queries dozens of optional system properties
# and StrictMode would turn every legitimate absence into an exception.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

$script:Raiz      = Split-Path -Parent $PSScriptRoot
$script:DirResp   = Join-Path $Raiz 'Backups'
$script:DirLog    = Join-Path $Raiz 'Logs'
$script:DirBase   = Join-Path $Raiz 'Baseline'
$script:DirInf    = Join-Path $Raiz 'Reports'
$script:DirPerf   = Join-Path $Raiz 'Profiles'
$script:Sello     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Log       = Join-Path $DirLog ("session-$Sello.log")
$script:TareaRev  = 'Sentinel-Emergency-Reverter'

foreach ($d in @($DirResp, $DirLog, $DirBase, $DirInf, $DirPerf)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

function Write-Bitacora {
    param(
        [Parameter(Mandatory)][string]$Mensaje,
        [ValidateSet('INFO','OK','WARN','ERROR','CHANGE','DRYRUN')][string]$Nivel = 'INFO'
    )
    $linea = '{0}  [{1,-6}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Nivel, $Mensaje
    Add-Content -Path $script:Log -Value $linea -Encoding UTF8
    $color = switch ($Nivel) {
        'OK'     { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR'  { 'Red' }
        'CHANGE' { 'Cyan' }
        'DRYRUN' { 'DarkGray' }
        default  { 'Gray' }
    }
    Write-Host $linea -ForegroundColor $color
}

function Write-Titulo {
    param([string]$Texto)
    $barra = '=' * 74
    Write-Host ''
    Write-Host $barra -ForegroundColor DarkCyan
    Write-Host ("  " + $Texto) -ForegroundColor White
    Write-Host $barra -ForegroundColor DarkCyan
    Add-Content -Path $script:Log -Value "`n$barra`n  $Texto`n$barra" -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Elevation
# ---------------------------------------------------------------------------

function Test-Elevado {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Elevado {
    param([string]$Script, [string[]]$Argumentos = @())
    if (Test-Elevado) { return $true }

    Write-Host ''
    Write-Host '  This script needs administrator rights.' -ForegroundColor Yellow
    Write-Host '  It will relaunch elevated. Accept the Windows prompt.' -ForegroundColor Yellow
    Write-Host ''

    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $lista = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$Script`"") + $Argumentos
    try {
        Start-Process -FilePath $exe -ArgumentList $lista -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "  Could not elevate: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Open PowerShell as administrator and run it again by hand.' -ForegroundColor Red
    }
    return $false
}

# ---------------------------------------------------------------------------
# Registry: write and READ BACK. Defender Tamper Protection silently rejects
# writes; without reading back we would believe something was applied
# when it was not.
# ---------------------------------------------------------------------------

function Set-ValorRegistro {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)]$Valor,
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')][string]$Tipo = 'DWord',
        [string]$Motivo = '',
        [switch]$Simular
    )

    $actual = $null
    try { $actual = (Get-ItemProperty -Path $Ruta -Name $Nombre -ErrorAction Stop).$Nombre } catch { }

    if ($null -ne $actual -and "$actual" -eq "$Valor") {
        Write-Bitacora "already set: $Nombre = $Valor" 'INFO'
        return $true
    }

    $desc = "$Ruta :: $Nombre = $Valor (before: $(if($null -eq $actual){'<not set>'}else{$actual}))"
    if ($Motivo) { $desc += "  -- $Motivo" }

    if ($Simular) { Write-Bitacora "DRY RUN -> $desc" 'DRYRUN'; return $true }

    try {
        if (-not (Test-Path $Ruta)) { New-Item -Path $Ruta -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Ruta -Name $Nombre -Value $Valor -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Bitacora "FAILED to write $Nombre : $($_.Exception.Message)" 'ERROR'
        return $false
    }

    # Read back. This is what separates "I think I did it" from "I did it".
    $comprobado = $null
    try { $comprobado = (Get-ItemProperty -Path $Ruta -Name $Nombre -ErrorAction Stop).$Nombre } catch { }
    if ("$comprobado" -eq "$Valor") {
        Write-Bitacora "applied: $desc" 'CHANGE'
        return $true
    }
    Write-Bitacora "SILENTLY REJECTED (probably Tamper Protection): $Nombre" 'WARN'
    return $false
}

function Set-EstadoServicio {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [ValidateSet('Disabled','Manual','Automatic')][string]$Arranque,
        [switch]$Detener,
        [string]$Motivo = '',
        [switch]$Simular
    )

    # Hard guard: some services are never touched.
    $intocables = @('Dhcp','Dnscache','nsi','NlaSvc','netprofm','WlanSvc','Wcmsvc',
                    'RpcSs','DcomLaunch','RpcEptMapper','BFE','mpssvc','WinDefend',
                    'WdNisSvc','SecurityHealthService','wuauserv','CryptSvc','LSM')
    if ($intocables -contains $Nombre) {
        Write-Bitacora "BLOCKED BY DENYLIST: service $Nombre is not touched" 'ERROR'
        return $false
    }

    $svc = $null
    try { $svc = Get-Service -Name $Nombre -ErrorAction Stop } catch {
        Write-Bitacora "service $Nombre does not exist on this computer" 'INFO'
        return $true
    }

    $desc = "service $Nombre -> $Arranque$(if($Detener){' and stopped'}) (before: $($svc.StartType)/$($svc.Status))"
    if ($Motivo) { $desc += "  -- $Motivo" }

    if ($Simular) { Write-Bitacora "DRY RUN -> $desc" 'DRYRUN'; return $true }

    try {
        if ($Detener -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Nombre -Force -ErrorAction Stop
        }
        Set-Service -Name $Nombre -StartupType $Arranque -ErrorAction Stop
        Write-Bitacora "applied: $desc" 'CHANGE'
        return $true
    } catch {
        Write-Bitacora "FAILED on $Nombre : $($_.Exception.Message)" 'WARN'
        return $false
    }
}

# ---------------------------------------------------------------------------
# Firewall rules: query them PROPERLY.
#
# "Get-NetFirewallRule -DisplayName X -Direction Inbound" is a mistake: those
# parameters belong to different sets and PowerShell does not combine them.
# The first version of the hardening did that inside an empty catch, and the
# result was that three whole sweeps returned zero without any warning.
#
# Also, Windows group names in Spanish carry accents and this code is pure
# ASCII, so the comparison ignores accents and case.
# ---------------------------------------------------------------------------

function ConvertTo-SinTildes {
    param([string]$Texto)
    if ([string]::IsNullOrEmpty($Texto)) { return '' }
    $d = $Texto.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    return $sb.ToString().ToLowerInvariant()
}

function Get-ReglasEntrada {
    param(
        [string]$Nombre,
        [string]$Grupo,
        [switch]$SoloHabilitadas,
        [switch]$Refrescar
    )

    if ($Refrescar) { $script:CacheReglas = $null }
    if (-not $script:CacheReglas) {
        try { $script:CacheReglas = @(Get-NetFirewallRule -Direction Inbound -ErrorAction Stop) }
        catch {
            Write-Bitacora "could not read the firewall rules: $($_.Exception.Message)" 'ERROR'
            return @()
        }
    }

    $r = $script:CacheReglas
    if ($SoloHabilitadas) { $r = @($r | Where-Object { $_.Enabled -eq 'True' }) }

    if ($Nombre) {
        $n = ConvertTo-SinTildes $Nombre
        $r = @($r | Where-Object { (ConvertTo-SinTildes $_.DisplayName) -like "*$n*" })
    }
    if ($Grupo) {
        $g = ConvertTo-SinTildes $Grupo
        $r = @($r | Where-Object { $_.DisplayGroup -and (ConvertTo-SinTildes $_.DisplayGroup) -like "*$g*" })
    }

    # HARD GUARD. These rules are never touched, whatever matches:
    # DHCP, DHCPv6 and the ICMP needed for MTU discovery live there.
    # Disabling them leaves you without an IP, and with a pattern that is too broad
    # it would be very easy to take them down by accident.
    # The names are matched in Spanish and English (Windows shows its own language).
    $intocables = @('redes principales','core networking','dhcp','iphttps')
    $r = @($r | Where-Object {
        $dg = ConvertTo-SinTildes $_.DisplayGroup
        $dn = ConvertTo-SinTildes $_.DisplayName
        $malo = $false
        foreach ($i in $intocables) { if ($dg -like "*$i*" -or $dn -like "*$i*") { $malo = $true; break } }
        -not $malo
    })

    return $r
}

# ---------------------------------------------------------------------------
# Backup. If this fails, nothing is touched.
# ---------------------------------------------------------------------------

function Backup-EstadoSistema {
    param([switch]$Simular)

    $carpeta = Join-Path $script:DirResp $script:Sello
    Write-Titulo "BACKUP -> $carpeta"

    if ($Simular) {
        Write-Bitacora 'DRY RUN: firewall, registry and service state would be exported' 'DRYRUN'
        return $carpeta
    }

    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    $ok = $true

    # 1) Full firewall. Restores the EXACT rules.
    $wfw = Join-Path $carpeta 'firewall.wfw'
    $salida = & netsh.exe advfirewall export "$wfw" 2>&1
    if ((Test-Path $wfw) -and ((Get-Item $wfw).Length -gt 0)) {
        Write-Bitacora "firewall exported ($([math]::Round((Get-Item $wfw).Length/1KB)) KB)" 'OK'
    } else {
        Write-Bitacora "FAILED to export the firewall: $salida" 'ERROR'
        $ok = $false
    }

    # 2) Registry keys that will be touched.
    $claves = @{
        'system-policies'     = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        'datacollection-pol'  = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        'lsa'                 = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'
        'ci-config'           = 'HKLM\SYSTEM\CurrentControlSet\Control\CI'
        'dnsclient'           = 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
        'netbt'               = 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
        'tcpip-ifaces'        = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
        'user-explorer'       = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        'wsh'                 = 'HKLM\SOFTWARE\Microsoft\Windows Script Host\Settings'
        'consentstore'        = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
        'systemrestore'       = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    }
    foreach ($k in $claves.Keys) {
        $destino = Join-Path $carpeta "$k.reg"
        & reg.exe export $claves[$k] "$destino" /y > $null 2>&1
        if (Test-Path $destino) { Write-Bitacora "registry saved: $k" 'OK' }
        else { Write-Bitacora "key does not exist (normal): $k" 'INFO' }
    }

    # 3) Service and network state, as JSON.
    $estado = [ordered]@{
        sello      = $script:Sello
        servicios  = @(Get-Service | Select-Object Name, StartType, Status)
        perfiles   = @(Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogBlocked, LogFileName)
        dns        = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses)
        adaptador  = @(Get-NetAdapter | Select-Object Name, InterfaceIndex, Status, MacAddress)
        netbios    = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | Select-Object Description, SettingID, TcpipNetbiosOptions)
    }
    try {
        $estado | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $carpeta 'state.json') -Encoding UTF8
        Write-Bitacora 'service and network state saved' 'OK'
    } catch {
        Write-Bitacora "FAILED to save the state: $($_.Exception.Message)" 'ERROR'
        $ok = $false
    }

    # 4) Restore point. Windows limits it to one every 24h; the limit is lifted.
    #    Enable-ComputerRestore and Checkpoint-Computer do NOT exist in PowerShell 7,
    #    so this must go through Windows PowerShell 5.1.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
                      -Nombre 'SystemRestorePointCreationFrequency' -Valor 0 -Motivo 'allow several points per day' | Out-Null
    $ordenSR = "Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop; " +
               "Checkpoint-Computer -Description 'Sentinel $script:Sello' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; " +
               "'POINT-OK'"
    $resSR = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $ordenSR 2>&1
    if ("$resSR" -match 'POINT-OK') {
        Write-Bitacora 'restore point created' 'OK'
    } else {
        Write-Bitacora "restore point not created: $resSR" 'WARN'
        Write-Bitacora 'the firewall and registry backup still exists, which is what matters most' 'INFO'
    }

    # 5) The emergency script, self-contained. It depends neither on this file
    #    nor on anything else: if everything else breaks, this keeps working.
    $emerg = Join-Path $carpeta 'EMERGENCY-restore-network.ps1'
    $cuerpo = @"
# Emergency reverter. Right-click -> Run with PowerShell (as admin).
# Restores the firewall and network services to the state of $($script:Sello).
#
# -Auto is used by the scheduled task and the code that calls it automatically. Without
# that parameter the script waits for a key at the end, which would hang both the task
# (it runs as SYSTEM, without a console) and the hardening script itself.
param([switch]`$Auto)

Write-Host 'Restoring firewall...' -ForegroundColor Yellow
netsh advfirewall reset
netsh advfirewall import "$wfw"
netsh advfirewall set allprofiles state on
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
Write-Host 'Re-enabling network services...' -ForegroundColor Yellow
foreach (`$s in 'Dhcp','Dnscache','nsi','NlaSvc','netprofm','WlanSvc','Wcmsvc','BFE','mpssvc') {
    try { Set-Service -Name `$s -StartupType Automatic -ErrorAction Stop; Start-Service -Name `$s -ErrorAction SilentlyContinue } catch { }
}
ipconfig /flushdns | Out-Null
Write-Host ''
Write-Host 'Done. Checking internet access...' -ForegroundColor Cyan
try { `$null = Resolve-DnsName microsoft.com -ErrorAction Stop; Write-Host '  DNS: OK' -ForegroundColor Green } catch { Write-Host '  DNS: FAIL' -ForegroundColor Red }
`$hay = `$false
foreach (`$u in 'https://1.1.1.1/','https://www.msftconnecttest.com/connecttest.txt') {
    try { `$null = Invoke-WebRequest `$u -UseBasicParsing -TimeoutSec 10; `$hay = `$true; break } catch { }
}
if (-not `$hay) {
    foreach (`$h in '1.1.1.1','8.8.8.8') {
        try { `$t = New-Object System.Net.Sockets.TcpClient; if (`$t.ConnectAsync(`$h,443).Wait(4000) -and `$t.Connected) { `$hay = `$true }; `$t.Close(); if (`$hay) { break } } catch { }
    }
}
if (`$hay) { Write-Host '  HTTPS: OK' -ForegroundColor Green } else { Write-Host '  HTTPS: FAIL' -ForegroundColor Red }
Write-Host ''
if (-not `$Auto) { Read-Host 'Press Enter to close' }
"@
    Set-Content -Path $emerg -Value $cuerpo -Encoding UTF8
    Write-Bitacora "emergency reverter ready: $emerg" 'OK'

    if (-not $ok) {
        Write-Bitacora 'THE BACKUP IS NOT COMPLETE. Aborting: no jumping without a safety net.' 'ERROR'
        throw 'Incomplete backup'
    }

    Set-Content -Path (Join-Path $script:DirResp 'LATEST.txt') -Value $carpeta -Encoding UTF8
    return $carpeta
}

# ---------------------------------------------------------------------------
# Connectivity check. Runs after EVERY layer that touches the network.
# ---------------------------------------------------------------------------

function Test-Conectividad {
    param([switch]$Silencioso)

    $r = [ordered]@{}

    # Adapter up with an IP
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
              Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' }
        $r['adapter'] = [bool]$ip
    } catch { $r['adapter'] = $false }

    # Gateway. Ping through .NET instead of Test-Connection: that cmdlet's
    # parameters changed between PowerShell 5.1 and 7.
    try {
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
               Sort-Object RouteMetric | Select-Object -First 1).NextHop
        if ($gw -and $gw -ne '0.0.0.0') {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $r['gateway'] = ($ping.Send($gw, 2500).Status -eq 'Success')
        } else { $r['gateway'] = $false }
    } catch { $r['gateway'] = $false }

    # Name resolution: two different domains in case one is down
    $dns = $false
    foreach ($d in 'microsoft.com','cloudflare.com') {
        try { $null = Resolve-DnsName -Name $d -Type A -ErrorAction Stop; $dns = $true; break } catch { }
    }
    $r['dns'] = $dns

    # HTTPS access. Three independent targets and, if all three fail, a raw
    # TCP connection to 443.
    #
    # Why the last resort: on other people's networks with TLS inspection,
    # Invoke-WebRequest fails with an SSL error even though access works
    # perfectly. Without this check we would get a false negative, and a false
    # negative here makes the script revert layers that were fine.
    $https = $false
    foreach ($u in 'https://1.1.1.1/','https://www.msftconnecttest.com/connecttest.txt','https://dns.google/') {
        try { $null = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop; $https = $true; break } catch { }
    }
    if (-not $https) {
        foreach ($h in @('1.1.1.1','8.8.8.8','9.9.9.9')) {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $conectado = $tcp.ConnectAsync($h, 443).Wait(4000)
                if ($conectado -and $tcp.Connected) { $https = $true }
                $tcp.Close()
                if ($https) { break }
            } catch { }
        }
        if ($https) { Write-Bitacora '  (HTTPS verified by raw TCP: there is access, but something inspects TLS)' 'INFO' }
    }
    $r['https'] = $https

    # Your own services listening locally (name = port). Add yours.
    $suyos = @{}
    foreach ($n in $suyos.Keys) {
        $p = $suyos[$n]
        $vivo = $null -ne (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
        $r["local-$n"] = $vivo
    }

    $critico = $r['adapter'] -and $r['dns'] -and $r['https']

    if (-not $Silencioso) {
        foreach ($k in $r.Keys) {
            $v = $r[$k]
            $etiq = if ($v) { 'OK  ' } else { 'FAIL' }
            $niv  = if ($v) { 'OK' } elseif ($k -like 'local-*' -or $k -eq 'gateway') { 'INFO' } else { 'ERROR' }
            Write-Bitacora ("  {0,-18} {1}" -f $k, $etiq) $niv
        }
    }

    return [pscustomobject]@{ Detalle = $r; Sano = $critico }
}

# ---------------------------------------------------------------------------
# Dead man's switch.
#
# Arms a task that, N minutes later, restores the network from the backup.
# If the computer loses its connection, hangs, or you close the console in a
# panic: after N minutes it goes back to the previous state by itself.
# It is the same trick used to change a server firewall over SSH
# without locking yourself out.
# ---------------------------------------------------------------------------

function Enable-Reversor {
    param(
        [Parameter(Mandatory)][string]$ScriptEmergencia,
        [int]$Minutos = 10,
        [switch]$Simular
    )

    if ($Simular) { Write-Bitacora "DRY RUN: the reverter would be armed for $Minutos minutes" 'DRYRUN'; return $true }

    Disable-Reversor -Silencioso

    $cuando = (Get-Date).AddMinutes($Minutos)
    try {
        # -Auto is mandatory here: the task runs as SYSTEM with no
        # console, so a Read-Host would hang it until the execution
        # limit runs out, without restoring anything.
        $accion  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                     -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptEmergencia`" -Auto"
        $disparo = New-ScheduledTaskTrigger -Once -At $cuando
        $ppal    = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $opts    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        Register-ScheduledTask -TaskName $script:TareaRev -Action $accion -Trigger $disparo `
            -Principal $ppal -Settings $opts -Force -ErrorAction Stop | Out-Null

        Write-Bitacora "REVERTER ARMED: if you do not confirm, at $($cuando.ToString('HH:mm:ss')) the network goes back to the previous state by itself" 'WARN'
        return $true
    } catch {
        Write-Bitacora "COULD NOT ARM THE REVERTER: $($_.Exception.Message)" 'ERROR'
        Write-Bitacora 'Without a reverter no network layers are applied. Aborting.' 'ERROR'
        return $false
    }
}

function Disable-Reversor {
    param([switch]$Silencioso)
    try {
        $t = Get-ScheduledTask -TaskName $script:TareaRev -ErrorAction Stop
        Unregister-ScheduledTask -TaskName $script:TareaRev -Confirm:$false -ErrorAction Stop
        if (-not $Silencioso) { Write-Bitacora 'reverter disarmed: the changes are kept' 'OK' }
    } catch {
        if (-not $Silencioso) { Write-Bitacora 'there was no armed reverter' 'INFO' }
    }
}

function Confirm-Supervivencia {
    <#
        After a network layer is applied, checks that we are still alive and asks
        for human confirmation before disarming the reverter. If something fails, it reverts at once.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptEmergencia,
        [switch]$NoPrompt
    )

    Write-Bitacora 'checking that we still have internet...' 'INFO'
    Start-Sleep -Seconds 3
    $chequeo = Test-Conectividad

    if (-not $chequeo.Sano) {
        Write-Bitacora 'CONNECTIVITY LOST. Reverting NOW without waiting for the reverter.' 'ERROR'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptEmergencia -Auto
        Disable-Reversor
        return $false
    }

    Write-Bitacora 'connectivity intact' 'OK'

    if ($NoPrompt) { Disable-Reversor; return $true }

    Write-Host ''
    Write-Host '  There is still internet. Confirm that everything works for you.' -ForegroundColor Cyan
    Write-Host '  If you do NOT answer, in a few minutes the network goes back to the previous state by itself.' -ForegroundColor Yellow
    $resp = Read-Host '  Type YES to keep the changes'
    if ($resp -match '^\s*(si|s|yes|y)\s*$') {
        Disable-Reversor
        return $true
    }

    Write-Bitacora 'not confirmed: reverting' 'WARN'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptEmergencia -Auto
    Disable-Reversor
    return $false
}

# ---------------------------------------------------------------------------
# Defender: write and read back, because Tamper Protection
# rejects silently.
# ---------------------------------------------------------------------------

function Set-PreferenciaDefender {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)]$Valor,
        [string]$Motivo = '',
        [switch]$Simular
    )

    $antes = $null
    try { $antes = (Get-MpPreference).$Nombre } catch { }
    if ("$antes" -eq "$Valor") { Write-Bitacora "already set: Defender.$Nombre = $Valor" 'INFO'; return $true }

    $desc = "Defender.$Nombre = $Valor (before: $antes)"
    if ($Motivo) { $desc += "  -- $Motivo" }
    if ($Simular) { Write-Bitacora "DRY RUN -> $desc" 'DRYRUN'; return $true }

    $param = @{ $Nombre = $Valor }
    try {
        Set-MpPreference @param -ErrorAction Stop
    } catch {
        Write-Bitacora "FAILED on Defender.$Nombre : $($_.Exception.Message)" 'ERROR'
        return $false
    }

    $despues = $null
    try { $despues = (Get-MpPreference).$Nombre } catch { }
    if ("$despues" -eq "$Valor") { Write-Bitacora "applied: $desc" 'CHANGE'; return $true }

    Write-Bitacora "SILENTLY REJECTED: Defender.$Nombre is still '$despues'. Probable cause: Tamper Protection." 'WARN'
    return $false
}
