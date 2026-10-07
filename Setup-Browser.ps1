param([switch]$NoPause)
# Gets the whole Browser working in a single pass:
# LibreWolf with the smiley, its settings, Edge disabled and redirected, the Tor
# exit with WebTunnel always on, and the firewall lock.
# Brings together Smiley-Browser.ps1, Disable-Edge.ps1, IP-Always-Hidden.ps1, the Edge
# part of Remaining-Telemetry.ps1 and the "Browser - Tor always" task.
# It only adds what is missing; it can be run again without harm. Everything it replaces
# is copied first to Backups\browser-YYYYMMDD-HHMMSS. Requires administrator.
# It does not replace Movie-Grade.ps1 (Unbound) or bridges.sh (Tor bridges):
# if they are missing, it says so. ASCII text on purpose (PowerShell 5 and accented characters).

$ErrorActionPreference = 'Continue'
$S      = "$env:USERPROFILE\Security"
$B      = "$S\Browser"
$L      = 'C:\Program Files\LibreWolf'
$exe    = "$L\librewolf.exe"
$cfg    = "$env:USERPROFILE\.librewolf\librewolf.overrides.cfg"
$propio = "$S\Backups\librewolf-own"
$copias = "$S\Backups\browser-$(Get-Date -Format yyyyMMdd-HHmmss)"
$pins   = "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$distro = @(wsl.exe -l -q 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -like 'Ubuntu*' })[0]
if (-not $distro) { $distro = 'Ubuntu' }
$ok = 0; $fallos = @()

function Paso($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
function Hecho($t) { Write-Host "   [OK] $t" -ForegroundColor Green; $script:ok++ }
function Falla($t) { Write-Host "   [!!] $t" -ForegroundColor Yellow; $script:fallos += $t }
function Fin($t) {
    Write-Host ''; Write-Host $t
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit
}
function Copia($f) {
    if (-not (Test-Path $f)) { return }
    New-Item -ItemType Directory -Force $copias | Out-Null
    Copy-Item $f (Join-Path $copias (($f -replace '[:\\ ]', '_'))) -Force
}
# Writes a DWORD without emptying the key: New-Item -Force on an existing key
# leaves it empty (a trap that once wiped Explorer policies).
function Valor($ruta, $nombre, $v) {
    if (-not (Test-Path $ruta)) { New-Item $ruta -Force | Out-Null }
    Set-ItemProperty $ruta $nombre $v -Type DWord
}
function Puerto9050 {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.ConnectAsync('127.0.0.1', 9050).Wait(2000) -and $c.Connected } catch { $false } finally { $c.Dispose() }
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fin 'It must be run as administrator (the .bat does it by itself).' }

# ---------------------------------------------------------------- 1. Requirements
Paso '1. Requirements'
$pyw = (Get-Command pythonw.exe -EA 0).Source
if (-not $pyw) { Fin 'Python (pythonw.exe) is missing: the Browser launcher cannot run. Nothing was touched.' }
Hecho "Python: $pyw"
foreach ($f in 'launch_browser.pyw', 'from_edge.pyw', 'tor_watchdog.pyw', 'home.html', 'browser.ico') {
    if (-not (Test-Path "$B\$f")) { Fin "$B\$f is missing. Nothing was touched." }
}
Hecho 'Browser files present'
if (-not (Test-Path $exe)) {
    Write-Host '   LibreWolf is not installed: installing it with winget...'
    winget install --id LibreWolf.LibreWolf -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
    if (-not (Test-Path $exe)) { Fin 'LibreWolf could not be installed. Run UPDATE BROWSER.bat and try again.' }
}
$firma = Get-AuthenticodeSignature $exe
if ($firma.Status -ne 'Valid') { Falla "librewolf.exe signature: $($firma.Status)" }
Hecho "LibreWolf $((Get-Item $exe).VersionInfo.ProductVersion), signature $($firma.Status)"
$unb = Get-Service unbound -EA 0
if ($unb -and $unb.Status -eq 'Running') { Hecho 'local DNS Unbound running' }
else { Falla 'Unbound is not running: run MOVIE-GRADE PROTECTION.bat' }

