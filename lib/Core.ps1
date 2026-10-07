<#
    Core.ps1 -- funciones comunes del sistema de blindaje.
    Sin acentos a proposito: la consola de Windows los destroza segun la pagina
    de codigos activa, y este codigo tiene que correr igual en PowerShell 5.1
    y en 7.x.

    Nada de lo que hay aqui cambia el sistema por si solo. Son herramientas.
#>

# Nada de StrictMode: este script consulta decenas de propiedades opcionales
# del sistema y StrictMode convertiria cada ausencia legitima en excepcion.

# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------

$script:Raiz      = Split-Path -Parent $PSScriptRoot
$script:DirResp   = Join-Path $Raiz 'Backups'
$script:DirLog    = Join-Path $Raiz 'Logs'
$script:DirBase   = Join-Path $Raiz 'Baseline'
$script:DirInf    = Join-Path $Raiz 'Reports'
$script:DirPerf   = Join-Path $Raiz 'Profiles'
$script:Sello     = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:Log       = Join-Path $DirLog ("sesion-$Sello.log")
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
# Elevacion
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
    Write-Host '  Este script necesita permisos de administrador.' -ForegroundColor Yellow
    Write-Host '  Se va a relanzar elevado. Acepta el aviso de Windows.' -ForegroundColor Yellow
    Write-Host ''

    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $lista = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$Script`"") + $Argumentos
    try {
        Start-Process -FilePath $exe -ArgumentList $lista -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "  No se pudo elevar: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Abre PowerShell como administrador y vuelve a lanzarlo a mano.' -ForegroundColor Red
    }
    return $false
}

# ---------------------------------------------------------------------------
# Registro: escribir y RELEER. La Proteccion contra Manipulaciones de Defender
# rechaza escrituras en silencio; si no releemos, creemos que se aplico algo
# que no se aplico.
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
        Write-Bitacora "ya estaba: $Nombre = $Valor" 'INFO'
        return $true
    }

    $desc = "$Ruta :: $Nombre = $Valor (antes: $(if($null -eq $actual){'<sin definir>'}else{$actual}))"
    if ($Motivo) { $desc += "  -- $Motivo" }

    if ($Simular) { Write-Bitacora "SIMULACRO -> $desc" 'DRYRUN'; return $true }

    try {
        if (-not (Test-Path $Ruta)) { New-Item -Path $Ruta -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Ruta -Name $Nombre -Value $Valor -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Bitacora "FALLO al escribir $Nombre : $($_.Exception.Message)" 'ERROR'
        return $false
    }

    # Releer. Esto es lo que separa "creo que lo hice" de "lo hice".
    $comprobado = $null
    try { $comprobado = (Get-ItemProperty -Path $Ruta -Name $Nombre -ErrorAction Stop).$Nombre } catch { }
    if ("$comprobado" -eq "$Valor") {
        Write-Bitacora "aplicado: $desc" 'CHANGE'
        return $true
    }
    Write-Bitacora "RECHAZADO en silencio (probable Proteccion contra Manipulaciones): $Nombre" 'WARN'
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

    # Guardia dura: hay servicios que jamas se tocan.
    $intocables = @('Dhcp','Dnscache','nsi','NlaSvc','netprofm','WlanSvc','Wcmsvc',
                    'RpcSs','DcomLaunch','RpcEptMapper','BFE','mpssvc','WinDefend',
                    'WdNisSvc','SecurityHealthService','wuauserv','CryptSvc','LSM')
    if ($intocables -contains $Nombre) {
        Write-Bitacora "BLOQUEADO POR LISTA NEGRA: no se toca el servicio $Nombre" 'ERROR'
        return $false
    }

    $svc = $null
    try { $svc = Get-Service -Name $Nombre -ErrorAction Stop } catch {
        Write-Bitacora "servicio $Nombre no existe en este equipo" 'INFO'
        return $true
    }

    $desc = "servicio $Nombre -> $Arranque$(if($Detener){' y detenido'}) (antes: $($svc.StartType)/$($svc.Status))"
    if ($Motivo) { $desc += "  -- $Motivo" }

    if ($Simular) { Write-Bitacora "SIMULACRO -> $desc" 'DRYRUN'; return $true }

    try {
        if ($Detener -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Nombre -Force -ErrorAction Stop
        }
        Set-Service -Name $Nombre -StartupType $Arranque -ErrorAction Stop
        Write-Bitacora "aplicado: $desc" 'CHANGE'
        return $true
    } catch {
        Write-Bitacora "FALLO en $Nombre : $($_.Exception.Message)" 'WARN'
        return $false
    }
}

# ---------------------------------------------------------------------------
# Reglas de firewall: consultarlas BIEN.
#
# "Get-NetFirewallRule -DisplayName X -Direction Inbound" es un error: esos
# parametros pertenecen a conjuntos distintos y PowerShell no los combina.
# La primera version del blindaje lo hacia asi dentro de un catch vacio, y el
# resultado fue que tres barridos enteros devolvieron cero sin avisar de nada.
#
# Ademas, los nombres de grupo de Windows en espanol llevan tildes
# ("Deteccion de redes" vs "Detección de redes") y el codigo va en ASCII puro,
# asi que la comparacion se hace sin tildes y sin distinguir mayusculas.
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
            Write-Bitacora "no se pudieron leer las reglas de firewall: $($_.Exception.Message)" 'ERROR'
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

    # GUARDIA DURA. Estas reglas no se tocan jamas, coincida lo que coincida:
    # ahi viven DHCP, DHCPv6 y el ICMP que hace falta para descubrir la MTU.
    # Desactivarlas te deja sin IP, y con un patron demasiado amplio seria
    # facilisimo llevarselas por delante sin darse cuenta.
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
# Backup. Si esto falla, no se toca nada.
# ---------------------------------------------------------------------------

function Backup-EstadoSistema {
    param([switch]$Simular)

    $carpeta = Join-Path $script:DirResp $script:Sello
    Write-Titulo "RESPALDO -> $carpeta"

    if ($Simular) {
        Write-Bitacora 'SIMULACRO: se exportaria firewall, registro y estado de servicios' 'DRYRUN'
        return $carpeta
    }

    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    $ok = $true

    # 1) Firewall completo. Restaura las reglas EXACTAS.
    $wfw = Join-Path $carpeta 'firewall.wfw'
    $salida = & netsh.exe advfirewall export "$wfw" 2>&1
    if ((Test-Path $wfw) -and ((Get-Item $wfw).Length -gt 0)) {
        Write-Bitacora "firewall exportado ($([math]::Round((Get-Item $wfw).Length/1KB)) KB)" 'OK'
    } else {
        Write-Bitacora "FALLO exportando el firewall: $salida" 'ERROR'
        $ok = $false
    }

    # 2) Claves del registro que vamos a tocar.
    $claves = @{
        'politicas-sistema'   = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        'datacollection-pol'  = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        'lsa'                 = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'
        'ci-config'           = 'HKLM\SYSTEM\CurrentControlSet\Control\CI'
        'dnsclient'           = 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
        'netbt'               = 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
        'tcpip-ifaces'        = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
        'explorer-usuario'    = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        'wsh'                 = 'HKLM\SOFTWARE\Microsoft\Windows Script Host\Settings'
        'consentstore'        = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
        'systemrestore'       = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    }
    foreach ($k in $claves.Keys) {
        $destino = Join-Path $carpeta "$k.reg"
        & reg.exe export $claves[$k] "$destino" /y > $null 2>&1
        if (Test-Path $destino) { Write-Bitacora "registro guardado: $k" 'OK' }
        else { Write-Bitacora "clave inexistente (normal): $k" 'INFO' }
    }

    # 3) Estado de servicios y red, en JSON.
    $estado = [ordered]@{
        sello      = $script:Sello
        servicios  = @(Get-Service | Select-Object Name, StartType, Status)
        perfiles   = @(Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogBlocked, LogFileName)
        dns        = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses)
        adaptador  = @(Get-NetAdapter | Select-Object Name, InterfaceIndex, Status, MacAddress)
        netbios    = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | Select-Object Description, SettingID, TcpipNetbiosOptions)
    }
    try {
        $estado | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $carpeta 'estado.json') -Encoding UTF8
        Write-Bitacora 'estado de servicios y red guardado' 'OK'
    } catch {
        Write-Bitacora "FALLO guardando el estado: $($_.Exception.Message)" 'ERROR'
        $ok = $false
    }

    # 4) Punto de restauracion. Windows limita a uno cada 24h; lo levantamos.
    #    Enable-ComputerRestore y Checkpoint-Computer NO existen en PowerShell 7,
    #    asi que hay que pasar por Windows PowerShell 5.1 si o si.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
                      -Nombre 'SystemRestorePointCreationFrequency' -Valor 0 -Motivo 'permitir varios puntos al dia' | Out-Null
    $ordenSR = "Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop; " +
               "Checkpoint-Computer -Description 'Sentinel $script:Sello' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; " +
               "'PUNTO-OK'"
    $resSR = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $ordenSR 2>&1
    if ("$resSR" -match 'PUNTO-OK') {
        Write-Bitacora 'punto de restauracion creado' 'OK'
    } else {
        Write-Bitacora "punto de restauracion no creado: $resSR" 'WARN'
        Write-Bitacora 'sigue habiendo respaldo de firewall y registro, que es lo que mas importa' 'INFO'
    }

    # 5) El script de emergencia, autocontenido. No depende de este fichero
    #    ni de nada mas: si todo lo demas se rompe, esto sigue funcionando.
    $emerg = Join-Path $carpeta 'EMERGENCIA-restaurar-red.ps1'
    $cuerpo = @"
# Reversor de emergencia. Doble clic con boton derecho -> Ejecutar con PowerShell (como admin).
# Devuelve el firewall y los servicios de red al estado del $($script:Sello).
#
# -Auto lo usan la tarea programada y el codigo que lo invoca solo. Sin ese
# parametro el script espera una tecla al final, y eso colgaria tanto la tarea
# (que corre como SYSTEM, sin consola) como al propio blindador.
param([switch]`$Auto)

