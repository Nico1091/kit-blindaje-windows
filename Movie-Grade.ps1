<#
.SYNOPSIS
    Movie-grade protection. WITHOUT -Apply IT CHANGES NOTHING.

.DESCRIPTION
    Everything local, with almost no resource use. Nothing is sent to a third party.

      1  dns         Unbound resolves names on THIS computer, asking the root
                     servers directly. No third-party DNS (Cloudflare, Google,
                     Quad9) receives your history.
      2  stealth     Random MAC on the Wi-Fi (a different one per network) and
                     usbipd port 3240 closed to the network.
      3  browser     LibreWolf (free Firefox, no telemetry) with the "Browser"
                     shortcut: ECH, no WebRTC leaks, anti-fingerprinting, no cloud.
                     On close it deletes cookies and cache; history, bookmarks and
                     passwords stay on your disk so you can search them.
      4  errors      Error reports queued LOCALLY. Nothing is sent by itself: you
                     decide from Reliability Monitor (perfmon /rel) whether to send it.

    It does not touch telemetry or block Microsoft domains: activation,
    the Store and Windows Update stay intact.

.EXAMPLE
    .\Movie-Grade.ps1              Dry run: checks and reports what it would do.
    .\Movie-Grade.ps1 -Apply       Applies, with a 10-minute network reverter.
    .\Movie-Grade.ps1 -Revert      Puts the network and settings back as they were.
#>

[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    # With -Revert: only DNS, MAC and the usbipd rule. Used by the reverter.
    [switch]$NetworkOnly,
    # No questions. Passed by the reverter task, which runs as SYSTEM.
    [switch]$Auto,
    # Only rewrites the Unbound configuration. Does not touch MAC or DNS.
    [switch]$DnsOnly,
    [int]$RevertMinutes = 10
)

. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$Simular      = -not ($Apply -or $Revert)
$FichEstado   = Join-Path $script:DirResp 'movie-grade-state.json'
$FichPerfil   = Join-Path $script:DirResp 'movie-grade-wifi-profile.bin'
$FichEmerg    = Join-Path $script:DirResp 'EMERGENCY-movie-grade.ps1'
$DirBuscador    = Join-Path $script:Raiz 'Browser'
$Icono        = Join-Path $DirBuscador 'browser.ico'
$UrlInicio    = "file:///" + ((Join-Path $DirBuscador "home.html") -replace "\\","/")
$Adaptadores  = @('Wi-Fi','Ethernet')
$LibreWolfExe = 'C:\Program Files\LibreWolf\librewolf.exe'
$Overrides    = Join-Path $env:USERPROFILE '.librewolf\librewolf.overrides.cfg'
$Marca        = '// Movie-Grade'

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
# Utilities
# ===========================================================================

function Get-Adaptador([string]$Nombre) {
    Get-NetAdapter -Name $Nombre -ErrorAction SilentlyContinue
}

# What is in the registry is the STATIC DNS. Empty = handed out by DHCP.
function Get-DnsEstatico($Ad, [string]$Pila) {
    $raiz = if ($Pila -eq 'v6') { 'Tcpip6' } else { 'Tcpip' }
    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$raiz\Parameters\Interfaces\$($Ad.InterfaceGuid)"
    try { [string](Get-ItemProperty -Path $k -Name NameServer -ErrorAction Stop).NameServer } catch { '' }
}

# "netsh wlan show interfaces" requires the location permission, which the hardening
# closes. The network name (NLA, which sometimes has " 2" appended) is matched
# against the profile list, which can be read without that permission.
# netsh output is in the language of Windows, hence "Perfil|Profile".
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
    if (-not $wg) { Write-Bitacora 'winget is not available' 'ERROR'; return }
    Write-Bitacora "winget $Verbo $Id (may take a minute)..." 'INFO'
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
    # LocalMachine: the reverter runs as SYSTEM and must be able to read it.
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
# Backup of the original state. Taken ONCE: if it already exists it is kept,
# so applying again does not overwrite the original state with the changed one.
# ===========================================================================

