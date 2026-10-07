param([switch]$SinPausa)
# Deja el Buscador completo funcionando en una sola pasada (04/10/2026):
# LibreWolf con la carita, sus ajustes, Edge paralizado y redirigido, la salida
# por Tor con WebTunnel siempre encendida, y el candado del cortafuegos.
# Reune Carita-Buscador.ps1, Apagar-Edge.ps1, IP-Siempre-Oculta.ps1, la parte de
# Edge de Telemetria-Restante.ps1 y la tarea "Buscador - Tor siempre".
# Solo pone lo que falta; se puede repetir sin dano. Cada cosa que reemplaza la
# copia antes en Respaldos\buscador-AAAAMMDD-HHMMSS. Exige administrador.
# No sustituye a Nivel-Pelicula.ps1 (Unbound) ni a puentes.sh (puentes de Tor):
# si faltan, lo dice. Texto en ASCII a proposito (PowerShell 5 y tildes).

$ErrorActionPreference = 'Continue'
$S      = "$env:USERPROFILE\Seguridad"
$B      = "$S\Buscador"
$L      = 'C:\Program Files\LibreWolf'
$exe    = "$L\librewolf.exe"
$cfg    = "$env:USERPROFILE\.librewolf\librewolf.overrides.cfg"
$propio = "$S\Respaldos\librewolf-propio"
$copias = "$S\Respaldos\buscador-$(Get-Date -Format yyyyMMdd-HHmmss)"
$pins   = "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$distro = @(wsl.exe -l -q 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -like 'Ubuntu*' })[0]
if (-not $distro) { $distro = 'Ubuntu' }
$ok = 0; $fallos = @()