# ---------------------------------------------------------------- 2. LibreWolf customizations
Paso '2. LibreWolf settings (smiley, policies, overrides)'
if (Get-Process librewolf -EA 0) { Write-Host '   The Browser is open: changes in this section apply when it is reopened.' }
New-Item -ItemType Directory -Force "$L\defaults\pref", "$L\distribution", "$L\browser\chrome\icons\default" | Out-Null
# Without browser.js the privileged code in the overrides does not run: no per-page Tor
# routing, no hidden location, no "Browser" title.
$js = 'pref("general.config.sandbox_enabled", false);'
if ((Get-Content "$L\defaults\pref\browser.js" -Raw -EA 0) -notmatch 'sandbox_enabled') {
    Set-Content "$L\defaults\pref\browser.js" $js -Encoding ASCII; Hecho 'browser.js in place'
} else { Hecho 'browser.js was already there' }
foreach ($ico in 'main-window.ico', 'default.ico') { Copy-Item "$B\browser.ico" "$L\browser\chrome\icons\default\$ico" -Force }
Hecho 'smiley icon on the window'
# policies.json: DuckDuckGo HTML by default, uBlock with cookie-notice lists,
# Dark Reader blocked. A LibreWolf update can overwrite it.
$pol = "$L\distribution\policies.json"
if (Test-Path "$propio\policies.json") {
    if (-not (Test-Path $pol) -or (Get-FileHash $pol).Hash -ne (Get-FileHash "$propio\policies.json").Hash) {
        Copia $pol; Copy-Item "$propio\policies.json" $pol -Force; Hecho 'policies.json restored from the kit backup'
    } else { Hecho 'policies.json correct' }
} else { Falla "there is no $propio\policies.json" }
if (Test-Path $cfg) {
    $t = Get-Content $cfg -Raw
    foreach ($marca in 'network.proxy.autoconfig_url', 'network.proxy.socks_remote_dns', 'security.tls.version.min') {
        if ($t -notmatch [regex]::Escape($marca)) { Falla "librewolf.overrides.cfg is missing $marca" }
    }
    Hecho 'librewolf.overrides.cfg present'
} else {
    $ult = Get-ChildItem "$cfg.bak-*" -EA 0 | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($ult) { Copy-Item $ult.FullName $cfg; Falla "overrides was missing: restored from $($ult.Name) (check it)" }
    else { Falla 'neither librewolf.overrides.cfg nor a copy exists: the Browser is left without its settings' }
}

# ---------------------------------------------------------------- 3. Edge disabled
Paso '3. Edge disabled and redirected to the Browser'
Get-Process msedge -EA 0 | Stop-Process -Force
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe'
if (-not (Test-Path $ifeo)) { New-Item $ifeo -Force | Out-Null }
Set-ItemProperty $ifeo Debugger "`"$pyw`" `"$B\from_edge.pyw`""
Hecho 'msedge.exe opens the Browser (links and PDFs included); WebView2 intact'
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$politicas = [ordered]@{
    StartupBoostEnabled = 0; BackgroundModeEnabled = 0; DiagnosticData = 0; PersonalizationReportingEnabled = 0
    UserFeedbackAllowed = 0; EdgeShoppingAssistantEnabled = 0; SpotlightExperiencesAndRecommendationsEnabled = 0
    ShowRecommendationsEnabled = 0; AlternateErrorPagesEnabled = 0; ResolveNavigationErrorsUseWebService = 0
    ConfigureDoNotTrack = 1; EdgeFollowEnabled = 0; ShowMicrosoftRewards = 0; NewTabPageContentEnabled = 0
    NewTabPageQuickLinksEnabled = 0; CopilotPageContext = 0; HubsSidebarEnabled = 0; TrackingPrevention = 3
}
foreach ($k in $politicas.Keys) { Valor $edge $k $politicas[$k] }
Hecho "$($politicas.Count) Edge policies (no startup boost, no background mode, no data)"
foreach ($f in 'C:\Users\Public\Desktop\Microsoft Edge.lnk', "$env:USERPROFILE\Desktop\Microsoft Edge.lnk", "$pins\Microsoft Edge.lnk") {
    if (Test-Path $f) { Copia $f; Remove-Item $f -Force; Hecho "shortcut removed: $f" }
}
if ((Test-Path "$env:USERPROFILE\Desktop\Browser.lnk") -and -not (Test-Path "$pins\Browser.lnk")) {
    Copy-Item "$env:USERPROFILE\Desktop\Browser.lnk" "$pins\Browser.lnk" -Force; Hecho 'Browser pinned to the taskbar'
}
# Start menu search without sending what you type to Bing
Valor 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
Valor 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 0
Valor 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' CortanaConsent 0
Hecho 'Start menu without Bing'

# ---------------------------------------------------------------- 4. Lock
Paso '4. Firewall lock: the Browser only goes out through Tor'
$nombre = 'Browser: Tor only (IP always hidden)'
Get-NetFirewallRule -DisplayName $nombre -EA 0 | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $nombre -Direction Outbound -Program $exe -Action Block -Profile Any -Enabled True `
    -RemoteAddress '0.0.0.0-9.255.255.255', '11.0.0.0-126.255.255.255', '128.0.0.0-169.253.255.255',
    '169.255.0.0-172.15.255.255', '172.32.0.0-192.167.255.255', '192.169.0.0-255.255.255.255', '2000::/3' `
    -Description 'Setup-Browser.ps1' | Out-Null
if (Get-NetFirewallRule -DisplayName $nombre -EA 0) { Hecho $nombre } else { Falla 'the lock could not be created' }