function Save-Estado {
    if (Test-Path $FichEstado) {
        Write-Bitacora "original backup kept: $FichEstado" 'INFO'
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

    # Wi-Fi profile as is, encrypted with DPAPI: it contains your network key.
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
        Copy-Item $Overrides "$Overrides.before-$($script:Sello)" -Force
        $e.overridesPrevio = $true
    }

    $e | ConvertTo-Json -Depth 5 | Set-Content -Path $FichEstado -Encoding UTF8
    Write-Bitacora "original state backed up to $FichEstado" 'OK'
}

function Write-ScriptEmergencia {
    $contenido = @"
# Generated by Movie-Grade.ps1. The reverter runs it if you do not confirm.
param([switch]`$Auto)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -Revert -NetworkOnly -Auto
"@
    Set-Content -Path $FichEmerg -Value $contenido -Encoding UTF8
}

# ===========================================================================
# 1  Local DNS with Unbound
# ===========================================================================

function Install-DnsLocal {
    Write-Titulo 'DNS RESOLVED ON THIS COMPUTER (Unbound)'

    $u = Get-Unbound
    if (-not $u) { Invoke-Winget 'install' 'NLnetLabs.Unbound'; $u = Get-Unbound }
    if (-not $u) { Write-Bitacora 'Unbound did not get installed; DNS is not touched' 'ERROR'; return $false }
    Write-Bitacora "Unbound in $($u.Dir)" 'OK'

    # Root trust anchor (DNSSEC). Downloaded once from IANA.
    $clave = Join-Path $u.Dir 'root.key'
    $anchor = Join-Path $u.Dir 'unbound-anchor.exe'
    if ((Test-Path $anchor) -and -not (Test-Path $clave)) {
        & $anchor -a $clave 2>&1 | Out-Null
    }
    $lineaDnssec = if (Test-Path $clave) {
        '    auto-trust-anchor-file: "' + ($clave -replace '\\','/') + '"'
    } else {
        Write-Bitacora 'no DNSSEC anchor: it still resolves, but without validating signatures' 'WARN'
        '    # no DNSSEC anchor available'
    }

    if ((Test-Path $u.Conf) -and -not (Test-Path "$($u.Conf).original")) {
        Copy-Item $u.Conf "$($u.Conf).original" -Force
    }

    $conf = @"
# Movie-Grade: local resolver. It only serves this computer.
# It asks the root servers directly: no third-party DNS sees your history.
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
    # The Windows internet probe expects a private IPv6 (fd3e:...) for
    # this domain. Without this exception Windows thinks there is no internet and
    # keeps restarting the Wi-Fi driver.
    private-domain: "msftncsi.com"
$lineaDnssec
"@
    Set-Content -Path $u.Conf -Value $conf -Encoding ASCII

    $check = Join-Path $u.Dir 'unbound-checkconf.exe'
    if (Test-Path $check) {
        $salida = & $check $u.Conf 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Bitacora "configuration rejected: $salida" 'ERROR'
            if (Test-Path "$($u.Conf).original") { Copy-Item "$($u.Conf).original" $u.Conf -Force }
            return $false
        }
        Write-Bitacora 'configuration validated by unbound-checkconf' 'OK'
    }

    Set-Service -Name unbound -StartupType Automatic
    & sc.exe failure unbound reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null
    Restart-Service -Name unbound -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (-not (Test-Unbound)) {
        Write-Bitacora 'Unbound does not answer on 127.0.0.1; the computer DNS is NOT changed' 'ERROR'
        Stop-Service unbound -Force -ErrorAction SilentlyContinue
        Set-Service unbound -StartupType Manual
        return $false
    }
    Write-Bitacora 'Unbound resolves locally' 'OK'
    return $true
}

function Set-DnsLocal {
    foreach ($n in $Adaptadores) {
        $ad = Get-Adaptador $n
        if (-not $ad) { continue }
        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses @('127.0.0.1','::1')
        Write-Bitacora "DNS of '$n' -> 127.0.0.1 and ::1 (Unbound)" 'CHANGE'
    }
    & ipconfig.exe /flushdns | Out-Null
}

# ===========================================================================
# 2  Network stealth: random MAC and usbipd closed
# ===========================================================================

function Set-MacAleatoria {
    # Many Wi-Fi drivers (for example Intel AX201) do not expose "NetworkAddress", so the
    # native Windows randomization is used, written into the network profile:
    # an invented MAC that is stable for that network.
    $perfil = Get-PerfilWifi
    if (-not $perfil) { Write-Bitacora 'Wi-Fi not connected: MAC untouched' 'INFO'; return }

    $tmp = Join-Path $env:TEMP ("pel-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        & netsh.exe wlan export profile name="$perfil" key=clear folder="$tmp" | Out-Null
        $f = Get-ChildItem $tmp -Filter *.xml | Select-Object -First 1
        if (-not $f) { Write-Bitacora "could not export the profile '$perfil'" 'WARN'; return }

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
        if (-not (Wait-Wifi 40)) { Write-Bitacora 'the Wi-Fi is slow to come back; the connectivity check will judge it' 'WARN' }
        $despues = (Get-Adaptador 'Wi-Fi').MacAddress
        Write-Bitacora "Wi-Fi MAC on '$perfil': $antes -> $despues" 'CHANGE'
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Close-Usbipd {
    $r = Get-NetFirewallRule -DisplayName 'usbipd' -ErrorAction SilentlyContinue
    if (-not $r) { Write-Bitacora 'there is no usbipd rule' 'INFO'; return }
    $r | Disable-NetFirewallRule
    Write-Bitacora 'port 3240 (usbipd) closed to the network' 'CHANGE'
}

# ===========================================================================
# 3  Browser: LibreWolf with the "Browser" shortcut
# ===========================================================================

function Install-Navegador {
    Write-Titulo 'THE BROWSER (LibreWolf)'

    if (Test-Path $LibreWolfExe) { Invoke-Winget 'upgrade' 'LibreWolf.LibreWolf' }
    else                         { Invoke-Winget 'install' 'LibreWolf.LibreWolf' }
    if (-not (Test-Path $LibreWolfExe)) { Write-Bitacora 'LibreWolf did not get installed' 'ERROR'; return $false }
    Write-Bitacora 'LibreWolf installed and up to date' 'OK'

    $cfg = @"
$Marca -- Browser settings. You can edit it; it is read again when the browser opens.

// --- DNS: this computer's (Unbound), never third-party DoH ---------------
defaultPref("network.trr.mode", 5);
defaultPref("network.dns.native_https_query", true);
// ECH: the site name travels encrypted inside the TLS handshake
defaultPref("network.dns.echconfig.enabled", true);
defaultPref("network.dns.http3_echconfig.enabled", true);

// --- Home page: the animated smiley (local file) ------------------------
defaultPref("browser.startup.homepage", "$UrlInicio");
defaultPref("browser.startup.page", 1);

// --- Nothing to the cloud -----------------------------------------------
defaultPref("identity.fxaccounts.enabled", false);
defaultPref("browser.contentblocking.report.lockwise.enabled", false);
defaultPref("extensions.pocket.enabled", false);
defaultPref("network.captive-portal-service.enabled", false);
defaultPref("network.connectivity-service.enabled", false);
defaultPref("browser.search.suggest.enabled", false);
defaultPref("browser.urlbar.suggest.searches", false);
// Background connections the browser makes on its own: all of them off
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
// What LibreWolf left untouched. Reviewed: no open connection to
// Mozilla, but it is turned off so it cannot open one.
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
// KEPT on purpose (protection, not spying; they only download lists):
//   services.settings -> revoked certificates (CRLite), without OCSP it is the only one
//   shavar            -> lists of trackers that are blocked
//   extensions.update -> uBlock Origin updates

// --- No IP leaks and no speculative connections --------------------------
defaultPref("media.peerconnection.ice.default_address_only", true);
defaultPref("media.peerconnection.ice.no_host", true);
defaultPref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);
defaultPref("network.prefetch-next", false);
defaultPref("network.dns.disablePrefetch", true);
defaultPref("network.http.speculative-parallel-limit", 0);
defaultPref("browser.urlbar.speculativeConnect.enabled", false);
defaultPref("browser.places.speculativeConnect.enabled", false);
// 0 and not 2: Microsoft sign-in (Outlook) breaks with 2. The
// trimming below still sends only the domain, never the page.
defaultPref("network.http.referer.XOriginPolicy", 0);
defaultPref("network.http.referer.XOriginTrimmingPolicy", 2);

// --- HTTPS only ----------------------------------------------------------
defaultPref("dom.security.https_only_mode", true);
defaultPref("dom.security.https_only_mode_send_http_background_request", false);

// --- Anti-spoofing and downloads ---------------------------------------
// Full addresses and lookalike-letter domains visible (phishing)
defaultPref("network.IDN_show_punycode", true);
defaultPref("browser.urlbar.trimURLs", false);
defaultPref("browser.urlbar.trimHttps", false);
// Always ask where and what to download: nothing is saved or opened by itself
defaultPref("browser.download.useDownloadDir", false);
defaultPref("browser.download.always_ask_before_handling_new_types", true);
defaultPref("browser.download.open_pdf_attachments_inline", true);
// PDF without JavaScript: a malicious PDF runs no code
defaultPref("pdfjs.enableScripting", false);
// Passwords: filled only when you ask, never into hidden forms
defaultPref("signon.autofillForms", false);
defaultPref("signon.formlessCapture.enabled", false);
defaultPref("signon.privateBrowsingCapture.enabled", false);
defaultPref("network.auth.subresource-http-auth-allow", 1);
// Strict TLS: no insecure renegotiation
defaultPref("security.ssl.require_safe_negotiation", true);
defaultPref("security.ssl.treat_unsafe_negotiation_as_broken", true);
defaultPref("security.tls.enable_0rtt_data", false);
// No notification prompts and no windows that move by themselves
defaultPref("permissions.default.desktop-notification", 2);
defaultPref("dom.disable_window_move_resize", true);
// Extensions only from where you install them
defaultPref("extensions.enabledScopes", 5);
defaultPref("extensions.autoDisableScopes", 15);

// --- Fingerprint: make the browser look like one among millions ----------
// Full fingerprint protection (all RFP targets) except two that were
// annoying: the pages' dark mode and the local time zone (RFP forced UTC
// and email showed the wrong time).
defaultPref("privacy.resistFingerprinting", false);
defaultPref("privacy.fingerprintingProtection", true);
defaultPref("privacy.fingerprintingProtection.pbmode", true);
defaultPref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CSSPrefersColorScheme,-JSDateTimeUTC");
// Everything dark: the browser and the pages that have a dark mode
pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
defaultPref("layout.css.prefers-color-scheme.content-override", 0);
defaultPref("browser.theme.content-theme", 0);
defaultPref("browser.theme.toolbar-theme", 0);
defaultPref("ui.systemUsesDarkTheme", 1);
// No dark frame around the page: full width, like Edge.
defaultPref("privacy.resistFingerprinting.letterboxing", false);
defaultPref("webgl.disabled", true);
defaultPref("geo.enabled", false);
defaultPref("dom.battery.enabled", false);
defaultPref("media.eme.enabled", false);
defaultPref("privacy.globalprivacycontrol.enabled", true);

// --- On close: cookies and cache gone (the trail pages use) -------------
// While the window is open, each site keeps its cookies apart
// (Total Cookie Protection): no tracker follows you across sites.
// History, bookmarks and passwords STAY on your disk so you can search them.
defaultPref("places.history.enabled", true);
defaultPref("signon.rememberSignons", true);
// LibreWolf 156 ignores the exceptions when clearing on close and wiped the
// email sessions. Clearing is done by Browser\launch_browser.pyw on open
// and on close: everything goes except the domains in CONSERVAR. Tested on a copy.
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
    Write-Bitacora "Browser settings written to $Overrides" 'CHANGE'

    # Shortcuts with the kit's own icon
    $w = New-Object -ComObject WScript.Shell
    $destinos = @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Browser.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Browser.lnk')
    )
    # The icon opens the launcher, which clears everything except the kept sessions
    # before opening and on close. Without pythonw, it opens the browser directly.
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
        $l.Description      = 'Browser: a browser that leaves no trace'
        if (Test-Path $Icono) { $l.IconLocation = "$Icono,0" }
        $l.Save()
    }
    $imp = $w.CreateShortcut((Join-Path $DirBuscador 'Import from Edge.lnk'))
    $imp.TargetPath   = $LibreWolfExe
    $imp.Arguments    = '-migration'
    $imp.IconLocation = "$Icono,0"
    $imp.Save()
    Write-Bitacora '"Browser" shortcut created on the Desktop and in Start' 'CHANGE'
    return $true
}

# ===========================================================================
# 4  Error reports: queued locally, nothing is sent by itself
# ===========================================================================

function Set-ErroresLocales {
    Write-Titulo 'LOCAL ERROR REPORTS'
    foreach ($v in $ValoresWer) {
        Set-ValorRegistro -Ruta $v[0] -Nombre $v[1] -Valor $v[2] | Out-Null
    }
    Write-Bitacora 'reports stay queued on your computer; they are sent only if you ask' 'OK'
    Write-Bitacora 'to see them and send them to Microsoft: run perfmon /rel (Reliability Monitor)' 'INFO'
}

# ===========================================================================
# Revert
# ===========================================================================

function Restore-Red {
    Write-Titulo 'PUTTING THE NETWORK BACK TO ITS ORIGINAL STATE'
    if (-not (Test-Path $FichEstado)) { Write-Bitacora 'there is no backup: nothing to revert' 'WARN'; return }
    $e = Get-Content $FichEstado -Raw | ConvertFrom-Json

    foreach ($d in @($e.dns)) {
        $ad = Get-Adaptador $d.nombre
        if (-not $ad) { continue }
        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ResetServerAddresses
        $lista = @()
        foreach ($x in @($d.v4, $d.v6)) { if ($x) { $lista += @($x -split '[ ,;]+' | Where-Object { $_ }) } }
        if ($lista.Count) { Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $lista }
        Write-Bitacora "DNS of '$($d.nombre)' restored" 'CHANGE'
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
            Write-Bitacora "Wi-Fi profile '$($e.perfilWifi)' restored with its real MAC" 'CHANGE'
        } catch {
            Write-Bitacora "Wi-Fi profile: $($_.Exception.Message)" 'WARN'
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Restore-Resto {
    $e = Get-Content $FichEstado -Raw | ConvertFrom-Json
    if (Get-Service unbound -ErrorAction SilentlyContinue) {
        Stop-Service unbound -Force -ErrorAction SilentlyContinue
        Set-Service unbound -StartupType Disabled
        Write-Bitacora 'Unbound stopped and disabled' 'CHANGE'
    }
    foreach ($w in @($e.wer)) {
        if ($null -eq $w.valor) { Remove-ItemProperty -Path $w.ruta -Name $w.nombre -ErrorAction SilentlyContinue }
        else { Set-ValorRegistro -Ruta $w.ruta -Nombre $w.nombre -Valor $w.valor | Out-Null }
    }
    if ((Test-Path $Overrides) -and ((Get-Content $Overrides -TotalCount 1) -like "$Marca*")) {
        Remove-Item $Overrides -Force
        Write-Bitacora 'Browser settings removed (LibreWolf stays installed)' 'CHANGE'
    }
    Rename-Item $FichEstado ("movie-grade-state-reverted-$($script:Sello).json") -ErrorAction SilentlyContinue
    Remove-Item $FichPerfil -Force -ErrorAction SilentlyContinue
}

# ===========================================================================
# Main
# ===========================================================================

if ($Revert) {
    Restore-Red
    if (-not $NetworkOnly) { Restore-Resto }
    Disable-Reversor -Silencioso
    Write-Bitacora 'revert finished' 'OK'
    return
}

if ($Simular) {
    Write-Titulo 'DRY RUN -- nothing is changed'
    $u = Get-Unbound
    $ocupado = Get-NetUDPEndpoint -LocalAddress 127.0.0.1 -LocalPort 53 -ErrorAction SilentlyContinue
    Write-Bitacora ("winget:            " + $(if (Get-Winget) { 'yes' } else { 'NO' })) 'INFO'
    Write-Bitacora ("Unbound:           " + $(if ($u) { $u.Dir } else { 'would be installed' })) 'INFO'
    Write-Bitacora ("127.0.0.1:53:      " + $(if ($ocupado -and -not $u) { 'BUSY' } else { 'free' })) 'INFO'
    Write-Bitacora ("LibreWolf:         " + $(if (Test-Path $LibreWolfExe) { 'installed' } else { 'would be installed' })) 'INFO'
    Write-Bitacora ("Wi-Fi profile:     " + $(Get-PerfilWifi)) 'INFO'
    foreach ($n in $Adaptadores) {
        $ad = Get-Adaptador $n
        if ($ad) { Write-Bitacora ("DNS {0,-14} {1}" -f $n, ((Get-DnsClientServerAddress -InterfaceIndex $ad.ifIndex).ServerAddresses -join ', ')) 'INFO' }
    }
    Write-Bitacora 'to apply: MOVIE-GRADE PROTECTION.bat' 'INFO'
    return
}

if ($DnsOnly) {
    if (Install-DnsLocal) { Write-Bitacora 'Unbound reconfigured; the network was not touched' 'OK' }
    return
}

# --- Apply ---------------------------------------------------------------
Write-Titulo 'MOVIE-GRADE PROTECTION'
Save-Estado
Write-ScriptEmergencia

Set-ErroresLocales
$navOk = Install-Navegador
$dnsOk = Install-DnsLocal

Write-Titulo 'NETWORK (reverter armed)'
if (-not (Enable-Reversor -ScriptEmergencia $FichEmerg -Minutos $RevertMinutes)) { return }

if ($dnsOk) { Set-DnsLocal }
Close-Usbipd
Set-MacAleatoria

if (-not (Confirm-Supervivencia -ScriptEmergencia $FichEmerg)) {
    Write-Bitacora 'the network was put back as it was; the rest (browser, error reports) stays' 'WARN'
    return
}

Write-Titulo 'DONE'
if ($dnsOk) { Write-Bitacora 'DNS: your computer resolves it. No third party receives your history.' 'OK' }
Write-Bitacora 'Wi-Fi with an invented MAC for this network; port 3240 closed.' 'OK'
Write-Bitacora 'Error reports: queued locally, they only leave if you ask.' 'OK'
if ($navOk) {
    Write-Bitacora 'Opening the Browser to import bookmarks, history and passwords from Edge...' 'INFO'
    Write-Bitacora 'In the window that appears: leave Edge selected and click Import. Only this once.' 'INFO'
    # Through explorer.exe so the browser does NOT open as administrator.
    Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$(Join-Path $DirBuscador 'Import from Edge.lnk')`""
}