Write-Host 'Restaurando firewall...' -ForegroundColor Yellow
netsh advfirewall reset
netsh advfirewall import "$wfw"
netsh advfirewall set allprofiles state on
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
Write-Host 'Reactivando servicios de red...' -ForegroundColor Yellow
foreach (`$s in 'Dhcp','Dnscache','nsi','NlaSvc','netprofm','WlanSvc','Wcmsvc','BFE','mpssvc') {
    try { Set-Service -Name `$s -StartupType Automatic -ErrorAction Stop; Start-Service -Name `$s -ErrorAction SilentlyContinue } catch { }
}
ipconfig /flushdns | Out-Null
Write-Host ''
Write-Host 'Listo. Comprobando salida a Internet...' -ForegroundColor Cyan
try { `$null = Resolve-DnsName microsoft.com -ErrorAction Stop; Write-Host '  DNS: OK' -ForegroundColor Green } catch { Write-Host '  DNS: FALLA' -ForegroundColor Red }
`$hay = `$false
foreach (`$u in 'https://1.1.1.1/','https://www.msftconnecttest.com/connecttest.txt') {
    try { `$null = Invoke-WebRequest `$u -UseBasicParsing -TimeoutSec 10; `$hay = `$true; break } catch { }
}
if (-not `$hay) {
    foreach (`$h in '1.1.1.1','8.8.8.8') {
        try { `$t = New-Object System.Net.Sockets.TcpClient; if (`$t.ConnectAsync(`$h,443).Wait(4000) -and `$t.Connected) { `$hay = `$true }; `$t.Close(); if (`$hay) { break } } catch { }
    }
}
if (`$hay) { Write-Host '  HTTPS: OK' -ForegroundColor Green } else { Write-Host '  HTTPS: FALLA' -ForegroundColor Red }
Write-Host ''
if (-not `$Auto) { Read-Host 'Pulsa Intro para cerrar' }
"@
    Set-Content -Path $emerg -Value $cuerpo -Encoding UTF8
    Write-Bitacora "reversor de emergencia listo: $emerg" 'OK'

    if (-not $ok) {
        Write-Bitacora 'EL RESPALDO NO ESTA COMPLETO. Se aborta: sin red no se salta.' 'ERROR'
        throw 'Backup incompleto'
    }

    Set-Content -Path (Join-Path $script:DirResp 'ULTIMO.txt') -Value $carpeta -Encoding UTF8
    return $carpeta
}

# ---------------------------------------------------------------------------
# Verificacion de conectividad. Se ejecuta despues de CADA capa que toque red.
# ---------------------------------------------------------------------------

function Test-Conectividad {
    param([switch]$Silencioso)

    $r = [ordered]@{}

    # Adaptador arriba con IP
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
              Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' }
        $r['adaptador'] = [bool]$ip
    } catch { $r['adaptador'] = $false }

    # Puerta de enlace. Ping por .NET en vez de Test-Connection: los parametros
    # de ese cmdlet cambiaron entre PowerShell 5.1 y 7.
    try {
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
               Sort-Object RouteMetric | Select-Object -First 1).NextHop
        if ($gw -and $gw -ne '0.0.0.0') {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $r['pasarela'] = ($ping.Send($gw, 2500).Status -eq 'Success')
        } else { $r['pasarela'] = $false }
    } catch { $r['pasarela'] = $false }

    # Resolucion de nombres: dos dominios distintos por si uno esta caido
    $dns = $false
    foreach ($d in 'microsoft.com','cloudflare.com') {
        try { $null = Resolve-DnsName -Name $d -Type A -ErrorAction Stop; $dns = $true; break } catch { }
    }
    $r['dns'] = $dns

    # Salida HTTPS. Tres destinos independientes y, si los tres fallan, una
    # conexion TCP cruda al 443.
    #
    # El motivo del ultimo recurso: en redes ajenas con inspeccion de TLS,
    # Invoke-WebRequest falla con error de SSL aunque la salida funcione
    # perfectamente. Sin esta comprobacion tendriamos un falso negativo, y un
    # falso negativo aqui hace que el script revierta capas que estaban bien.
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
        if ($https) { Write-Bitacora '  (HTTPS verificado por TCP crudo: hay salida, pero algo inspecciona el TLS)' 'INFO' }
    }
    $r['https'] = $https

    # Servicios propios que escuchan en local (nombre = puerto). Agregue los suyos.
    $suyos = @{}
    foreach ($n in $suyos.Keys) {
        $p = $suyos[$n]
        $vivo = $null -ne (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
        $r["local-$n"] = $vivo
    }

    $critico = $r['adaptador'] -and $r['dns'] -and $r['https']

    if (-not $Silencioso) {
        foreach ($k in $r.Keys) {
            $v = $r[$k]
            $etiq = if ($v) { 'OK  ' } else { 'FALLA' }
            $niv  = if ($v) { 'OK' } elseif ($k -like 'local-*' -or $k -eq 'pasarela') { 'INFO' } else { 'ERROR' }
            Write-Bitacora ("  {0,-18} {1}" -f $k, $etiq) $niv
        }
    }

    return [pscustomobject]@{ Detalle = $r; Sano = $critico }
}

# ---------------------------------------------------------------------------
# Interruptor de hombre muerto.
#
# Arma una tarea que, dentro de N minutos, restaura la red desde el respaldo.
# Si el equipo pierde la conexion, si se cuelga, o si cierras la consola presa
# del panico: a los N minutos vuelve solo al estado anterior.
# Es el mismo truco que se usa para tocar el cortafuegos de un servidor por SSH
# sin quedarse fuera.
# ---------------------------------------------------------------------------

function Enable-Reversor {
    param(
        [Parameter(Mandatory)][string]$ScriptEmergencia,
        [int]$Minutos = 10,
        [switch]$Simular
    )

    if ($Simular) { Write-Bitacora "SIMULACRO: se armaria el reversor a $Minutos minutos" 'DRYRUN'; return $true }

    Disable-Reversor -Silencioso

    $cuando = (Get-Date).AddMinutes($Minutos)
    try {
        # -Auto es obligatorio aqui: la tarea corre como SYSTEM y no tiene
        # consola, asi que un Read-Host la dejaria colgada hasta agotar el
        # limite de ejecucion, sin restaurar nada.
        $accion  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                     -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptEmergencia`" -Auto"
        $disparo = New-ScheduledTaskTrigger -Once -At $cuando
        $ppal    = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $opts    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        Register-ScheduledTask -TaskName $script:TareaRev -Action $accion -Trigger $disparo `
            -Principal $ppal -Settings $opts -Force -ErrorAction Stop | Out-Null

        Write-Bitacora "REVERSOR ARMADO: si no confirmas, a las $($cuando.ToString('HH:mm:ss')) la red vuelve sola al estado anterior" 'WARN'
        return $true
    } catch {
        Write-Bitacora "NO SE PUDO ARMAR EL REVERSOR: $($_.Exception.Message)" 'ERROR'
        Write-Bitacora 'Sin reversor no se aplican capas de red. Se aborta.' 'ERROR'
        return $false
    }
}

function Disable-Reversor {
    param([switch]$Silencioso)
    try {
        $t = Get-ScheduledTask -TaskName $script:TareaRev -ErrorAction Stop
        Unregister-ScheduledTask -TaskName $script:TareaRev -Confirm:$false -ErrorAction Stop
        if (-not $Silencioso) { Write-Bitacora 'reversor desarmado: los cambios quedan firmes' 'OK' }
    } catch {
        if (-not $Silencioso) { Write-Bitacora 'no habia reversor armado' 'INFO' }
    }
}

function Confirm-Supervivencia {
    <#
        Aplicada una capa de red, comprueba que seguimos vivos y pide confirmacion
        humana antes de desarmar el reversor. Si algo falla, revierte en el acto.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptEmergencia,
        [switch]$NoPrompt
    )

    Write-Bitacora 'comprobando que seguimos con Internet...' 'INFO'
    Start-Sleep -Seconds 3
    $chequeo = Test-Conectividad

    if (-not $chequeo.Sano) {
        Write-Bitacora 'CONECTIVIDAD PERDIDA. Revirtiendo AHORA sin esperar al reversor.' 'ERROR'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptEmergencia -Auto
        Disable-Reversor
        return $false
    }

    Write-Bitacora 'conectividad intacta' 'OK'

    if ($NoPrompt) { Disable-Reversor; return $true }

    Write-Host ''
    Write-Host '  Sigue habiendo Internet. Confirma que todo te funciona.' -ForegroundColor Cyan
    Write-Host '  Si NO respondes, en unos minutos la red vuelve sola al estado anterior.' -ForegroundColor Yellow
    $resp = Read-Host '  Escribe SI para dejar los cambios firmes'
    if ($resp -match '^\s*(si|s|yes|y)\s*$') {
        Disable-Reversor
        return $true
    }

    Write-Bitacora 'no confirmado: se revierte' 'WARN'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptEmergencia -Auto
    Disable-Reversor
    return $false
}

# ---------------------------------------------------------------------------
# Defender: escribir y releer, porque la Proteccion contra Manipulaciones
# rechaza en silencio.
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
    if ("$antes" -eq "$Valor") { Write-Bitacora "ya estaba: Defender.$Nombre = $Valor" 'INFO'; return $true }

    $desc = "Defender.$Nombre = $Valor (antes: $antes)"
    if ($Motivo) { $desc += "  -- $Motivo" }
    if ($Simular) { Write-Bitacora "SIMULACRO -> $desc" 'DRYRUN'; return $true }

    $param = @{ $Nombre = $Valor }
    try {
        Set-MpPreference @param -ErrorAction Stop
    } catch {
        Write-Bitacora "FALLO en Defender.$Nombre : $($_.Exception.Message)" 'ERROR'
        return $false
    }

    $despues = $null
    try { $despues = (Get-MpPreference).$Nombre } catch { }
    if ("$despues" -eq "$Valor") { Write-Bitacora "aplicado: $desc" 'CHANGE'; return $true }

    Write-Bitacora "RECHAZADO en silencio: Defender.$Nombre sigue en '$despues'. Causa probable: Proteccion contra Manipulaciones." 'WARN'
    return $false
}