function Paso($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
function Hecho($t) { Write-Host "   [OK] $t" -ForegroundColor Green; $script:ok++ }
function Falla($t) { Write-Host "   [!!] $t" -ForegroundColor Yellow; $script:fallos += $t }
function Fin($t) {
    Write-Host ''; Write-Host $t
    if (-not $SinPausa) { Read-Host 'Pulsa Enter para cerrar' | Out-Null }
    exit
}
function Copia($f) {
    if (-not (Test-Path $f)) { return }
    New-Item -ItemType Directory -Force $copias | Out-Null
    Copy-Item $f (Join-Path $copias (($f -replace '[:\\ ]', '_'))) -Force
}
# Escribe un DWORD sin vaciar la clave: New-Item -Force sobre una clave existente
# la deja vacia (trampa que ya borro politicas de Explorer una vez).
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
if (-not $admin) { Fin 'Hace falta abrirlo como administrador (el .bat lo hace solo).' }

# ---------------------------------------------------------------- 1. Requisitos
Paso '1. Requisitos'
$pyw = (Get-Command pythonw.exe -EA 0).Source
if (-not $pyw) { Fin 'Falta Python (pythonw.exe): el lanzador del Buscador no puede correr. No se toco nada.' }
Hecho "Python: $pyw"
foreach ($f in 'lanzar_buscador.pyw', 'desde_edge.pyw', 'vigia_tor.pyw', 'inicio.html', 'buscador.ico') {
    if (-not (Test-Path "$B\$f")) { Fin "Falta $B\$f. No se toco nada." }
}
Hecho 'piezas del Buscador presentes'
if (-not (Test-Path $exe)) {
    Write-Host '   LibreWolf no esta instalado: se instala con winget...'
    winget install --id LibreWolf.LibreWolf -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
    if (-not (Test-Path $exe)) { Fin 'No se pudo instalar LibreWolf. Pulsa ACTUALIZAR BUSCADOR.bat y repite.' }
}
$firma = Get-AuthenticodeSignature $exe
if ($firma.Status -ne 'Valid') { Falla "firma de librewolf.exe: $($firma.Status)" }
Hecho "LibreWolf $((Get-Item $exe).VersionInfo.ProductVersion), firma $($firma.Status)"
$unb = Get-Service unbound -EA 0
if ($unb -and $unb.Status -eq 'Running') { Hecho 'DNS local Unbound en marcha' }
else { Falla 'Unbound no esta en marcha: pulsa PROTECCION NIVEL PELICULA.bat' }

# ---------------------------------------------------------------- 2. LibreWolf propio
Paso '2. Ajustes de LibreWolf (carita, politicas, overrides)'
if (Get-Process librewolf -EA 0) { Write-Host '   El Buscador esta abierto: los cambios de esta seccion valen al reabrirlo.' }
New-Item -ItemType Directory -Force "$L\defaults\pref", "$L\distribution", "$L\browser\chrome\icons\default" | Out-Null
# Sin buscador.js no corre el codigo con privilegios de los overrides: ni ruta por Tor
# por pagina, ni ubicacion oculta, ni titulo "Buscador".
$js = 'pref("general.config.sandbox_enabled", false);'
if ((Get-Content "$L\defaults\pref\buscador.js" -Raw -EA 0) -notmatch 'sandbox_enabled') {
    Set-Content "$L\defaults\pref\buscador.js" $js -Encoding ASCII; Hecho 'buscador.js puesto'
} else { Hecho 'buscador.js ya estaba' }
foreach ($ico in 'main-window.ico', 'default.ico') { Copy-Item "$B\buscador.ico" "$L\browser\chrome\icons\default\$ico" -Force }
Hecho 'icono de la carita en la ventana'
# policies.json: DuckDuckGo HTML por defecto, uBlock con listas anti-avisos de cookies,
# Dark Reader bloqueado. Una actualizacion de LibreWolf puede reescribirlo.
$pol = "$L\distribution\policies.json"
if (Test-Path "$propio\policies.json") {
    if (-not (Test-Path $pol) -or (Get-FileHash $pol).Hash -ne (Get-FileHash "$propio\policies.json").Hash) {
        Copia $pol; Copy-Item "$propio\policies.json" $pol -Force; Hecho 'policies.json repuesto desde el respaldo propio'
    } else { Hecho 'policies.json correcto' }
} else { Falla "no hay $propio\policies.json" }
if (Test-Path $cfg) {
    $t = Get-Content $cfg -Raw
    foreach ($marca in 'network.proxy.autoconfig_url', 'network.proxy.socks_remote_dns', 'security.tls.version.min') {
        if ($t -notmatch [regex]::Escape($marca)) { Falla "librewolf.overrides.cfg sin $marca" }
    }
    Hecho 'librewolf.overrides.cfg presente'
} else {
    $ult = Get-ChildItem "$cfg.bak-*" -EA 0 | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($ult) { Copy-Item $ult.FullName $cfg; Falla "overrides faltaba: repuesto desde $($ult.Name) (revisar)" }
    else { Falla 'no existe librewolf.overrides.cfg ni copia: el Buscador queda sin sus ajustes' }
}

# ---------------------------------------------------------------- 3. Edge paralizado
Paso '3. Edge paralizado y redirigido al Buscador'
Get-Process msedge -EA 0 | Stop-Process -Force
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe'
if (-not (Test-Path $ifeo)) { New-Item $ifeo -Force | Out-Null }
Set-ItemProperty $ifeo Debugger "`"$pyw`" `"$B\desde_edge.pyw`""
Hecho 'msedge.exe abre el Buscador (enlaces y PDF incluidos); WebView2 intacto'
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$politicas = [ordered]@{
    StartupBoostEnabled = 0; BackgroundModeEnabled = 0; DiagnosticData = 0; PersonalizationReportingEnabled = 0
    UserFeedbackAllowed = 0; EdgeShoppingAssistantEnabled = 0; SpotlightExperiencesAndRecommendationsEnabled = 0
    ShowRecommendationsEnabled = 0; AlternateErrorPagesEnabled = 0; ResolveNavigationErrorsUseWebService = 0
    ConfigureDoNotTrack = 1; EdgeFollowEnabled = 0; ShowMicrosoftRewards = 0; NewTabPageContentEnabled = 0
    NewTabPageQuickLinksEnabled = 0; CopilotPageContext = 0; HubsSidebarEnabled = 0; TrackingPrevention = 3
}
foreach ($k in $politicas.Keys) { Valor $edge $k $politicas[$k] }
Hecho "$($politicas.Count) politicas de Edge (sin arranque previo, sin segundo plano, sin datos)"
foreach ($f in 'C:\Users\Public\Desktop\Microsoft Edge.lnk', "$env:USERPROFILE\Desktop\Microsoft Edge.lnk", "$pins\Microsoft Edge.lnk") {
    if (Test-Path $f) { Copia $f; Remove-Item $f -Force; Hecho "acceso quitado: $f" }
}
if ((Test-Path "$env:USERPROFILE\Desktop\Buscador.lnk") -and -not (Test-Path "$pins\Buscador.lnk")) {
    Copy-Item "$env:USERPROFILE\Desktop\Buscador.lnk" "$pins\Buscador.lnk" -Force; Hecho 'Buscador anclado a la barra'
}
# Busqueda del menu Inicio sin enviar lo escrito a Bing
Valor 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
Valor 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 0
Valor 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' CortanaConsent 0
Hecho 'menu Inicio sin Bing'

# ---------------------------------------------------------------- 4. Candado
Paso '4. Candado del cortafuegos: el Buscador solo sale por Tor'
$nombre = 'Buscador: solo por Tor (IP siempre oculta)'
Get-NetFirewallRule -DisplayName $nombre -EA 0 | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $nombre -Direction Outbound -Program $exe -Action Block -Profile Any -Enabled True `
    -RemoteAddress '0.0.0.0-9.255.255.255', '11.0.0.0-126.255.255.255', '128.0.0.0-169.253.255.255',
    '169.255.0.0-172.15.255.255', '172.32.0.0-192.167.255.255', '192.169.0.0-255.255.255.255', '2000::/3' `
    -Description 'Configurar-Buscador.ps1' | Out-Null
if (Get-NetFirewallRule -DisplayName $nombre -EA 0) { Hecho $nombre } else { Falla 'no se pudo crear el candado' }

# ---------------------------------------------------------------- 5. Tor siempre
Paso '5. Motor Tor (WebTunnel) siempre encendido'
$wsl = (& wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_.Trim() -eq $distro }
if (-not $wsl) { Falla "no existe la distribucion $distro de WSL: sin ella no hay Tor" }
else {
    # El motor principal se instala desde su copia en Windows, igual que el de salida elegida. Se escribe
    # en un archivo nuevo y se mueve encima: si se reescribe en su sitio mientras bash lo ejecuta, bash
    # sigue leyendo por donde iba, ya dentro del archivo nuevo (04/10/2026).
    & wsl.exe -d $distro --exec bash -c "mkdir -p ~/.carita && tr -d '\r' < /mnt/c/Users/$env:USERNAME/Seguridad/Buscador/tor-buscador.sh | sed 's#__WINHOME__#/mnt/c/Users/$env:USERNAME#g' > ~/.carita/tor-buscador.sh.nuevo && chmod +x ~/.carita/tor-buscador.sh.nuevo && mv -f ~/.carita/tor-buscador.sh.nuevo ~/.carita/tor-buscador.sh" 2>$null
    if ($LASTEXITCODE -eq 0) { Hecho 'motor ~/.carita/tor-buscador.sh instalado desde Buscador\tor-buscador.sh' } else { Falla 'no se pudo instalar ~/.carita/tor-buscador.sh en WSL' }
}
$tarea = 'Buscador - Tor siempre'
if (-not (Get-ScheduledTask $tarea -EA 0)) {
    $a = New-ScheduledTaskAction -Execute $pyw -Argument "`"$B\vigia_tor.pyw`""
    $d = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $c = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
         -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask $tarea -Action $a -Trigger $d -Settings $c -Principal $p | Out-Null
    Hecho "tarea '$tarea' creada"
} else { Hecho "tarea '$tarea' ya existe" }
# Se reinicia siempre para que corra la ultima version del vigia (no apaga Tor: Tor vive en Ubuntu).
Stop-ScheduledTask $tarea -EA 0; Start-Sleep 2; Start-ScheduledTask $tarea
$t0 = Get-Date
while (-not (Puerto9050) -and ((Get-Date) - $t0).TotalSeconds -lt 240) { Start-Sleep 5 }
if (Puerto9050) {
    Hecho 'Tor escucha en 127.0.0.1:9050'
    $r = & curl.exe -s -m 60 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2>$null
    if ($r -match '"IsTor":\s*true') { Hecho "salida comprobada por Tor: $r" } else { Falla "Tor abierto pero la comprobacion no confirma: $r" }
} else { Falla 'Tor no abrio el 9050 en 4 minutos: en Ubuntu ejecutar  ~/.carita/puentes.sh renovar' }

# ---------------------------------------------------------------- 6. Salidas especiales
Paso '6. Salida elegida y puerta directa'
# Los sitios que bloquean por pais: sigue por Tor, pero por un segundo motor que solo sale por los paises de
# Buscador\salida_elegida.txt (9055). Los que rechazan a toda la red Tor: sale directo, pero solo por la
# puerta local protegida (9060) y solo los sitios de Buscador\directos.txt. Ver BITACORA-2026-10-04.md.
if ($wsl) {
    & wsl.exe -d $distro --exec bash -c "tr -d '\r' < /mnt/c/Users/$env:USERNAME/Seguridad/Buscador/tor-elegida.sh | sed 's#__WINHOME__#/mnt/c/Users/$env:USERNAME#g' > ~/.carita/tor-elegida.sh.nuevo && chmod +x ~/.carita/tor-elegida.sh.nuevo && mv -f ~/.carita/tor-elegida.sh.nuevo ~/.carita/tor-elegida.sh" 2>$null
    if ($LASTEXITCODE -eq 0) { Hecho 'motor de salida elegida instalado en ~/.carita/tor-elegida.sh' }
    else { Falla 'no se pudo instalar tor-elegida.sh en Ubuntu' }
}
function Escucha($puerto) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.ConnectAsync('127.0.0.1', $puerto).Wait(2000) -and $c.Connected } catch { $false } finally { $c.Dispose() }
}
$t0 = Get-Date
while (-not ((Escucha 9055) -and (Escucha 9060) -and (Escucha 9070)) -and ((Get-Date) - $t0).TotalSeconds -lt 150) { Start-Sleep 5 }
if (Escucha 9055) { Hecho 'Tor con salida elegida escucha en 127.0.0.1:9055' } else { Falla 'Tor con salida elegida (9055) no abrio' }
if (Escucha 9060) { Hecho 'puerta directa protegida escucha en 127.0.0.1:9060' } else { Falla 'puerta directa (9060) no abrio' }
if (Escucha 9070) { Hecho 'carrera de circuitos escucha en 127.0.0.1:9070 (parametros en Buscador\velocidad.json)' } else { Falla 'carrera de circuitos (9070) no abrio: el navegador usa Tor directo' }

# ---------------------------------------------------------------- Resumen
if ($fallos.Count -eq 0) { Fin "BUSCADOR COMPLETO: $ok comprobaciones correctas. Abrelo con la carita." }
Fin ("{0} correctas y {1} por revisar:`n - {2}" -f $ok, $fallos.Count, ($fallos -join "`n - "))
