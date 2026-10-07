<#
.SYNOPSIS
    Proteccion nivel pelicula. SIN -Apply NO CAMBIA NADA.

.DESCRIPTION
    Todo local y de consumo casi nulo. Nada se manda a un tercero.

      1  dns        Unbound resuelve los nombres en ESTE equipo, preguntando
                    directo a los servidores raiz. Ningun DNS de terceros
                    (Cloudflare, Google, Quad9) recibe tu historial.
      2  stealth     MAC aleatoria en el Wi-Fi (una distinta por red) y el
                    puerto 3240 de usbipd cerrado a la red. La captura de
                    NetPulse no lo necesita: va por tunel SSH local.
      3  stealth-web LibreWolf (Firefox libre, sin telemetria) con el acceso
                    "Browser": ECH, sin fugas WebRTC, anti-huella, sin nube.
                    Al cerrar borra cookies y cache; historial, favoritos y
                    contrasenas se quedan en tu disco para buscar en ellos.
      4  errores    Reports de error en cola LOCAL. Nada se envia solo: tu
                    decides desde el Monitor de confiabilidad si lo mandas.

    No toca la telemetria ni bloquea dominios de Microsoft: activacion,
    Tienda y Windows Update siguen intactas.

.EXAMPLE
    .\Movie-Grade.ps1              Simulacro: comprueba y cuenta que haria.
    .\Movie-Grade.ps1 -Apply     Aplica, con reversor de 10 min en la red.
    .\Movie-Grade.ps1 -Revert    Deja la red y los ajustes como estaban.
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    # Con -Revert: solo DNS, MAC y regla de usbipd. Lo usa el reversor.
    [switch]$NetworkOnly,
    # Sin preguntas. Lo pasa la tarea del reversor, que corre como SYSTEM.
    [switch]$Auto,
    # Solo reescribe la configuracion de Unbound. No toca MAC ni DNS.
    [switch]$DnsOnly,
    [int]$RevertMinutes = 10
)

. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$Simular      = -not ($Apply -or $Revert)
$FichEstado   = Join-Path $script:DirResp 'movie-grade-state.json'
$FichPerfil   = Join-Path $script:DirResp 'pelicula-perfil-wifi.bin'
$FichEmerg    = Join-Path $script:DirResp 'EMERGENCY-movie-grade.ps1'
$DirBuscador    = Join-Path $script:Raiz 'Browser'
$Icono        = Join-Path $DirBuscador 'browser.ico'
$UrlInicio    = "file:///" + ((Join-Path $DirBuscador "home.html") -replace "\\","/")
$Adaptadores  = @('Wi-Fi','Ethernet')
$LibreWolfExe = 'C:\Program Files\LibreWolf\librewolf.exe'
$Overrides    = Join-Path $env:USERPROFILE '.librewolf\librewolf.overrides.cfg'
$Marca        = '// Nivel-Pelicula'

$ClaveWer = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
$ValoresWer = @(
    @($ClaveWer,               'DontSendAdditionalData',  1),
    @($ClaveWer,               'ForceQueue',              1),
    @("$ClaveWer\Consent",     'DefaultConsent',          1),
    @("$ClaveWer\Consent",     'DefaultOverrideBehavior', 1),
    @("$ClaveWer\LocalDumps",  'DumpCount',               10),
    @("$ClaveWer\LocalDumps",  'DumpType',                1)
)

if (-not $Simular) {
    $pasar = @()
    if ($Apply)  { $pasar += '-Apply' }
    if ($Revert) { $pasar += '-Revert' }
    if ($NetworkOnly)  { $pasar += '-NetworkOnly' }
    if ($Auto)     { $pasar += '-Auto' }
    if ($DnsOnly)  { $pasar += '-DnsOnly' }
    if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos $pasar)) { return }
}

# ===========================================================================
# Utilidades
# ===========================================================================

function Get-Adaptador([string]$Nombre) {
    Get-NetAdapter -Name $Nombre -ErrorAction SilentlyContinue
}

# Lo que hay en el registro es el DNS ESTATICO. Vacio = lo da el DHCP.
function Get-DnsEstatico($Ad, [string]$Pila) {
    $raiz = if ($Pila -eq 'v6') { 'Tcpip6' } else { 'Tcpip' }
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$raiz\Parameters\Interfaces\$($Ad.InterfaceGuid)"
    try { [string](Get-ItemProperty -Path $k -Name NameServer -ErrorAction Stop).NameServer } catch { '' }
}