# ---------------------------------------------------------------- 5. Tor always on
Paso '5. Tor engine (WebTunnel) always on'
$wsl = (& wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_.Trim() -eq $distro }
if (-not $wsl) { Falla "the WSL distribution $distro does not exist: without it there is no Tor" }
else {
    # The main engine is installed from its copy in Windows, like the chosen-exit one. It is written
    # to a new file and moved on top: if it were rewritten in place while bash runs it, bash would
    # keep reading from where it was, already inside the new file.
    & wsl.exe -d $distro --exec bash -c "mkdir -p ~/.smiley && tr -d '\r' < /mnt/c/Users/$env:USERNAME/Security/Browser/tor-browser.sh | sed 's#__WINHOME__#/mnt/c/Users/$env:USERNAME#g' > ~/.smiley/tor-browser.sh.new && chmod +x ~/.smiley/tor-browser.sh.new && mv -f ~/.smiley/tor-browser.sh.new ~/.smiley/tor-browser.sh" 2>$null
    if ($LASTEXITCODE -eq 0) { Hecho 'engine ~/.smiley/tor-browser.sh installed from Browser\tor-browser.sh' } else { Falla 'could not install ~/.smiley/tor-browser.sh in WSL' }
}
$tarea = 'Browser - Tor always'
if (-not (Get-ScheduledTask $tarea -EA 0)) {
    $a = New-ScheduledTaskAction -Execute $pyw -Argument "`"$B\tor_watchdog.pyw`""
    $d = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $c = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
         -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask $tarea -Action $a -Trigger $d -Settings $c -Principal $p | Out-Null
    Hecho "task '$tarea' created"
} else { Hecho "task '$tarea' already exists" }
# Always restarted so the latest watchdog version runs (it does not stop Tor: Tor lives in Ubuntu).
Stop-ScheduledTask $tarea -EA 0; Start-Sleep 2; Start-ScheduledTask $tarea
$t0 = Get-Date
while (-not (Puerto9050) -and ((Get-Date) - $t0).TotalSeconds -lt 240) { Start-Sleep 5 }
if (Puerto9050) {
    Hecho 'Tor is listening on 127.0.0.1:9050'
    $r = & curl.exe -s -m 60 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2>$null
    if ($r -match '"IsTor":\s*true') { Hecho "exit through Tor verified: $r" } else { Falla "Tor is open but the check does not confirm it: $r" }
} else { Falla 'Tor did not open 9050 within 4 minutes: in Ubuntu run  ~/.smiley/bridges.sh renovar' }

# ---------------------------------------------------------------- 6. Special exits
Paso '6. Chosen exit and direct gate'
# Sites that block by country: they keep going through Tor, but through a second engine that only exits
# through the countries in Browser\chosen_exit.txt (9055). Sites that reject the whole Tor network go out
# directly, but only through the protected local gate (9060) and only the sites in Browser\direct.txt.
if ($wsl) {
    & wsl.exe -d $distro --exec bash -c "tr -d '\r' < /mnt/c/Users/$env:USERNAME/Security/Browser/tor-chosen.sh | sed 's#__WINHOME__#/mnt/c/Users/$env:USERNAME#g' > ~/.smiley/tor-chosen.sh.new && chmod +x ~/.smiley/tor-chosen.sh.new && mv -f ~/.smiley/tor-chosen.sh.new ~/.smiley/tor-chosen.sh" 2>$null
    if ($LASTEXITCODE -eq 0) { Hecho 'chosen-exit engine installed at ~/.smiley/tor-chosen.sh' }
    else { Falla 'could not install tor-chosen.sh in Ubuntu' }
}
function Escucha($puerto) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.ConnectAsync('127.0.0.1', $puerto).Wait(2000) -and $c.Connected } catch { $false } finally { $c.Dispose() }
}
$t0 = Get-Date
while (-not ((Escucha 9055) -and (Escucha 9060) -and (Escucha 9070)) -and ((Get-Date) - $t0).TotalSeconds -lt 150) { Start-Sleep 5 }
if (Escucha 9055) { Hecho 'Tor with chosen exit is listening on 127.0.0.1:9055' } else { Falla 'Tor with chosen exit (9055) did not open' }
if (Escucha 9060) { Hecho 'protected direct gate is listening on 127.0.0.1:9060' } else { Falla 'direct gate (9060) did not open' }
if (Escucha 9070) { Hecho 'circuit race is listening on 127.0.0.1:9070 (parameters in Browser\speed.json)' } else { Falla 'circuit race (9070) did not open: the browser uses Tor directly' }

# ---------------------------------------------------------------- Summary
if ($fallos.Count -eq 0) { Fin "BROWSER READY: $ok checks passed. Open it with the smiley." }
Fin ("{0} passed and {1} to review:`n - {2}" -f $ok, $fallos.Count, ($fallos -join "`n - "))