# "netsh wlan show interfaces" exige el permiso de ubicacion, que el blindaje
# cierra. Se cruza el nombre de la red (NLA, que a veces lleva " 2" detras)
# con la lista de perfiles, que se lee sin ese permiso.
function Get-PerfilWifi {
    $nla = (Get-NetConnectionProfile -InterfaceAlias 'Wi-Fi' -ErrorAction SilentlyContinue).Name
    if (-not $nla) { return $null }
    $perfiles = @()
    foreach ($l in (& netsh.exe wlan show profiles)) {
        if ($l -match '^\s*(Perfil|Profile)[^:]*:\s*(.+)$') { $perfiles += $matches[2].Trim() }
    }
    if ($perfiles -contains $nla) { return $nla }
    $candidatos = @($perfiles | Where-Object { $nla -match ('^' + [regex]::Escape($_) + ' \d+$') } |
                  Sort-Object Length -Descending)
    if ($candidatos.Count) { return $candidatos[0] }
    return $null
}

function Get-Winget {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $p) { return $p }
    return $null
}

function Invoke-Winget([string]$Verbo, [string]$Id) {
    $wg = Get-Winget
    if (-not $wg) { Write-Bitacora 'winget no esta disponible' 'ERROR'; return }
    Write-Bitacora "winget $Verbo $Id (puede tardar un minuto)..." 'INFO'
    & $wg $Verbo --id $Id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
}

function Get-Unbound {
    $svc = Get-CimInstance Win32_Service -Filter "Name='unbound'" -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    $exe = if ($svc.PathName -match '^"([^"]+)"') { $matches[1] } else { ($svc.PathName -split ' ')[0] }
    $dir = Split-Path $exe -Parent
    $conf = $null
    try { $conf = (Get-ItemProperty 'HKLM:\SOFTWARE\Unbound' -Name ConfigFile -ErrorAction Stop).ConfigFile } catch { }
    if (-not $conf) { $conf = Join-Path $dir 'service.conf' }
    return [pscustomobject]@{ Dir = $dir; Conf = $conf; Exe = $exe }
}

function Test-Unbound {
    for ($i = 0; $i -lt 8; $i++) {
        foreach ($d in 'nlnetlabs.nl','microsoft.com') {
            try {
                $r = Resolve-DnsName -Name $d -Type A -Server 127.0.0.1 -DnsOnly -ErrorAction Stop
                if ($r) { return $true }
            } catch { }
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Protect-Texto([string]$Texto) {
    Add-Type -AssemblyName System.Security
    $b = [Text.Encoding]::UTF8.GetBytes($Texto)
    # LocalMachine: el reversor corre como SYSTEM y tiene que poder leerlo.
    return [Security.Cryptography.ProtectedData]::Protect($b, $null, 'LocalMachine')
}

function Unprotect-Texto([byte[]]$Bytes) {
    Add-Type -AssemblyName System.Security
    $b = [Security.Cryptography.ProtectedData]::Unprotect($Bytes, $null, 'LocalMachine')
    return [Text.Encoding]::UTF8.GetString($b)
}

function Wait-Wifi([int]$Segundos = 30) {
    $fin = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $fin) {
        $ad = Get-Adaptador 'Wi-Fi'
        if ($ad -and $ad.Status -eq 'Up') {
            $ip = Get-NetIPAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -notlike '169.254.*' }
            if ($ip) { return $true }
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

# ===========================================================================
# Backup del estado original. Se toma UNA vez: si ya existe, se conserva,
# para que volver a aplicar no pise el estado de antes con el ya cambiado.
# ===========================================================================

function Save-Estado {
    if (Test-Path $FichEstado) {
        Write-Bitacora "respaldo original conservado: $FichEstado" 'INFO'
        return
    }
    $e = [ordered]@{ fecha = (Get-Date).ToString('s'); dns = @(); usbipd = @(); wer = @(); perfilWifi = $null; overridesPrevio = $false }

    foreach ($n in $Adaptadores) {
        $ad = Get-Adaptador $n
        if (-not $ad) { continue }
        $e.dns += [ordered]@{ nombre = $n; v4 = (Get-DnsEstatico $ad 'v4'); v6 = (Get-DnsEstatico $ad 'v6') }
    }
    Get-NetFirewallRule -DisplayName 'usbipd' -ErrorAction SilentlyContinue | ForEach-Object {
        $e.usbipd += [ordered]@{ nombre = $_.Name; activa = [string]$_.Enabled }
    }
    foreach ($v in $ValoresWer) {
        $actual = $null
        try { $actual = (Get-ItemProperty -Path $v[0] -Name $v[1] -ErrorAction Stop).($v[1]) } catch { }
        $e.wer += [ordered]@{ ruta = $v[0]; nombre = $v[1]; valor = $actual }
    }

    # Perfil Wi-Fi tal cual, cifrado con DPAPI: lleva la clave de tu red.
    $perfil = Get-PerfilWifi
    if ($perfil) {
        $tmp = Join-Path $env:TEMP ("pel-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            & netsh.exe wlan export profile name="$perfil" key=clear folder="$tmp" | Out-Null
            $xml = Get-ChildItem $tmp -Filter *.xml | Select-Object -First 1
            if ($xml) {
                [IO.File]::WriteAllBytes($FichPerfil, (Protect-Texto (Get-Content $xml.FullName -Raw)))
                $e.perfilWifi = $perfil
            }
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    if (Test-Path $Overrides) {
        Copy-Item $Overrides "$Overrides.antes-$($script:Sello)" -Force
        $e.overridesPrevio = $true
    }

    $e | ConvertTo-Json -Depth 5 | Set-Content -Path $FichEstado -Encoding UTF8
    Write-Bitacora "estado original respaldado en $FichEstado" 'OK'
}

function Write-ScriptEmergencia {
    $contenido = @"
# Generado por Movie-Grade.ps1. Lo lanza el reversor si no confirmas.
param([switch]`$Auto)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -Revert -NetworkOnly -Auto
"@
    Set-Content -Path $FichEmerg -Value $contenido -Encoding UTF8
}

# ===========================================================================
# 1  DNS local con Unbound
# ===========================================================================

function Install-DnsLocal {
    Write-Titulo 'DNS RESUELTO EN ESTE EQUIPO (Unbound)'

    $u = Get-Unbound
    if (-not $u) { Invoke-Winget 'install' 'NLnetLabs.Unbound'; $u = Get-Unbound }
    if (-not $u) { Write-Bitacora 'Unbound no quedo instalado; el DNS no se toca' 'ERROR'; return $false }
    Write-Bitacora "Unbound en $($u.Dir)" 'OK'

    # Ancla de confianza de la raiz (DNSSEC). Se baja una vez de la IANA.
    $clave = Join-Path $u.Dir 'root.key'
    $anchor = Join-Path $u.Dir 'unbound-anchor.exe'
    if ((Test-Path $anchor) -and -not (Test-Path $clave)) {
        & $anchor -a $clave 2>&1 | Out-Null
    }
    $lineaDnssec = if (Test-Path $clave) {
        '    auto-trust-anchor-file: "' + ($clave -replace '\\','/') + '"'
    } else {
        Write-Bitacora 'sin ancla DNSSEC: resuelve igual, pero sin validar firmas' 'WARN'
        '    # sin ancla DNSSEC disponible'
    }

    if ((Test-Path $u.Conf) -and -not (Test-Path "$($u.Conf).original")) {
        Copy-Item $u.Conf "$($u.Conf).original" -Force
    }

    $conf = @"
# Nivel-Pelicula: resolutor local. Solo atiende a este equipo.
# Pregunta directo a los servidores raiz: ningun DNS de terceros ve tu historial.
server:
    verbosity: 0
    interface: 127.0.0.1
    interface: ::1
    port: 53
    access-control: 0.0.0.0/0 refuse
    access-control: ::0/0 refuse
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    num-threads: 1
    msg-cache-size: 8m
    rrset-cache-size: 16m
    prefetch: yes
    serve-expired: yes
    serve-expired-ttl: 86400
    qname-minimisation: yes
    aggressive-nsec: yes
    minimal-responses: yes
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-below-nxdomain: yes
    use-caps-for-id: no
    do-ip6: yes
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
    # La sonda de internet de Windows espera una IPv6 privada (fd3e:...) para
    # este dominio. Sin esta excepcion Windows cree que no hay internet y
    # reinicia el driver del Wi-Fi cada poco.
    private-domain: "msftncsi.com"
$lineaDnssec
"@
    Set-Content -Path $u.Conf -Value $conf -Encoding ASCII

    $check = Join-Path $u.Dir 'unbound-checkconf.exe'
    if (Test-Path $check) {
        $salida = & $check $u.Conf 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Bitacora "configuracion rechazada: $salida" 'ERROR'
            if (Test-Path "$($u.Conf).original") { Copy-Item "$($u.Conf).original" $u.Conf -Force }
            return $false
        }
        Write-Bitacora 'configuracion validada por unbound-checkconf' 'OK'
    }

    Set-Service -Name unbound -StartupType Automatic
    & sc.exe failure unbound reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    Restart-Service -Name unbound -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (-not (Test-Unbound)) {
        Write-Bitacora 'Unbound no responde en 127.0.0.1; el DNS del equipo NO se cambia' 'ERROR'
        Stop-Service unbound -Force -ErrorAction SilentlyContinue
        Set-Service unbound -StartupType Manual
        return $false
    }
    Write-Bitacora 'Unbound resuelve en local' 'OK'
    return $true
}

function Set-DnsLocal {
    foreach ($n in $Adaptadores) {
        $ad = Get-Adaptador $n
        if (-not $ad) { continue }
        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses @('127.0.0.1','::1')
        Write-Bitacora "DNS de '$n' -> 127.0.0.1 y ::1 (Unbound)" 'CHANGE'
    }
    & ipconfig.exe /flushdns | Out-Null
}

# ===========================================================================
# 2  Sigilo en la red: MAC aleatoria y usbipd cerrado
# ===========================================================================

function Set-MacAleatoria {
    # El driver Intel AX201 no expone "NetworkAddress", asi que se usa la
    # aleatorizacion nativa de Windows, escrita en el perfil de la red:
    # una MAC inventada y estable para esa red.
    $perfil = Get-PerfilWifi
    if (-not $perfil) { Write-Bitacora 'Wi-Fi sin conectar: MAC sin tocar' 'INFO'; return }

    $tmp = Join-Path $env:TEMP ("pel-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        & netsh.exe wlan export profile name="$perfil" key=clear folder="$tmp" | Out-Null
        $f = Get-ChildItem $tmp -Filter *.xml | Select-Object -First 1
        if (-not $f) { Write-Bitacora "no se pudo exportar el perfil '$perfil'" 'WARN'; return }

        [xml]$x = Get-Content $f.FullName -Raw
        $ns = 'http://www.microsoft.com/networking/WLAN/profile/v3'
        $previo = @($x.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'MacRandomization' })
        foreach ($p in $previo) { [void]$x.DocumentElement.RemoveChild($p) }
        $m  = $x.CreateElement('MacRandomization', $ns)
        $en = $x.CreateElement('enableRandomization', $ns); $en.InnerText = 'true'
        $sd = $x.CreateElement('randomizationSeed', $ns);   $sd.InnerText = [string](Get-Random -Minimum 1 -Maximum 2147483647)
        [void]$m.AppendChild($en); [void]$m.AppendChild($sd)
        [void]$x.DocumentElement.AppendChild($m)
        $x.Save($f.FullName)

        $antes = (Get-Adaptador 'Wi-Fi').MacAddress
        & netsh.exe wlan add profile filename="$($f.FullName)" user=all | Out-Null
        & netsh.exe wlan disconnect interface="Wi-Fi" | Out-Null
        Start-Sleep -Seconds 2
        & netsh.exe wlan connect name="$perfil" interface="Wi-Fi" | Out-Null
        if (-not (Wait-Wifi 40)) { Write-Bitacora 'el Wi-Fi tarda en volver; lo juzga la comprobacion de conectividad' 'WARN' }
        $despues = (Get-Adaptador 'Wi-Fi').MacAddress
        Write-Bitacora "MAC del Wi-Fi en '$perfil': $antes -> $despues" 'CHANGE'
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Close-Usbipd {
    $r = Get-NetFirewallRule -DisplayName 'usbipd' -ErrorAction SilentlyContinue
    if (-not $r) { Write-Bitacora 'no hay regla de usbipd' 'INFO'; return }
    $r | Disable-NetFirewallRule
    Write-Bitacora 'puerto 3240 (usbipd) cerrado a la red; NetPulse sigue por su tunel local' 'CHANGE'
}

# ===========================================================================
# 3  Navegador: LibreWolf con el acceso "Browser"
# ===========================================================================

function Install-Navegador {
    Write-Titulo 'NAVEGADOR BUSCADOR (LibreWolf)'

    if (Test-Path $LibreWolfExe) { Invoke-Winget 'upgrade' 'LibreWolf.LibreWolf' }
    else                         { Invoke-Winget 'install' 'LibreWolf.LibreWolf' }
    if (-not (Test-Path $LibreWolfExe)) { Write-Bitacora 'LibreWolf no quedo instalado' 'ERROR'; return $false }
    Write-Bitacora 'LibreWolf instalado y al dia' 'OK'

    $cfg = @"
$Marca -- ajustes de Browser. Se puede editar; se relee al abrir el navegador.

// --- DNS: el de este equipo (Unbound), nunca DoH de terceros -------------
defaultPref("network.trr.mode", 5);
defaultPref("network.dns.native_https_query", true);
// ECH: el nombre de la pagina viaja cifrado dentro del saludo TLS
defaultPref("network.dns.echconfig.enabled", true);
defaultPref("network.dns.http3_echconfig.enabled", true);

// --- Pagina de inicio: la smiley animada (archivo local) ----------------
defaultPref("browser.startup.homepage", "$UrlInicio");
defaultPref("browser.startup.page", 1);

// --- Nada a la nube ------------------------------------------------------
defaultPref("identity.fxaccounts.enabled", false);
defaultPref("browser.contentblocking.report.lockwise.enabled", false);
defaultPref("extensions.pocket.enabled", false);
defaultPref("network.captive-portal-service.enabled", false);
defaultPref("network.connectivity-service.enabled", false);
defaultPref("browser.search.suggest.enabled", false);
defaultPref("browser.urlbar.suggest.searches", false);
// Conexiones de fondo que el navegador hace por su cuenta: todas fuera
defaultPref("datareporting.healthreport.uploadEnabled", false);
defaultPref("datareporting.policy.dataSubmissionEnabled", false);
defaultPref("toolkit.telemetry.enabled", false);
defaultPref("app.normandy.enabled", false);
defaultPref("app.shield.optoutstudies.enabled", false);
defaultPref("browser.ping-centre.telemetry", false);
defaultPref("browser.send_pings", false);
defaultPref("beacon.enabled", false);
defaultPref("network.predictor.enabled", false);
defaultPref("browser.region.update.enabled", false);
defaultPref("browser.region.network.url", "");
defaultPref("geo.provider.network.url", "");
defaultPref("browser.topsites.contile.enabled", false);
defaultPref("extensions.getAddons.showPane", false);
defaultPref("extensions.htmlaboutaddons.recommendations.enabled", false);
defaultPref("browser.discovery.enabled", false);
defaultPref("app.update.auto", false);
// Lo que LibreWolf dejo sin tocar. Revisado el 26/09/2026: sin conexion
// abierta con Mozilla, pero se apaga para que no pueda abrirse.
defaultPref("dom.push.enabled", false);
defaultPref("dom.push.connection.enabled", false);
defaultPref("dom.push.serverURL", "");
defaultPref("dom.private-attribution.submission.enabled", false);
defaultPref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
defaultPref("browser.newtabpage.activity-stream.showSponsored", false);
defaultPref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
defaultPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
defaultPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
defaultPref("browser.messaging-system.whatsNewPanel.enabled", false);
defaultPref("messaging-system.rsexperimentloader.enabled", false);
defaultPref("extensions.systemAddon.update.enabled", false);
defaultPref("extensions.systemAddon.update.url", "");
defaultPref("browser.urlbar.quicksuggest.online.available", false);
defaultPref("browser.ml.chat.enabled", false);
defaultPref("browser.ml.linkPreview.enabled", false);
// Se QUEDAN a proposito (proteccion, no espionaje; solo descargan listas):
//   services.settings -> certificados revocados (CRLite), sin OCSP es la unica
//   shavar            -> listas de rastreadores que se bloquean
//   extensions.update -> actualizaciones de uBlock Origin

// --- Sin fugas de IP ni conexiones anticipadas ---------------------------
defaultPref("media.peerconnection.ice.default_address_only", true);
defaultPref("media.peerconnection.ice.no_host", true);
defaultPref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);
defaultPref("network.prefetch-next", false);
defaultPref("network.dns.disablePrefetch", true);
defaultPref("network.http.speculative-parallel-limit", 0);
defaultPref("browser.urlbar.speculativeConnect.enabled", false);
defaultPref("browser.places.speculativeConnect.enabled", false);
// 0 y no 2: el inicio de sesion de Microsoft (Outlook) se rompe con 2. El
// recorte de abajo sigue mandando solo el dominio, nunca la pagina.
defaultPref("network.http.referer.XOriginPolicy", 0);
defaultPref("network.http.referer.XOriginTrimmingPolicy", 2);

// --- Solo HTTPS ----------------------------------------------------------
defaultPref("dom.security.https_only_mode", true);
defaultPref("dom.security.https_only_mode_send_http_background_request", false);

// --- Anti-suplantacion y descargas -------------------------------------
// Direcciones completas y dominios con letras falsas a la vista (phishing)
defaultPref("network.IDN_show_punycode", true);
defaultPref("browser.urlbar.trimURLs", false);
defaultPref("browser.urlbar.trimHttps", false);
// Preguntar siempre donde y que descargar: nada se guarda ni se abre solo
defaultPref("browser.download.useDownloadDir", false);
defaultPref("browser.download.always_ask_before_handling_new_types", true);
defaultPref("browser.download.open_pdf_attachments_inline", true);
// PDF sin JavaScript: un PDF malicioso no ejecuta codigo
defaultPref("pdfjs.enableScripting", false);
// Contrasenas: se rellenan solo cuando tu lo pides, nunca en formularios ocultos
defaultPref("signon.autofillForms", false);
defaultPref("signon.formlessCapture.enabled", false);
defaultPref("signon.privateBrowsingCapture.enabled", false);
defaultPref("network.auth.subresource-http-auth-allow", 1);
// TLS estricto: sin renegociaciones inseguras
defaultPref("security.ssl.require_safe_negotiation", true);
defaultPref("security.ssl.treat_unsafe_negotiation_as_broken", true);
defaultPref("security.tls.enable_0rtt_data", false);
// Sin avisos de notificaciones ni ventanas que se mueven solas
defaultPref("permissions.default.desktop-notification", 2);
defaultPref("dom.disable_window_move_resize", true);
// Extensiones solo desde donde tu las instales
defaultPref("extensions.enabledScopes", 5);
defaultPref("extensions.autoDisableScopes", 15);

// --- Huella: que el navegador parezca uno mas entre millones ------------
// Proteccion de huella completa (todos los objetivos de RFP) salvo dos que
// el pidio o que molestaban: el modo oscuro de las paginas y la hora de
// Colombia (RFP ponia UTC y el correo salia con 5 horas de mas).
defaultPref("privacy.resistFingerprinting", false);
defaultPref("privacy.fingerprintingProtection", true);
defaultPref("privacy.fingerprintingProtection.pbmode", true);
defaultPref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC");
// Todo en oscuro: el navegador y las paginas que tengan modo oscuro
pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
defaultPref("layout.css.prefers-color-scheme.content-override", 0);
defaultPref("browser.theme.content-theme", 0);
defaultPref("browser.theme.toolbar-theme", 0);
defaultPref("ui.systemUsesDarkTheme", 1);
// Sin marco oscuro alrededor de la pagina: la pidio a ancho completo, como Edge.
defaultPref("privacy.resistFingerprinting.letterboxing", false);
defaultPref("webgl.disabled", true);
defaultPref("geo.enabled", false);
defaultPref("dom.battery.enabled", false);
defaultPref("media.eme.enabled", false);
defaultPref("privacy.globalprivacycontrol.enabled", true);

// --- Al cerrar: fuera cookies y cache (el rastro que usan las paginas) ---
// Mientras la ventana esta abierta, cada pagina guarda sus cookies aparte
// (Proteccion total de cookies): ningun rastreador te sigue entre sitios.
// Historial, favoritos y contrasenas se QUEDAN en tu disco para buscar ahi.
defaultPref("places.history.enabled", true);
defaultPref("signon.rememberSignons", true);
// LibreWolf 156 ignora las excepciones al borrar al cerrar y se llevaba las
// sesiones de correo. El borrado lo hace Browser\launch_browser.pyw al abrir
// y al cerrar: todo fuera salvo Google y Microsoft. Probado en una copia.
defaultPref("privacy.sanitize.sanitizeOnShutdown", false);
defaultPref("privacy.clearOnShutdown.cookies", true);
defaultPref("privacy.clearOnShutdown.cache", true);
defaultPref("privacy.clearOnShutdown.offlineApps", true);
defaultPref("privacy.clearOnShutdown.sessions", true);
defaultPref("privacy.clearOnShutdown.history", false);
defaultPref("privacy.clearOnShutdown.downloads", false);
defaultPref("privacy.clearOnShutdown.formdata", false);
defaultPref("privacy.clearOnShutdown.siteSettings", false);
defaultPref("privacy.clearOnShutdown_v2.cookiesAndStorage", true);
defaultPref("browser.contentblocking.category", "strict");
defaultPref("network.cookie.cookieBehavior", 5);
defaultPref("privacy.clearOnShutdown_v2.cache", true);
defaultPref("privacy.clearOnShutdown_v2.historyFormDataAndDownloads", false);
defaultPref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false);
defaultPref("privacy.clearOnShutdown_v2.formdata", false);
defaultPref("privacy.clearOnShutdown_v2.siteSettings", false);
"@
    $dirCfg = Split-Path $Overrides -Parent
    if (-not (Test-Path $dirCfg)) { New-Item -ItemType Directory -Path $dirCfg -Force | Out-Null }
    Set-Content -Path $Overrides -Value $cfg -Encoding UTF8
    Write-Bitacora "ajustes de Browser escritos en $Overrides" 'CHANGE'

    # Accesos directos con el icono propio
    $w = New-Object -ComObject WScript.Shell
    $destinos = @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Browser.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Browser.lnk')
    )
    # El icono abre el lanzador, que borra todo salvo las sesiones de correo
    # antes de abrir y al cerrar. Sin pythonw, abre el navegador directo.
    $lanzador = Join-Path $DirBuscador 'launch_browser.pyw'
    $pyw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
    if (-not $pyw) { $pyw = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\pythonw.exe' }
    foreach ($d in $destinos) {
        $l = $w.CreateShortcut($d)
        if ((Test-Path $pyw) -and (Test-Path $lanzador)) {
            $l.TargetPath = $pyw
            $l.Arguments  = "`"$lanzador`""
        } else {
            $l.TargetPath = $LibreWolfExe
        }
        $l.WorkingDirectory = Split-Path $LibreWolfExe -Parent
        $l.Description      = 'Browser: navegador sin rastro'
        if (Test-Path $Icono) { $l.IconLocation = "$Icono,0" }
        $l.Save()
    }
    $imp = $w.CreateShortcut((Join-Path $DirBuscador 'Importar de Edge.lnk'))
    $imp.TargetPath   = $LibreWolfExe
    $imp.Arguments    = '-migration'
    $imp.IconLocation = "$Icono,0"
    $imp.Save()
    Write-Bitacora 'acceso "Browser" creado en el Escritorio y en Inicio' 'CHANGE'
    return $true
}

# ===========================================================================
# 4  Reports de error: en cola local, nada se envia solo
# ===========================================================================

function Set-ErroresLocales {
    Write-Titulo 'INFORMES DE ERROR EN LOCAL'
    foreach ($v in $ValoresWer) {
        Set-ValorRegistro -Ruta $v[0] -Nombre $v[1] -Valor $v[2] | Out-Null
    }
    Write-Bitacora 'los informes quedan en cola en tu equipo; se envian solo si tu lo pides' 'OK'
    Write-Bitacora 'verlos y mandarlos a Microsoft: VER MIS INFORMES DE ERRORES.bat' 'INFO'
}

# ===========================================================================
# Reversion
# ===========================================================================

function Restore-Red {
    Write-Titulo 'DEVOLVIENDO LA RED A SU ESTADO ORIGINAL'
    if (-not (Test-Path $FichEstado)) { Write-Bitacora 'no hay respaldo: nada que revertir' 'WARN'; return }
    $e = Get-Content $FichEstado -Raw | ConvertFrom-Json

    foreach ($d in @($e.dns)) {
        $ad = Get-Adaptador $d.nombre
        if (-not $ad) { continue }
        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ResetServerAddresses
        $lista = @()
        foreach ($x in @($d.v4, $d.v6)) { if ($x) { $lista += @($x -split '[ ,;]+' | Where-Object { $_ }) } }
        if ($lista.Count) { Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $lista }
        Write-Bitacora "DNS de '$($d.nombre)' restaurado" 'CHANGE'
    }
    & ipconfig.exe /flushdns | Out-Null

    foreach ($r in @($e.usbipd)) {
        if ($r.activa -eq 'True') { Enable-NetFirewallRule -Name $r.nombre -ErrorAction SilentlyContinue }
    }

    if ($e.perfilWifi -and (Test-Path $FichPerfil)) {
        $tmp = Join-Path $env:TEMP ("pel-" + [guid]::NewGuid().ToString('N') + '.xml')
        try {
            [IO.File]::WriteAllText($tmp, (Unprotect-Texto ([IO.File]::ReadAllBytes($FichPerfil))))
            & netsh.exe wlan add profile filename="$tmp" user=all | Out-Null
            & netsh.exe wlan connect name="$($e.perfilWifi)" interface="Wi-Fi" | Out-Null
            Write-Bitacora "perfil Wi-Fi '$($e.perfilWifi)' restaurado con su MAC real" 'CHANGE'
        } catch {
            Write-Bitacora "perfil Wi-Fi: $($_.Exception.Message)" 'WARN'
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Restore-Resto {
    $e = Get-Content $FichEstado -Raw | ConvertFrom-Json
    if (Get-Service unbound -ErrorAction SilentlyContinue) {
        Stop-Service unbound -Force -ErrorAction SilentlyContinue
        Set-Service unbound -StartupType Disabled
        Write-Bitacora 'Unbound detenido y deshabilitado' 'CHANGE'
    }
    foreach ($w in @($e.wer)) {
        if ($null -eq $w.valor) { Remove-ItemProperty -Path $w.ruta -Name $w.nombre -ErrorAction SilentlyContinue }
        else { Set-ValorRegistro -Ruta $w.ruta -Nombre $w.nombre -Valor $w.valor | Out-Null }
    }
    if ((Test-Path $Overrides) -and ((Get-Content $Overrides -TotalCount 1) -like "$Marca*")) {
        Remove-Item $Overrides -Force
        Write-Bitacora 'ajustes de Browser retirados (LibreWolf queda instalado)' 'CHANGE'
    }
    Rename-Item $FichEstado ("movie-grade-state-reverted-$($script:Sello).json") -ErrorAction SilentlyContinue
    Remove-Item $FichPerfil -Force -ErrorAction SilentlyContinue
}

# ===========================================================================
# Principal
# ===========================================================================

if ($Revert) {
    Restore-Red
    if (-not $NetworkOnly) { Restore-Resto }
    Disable-Reversor -Silencioso
    Write-Bitacora 'reversion terminada' 'OK'
    return
}

if ($Simular) {
    Write-Titulo 'SIMULACRO -- no se cambia nada'
    $u = Get-Unbound
    $ocupado = Get-NetUDPEndpoint -LocalAddress 127.0.0.1 -LocalPort 53 -ErrorAction SilentlyContinue
    Write-Bitacora ("winget:            " + $(if (Get-Winget) { 'si' } else { 'NO' })) 'INFO'
    Write-Bitacora ("Unbound:           " + $(if ($u) { $u.Dir } else { 'se instalaria' })) 'INFO'
    Write-Bitacora ("127.0.0.1:53:      " + $(if ($ocupado -and -not $u) { 'OCUPADO' } else { 'libre' })) 'INFO'
    Write-Bitacora ("LibreWolf:         " + $(if (Test-Path $LibreWolfExe) { 'instalado' } else { 'se instalaria' })) 'INFO'
    Write-Bitacora ("perfil Wi-Fi:      " + $(Get-PerfilWifi)) 'INFO'
    foreach ($n in $Adaptadores) {
        $ad = Get-Adaptador $n
        if ($ad) { Write-Bitacora ("DNS {0,-14} {1}" -f $n, ((Get-DnsClientServerAddress -InterfaceIndex $ad.ifIndex).ServerAddresses -join ', ')) 'INFO' }
    }
    Write-Bitacora 'para aplicar: MOVIE-GRADE PROTECTION.bat' 'INFO'
    return
}

if ($DnsOnly) {
    if (Install-DnsLocal) { Write-Bitacora 'Unbound reconfigurado; la red no se ha tocado' 'OK' }
    return
}

# --- Apply ---------------------------------------------------------------
Write-Titulo 'MOVIE-GRADE PROTECTION'
Save-Estado
Write-ScriptEmergencia

Set-ErroresLocales
$navOk = Install-Navegador
$dnsOk = Install-DnsLocal

Write-Titulo 'RED (reversor armado)'
if (-not (Enable-Reversor -ScriptEmergencia $FichEmerg -Minutos $RevertMinutes)) { return }

if ($dnsOk) { Set-DnsLocal }
Close-Usbipd
Set-MacAleatoria

if (-not (Confirm-Supervivencia -ScriptEmergencia $FichEmerg)) {
    Write-Bitacora 'la red se devolvio a como estaba; lo demas (navegador, errores) queda' 'WARN'
    return
}

Write-Titulo 'LISTO'
if ($dnsOk) { Write-Bitacora 'DNS: lo resuelve tu equipo. Ningun tercero recibe tu historial.' 'OK' }
Write-Bitacora 'Wi-Fi con MAC inventada para esta red; puerto 3240 cerrado.' 'OK'
Write-Bitacora 'Reports de error: en cola local, solo salen si tu lo pides.' 'OK'
if ($navOk) {
    Write-Bitacora 'Abriendo Browser para importar favoritos, historial y contrasenas de Edge...' 'INFO'
    Write-Bitacora 'En la ventana que sale: deja marcado Edge y pulsa Importar. Es solo esta vez.' 'INFO'
    # Por explorer.exe para que el navegador NO se abra como administrador.
    Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$(Join-Path $DirBuscador 'Importar de Edge.lnk')`""
}
