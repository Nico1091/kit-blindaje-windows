<#
.SYNOPSIS
    Looks for backdoors and persistence. READ ONLY, changes nothing.
    Report in Security\Reports\backdoors-<date>.txt
    As administrator it sees everything; without elevation it skips what is protected.
#>

. (Join-Path $PSScriptRoot 'lib\Core.ps1')
if (-not (Assert-Elevado -Script $PSCommandPath)) { return }

$inf = Join-Path $script:DirInf ('backdoors-' + $script:Sello + '.txt')
$sospechas = New-Object System.Collections.ArrayList
function S([string]$area, [string]$texto) { [void]$sospechas.Add("[$area] $texto") }
function L([string]$t) { Add-Content -Path $inf -Value $t -Encoding UTF8 }
function T([string]$t) { L ''; L ('=== ' + $t + ' ==='); Write-Host "  checking: $t" -ForegroundColor Cyan }
$usuario = $env:USERPROFILE
$raros = '\\AppData\\|\\Temp\\|\\Downloads\\|\\Users\\Public\\|\\ProgramData\\(?!Microsoft)'
$lolbin = '-enc|-EncodedCommand|FromBase64|IEX|Invoke-Expression|DownloadString|DownloadFile|Net\.WebClient|http[s]?://|mshta|regsvr32.*/i:|javascript:|bitsadmin|certutil.*(urlcache|decode)|-w(indowstyle)? hid'

L "Backdoor search - $(Get-Date -Format 'dd/MM/yyyy HH:mm') - admin: $(Test-Elevado)"

# --- 1 Accounts --------------------------------------------------------------
T 'ACCOUNTS'
Get-LocalUser | ForEach-Object {
    L ("{0,-22} enabled={1,-5} last logon={2} password changed={3}" -f $_.Name, $_.Enabled, $_.LastLogon, $_.PasswordLastSet)
    if ($_.Enabled -and $_.Name -notin @($env:USERNAME, 'WsiAccount')) { S 'Accounts' "enabled account that is not yours: $($_.Name)" }
}
foreach ($g in @(@('S-1-5-32-544','Administrators'), @('S-1-5-32-555','Remote Desktop Users'), @('S-1-5-32-580','Remote Management Users'))) {
    $m = @(Get-LocalGroupMember -SID $g[0] -ErrorAction SilentlyContinue | ForEach-Object Name)
    L ("group {0}: {1}" -f $g[1], ($m -join ', '))
    foreach ($x in $m) { if ($x -notmatch "\\$([regex]::Escape($env:USERNAME))$" -and $x -notmatch '\\Administrador$|\\Administrator$') { S 'Accounts' "unexpected member of $($g[1]): $x" } }
}
$ocultas = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList' -ErrorAction SilentlyContinue
if ($ocultas) { $ocultas.PSObject.Properties | Where-Object Name -notlike 'PS*' | ForEach-Object { S 'Accounts' "account hidden from the sign-in screen: $($_.Name)" } }

# --- 2 Remote access -----------------------------------------------------------
T 'REMOTE ACCESS'
$remotos = 'sshd|WinRM|TermService|TeamViewer|AnyDesk|rustdesk|VNC|ScreenConnect|Splashtop|LogMeIn|chromoting|Radmin|Ammyy|ngrok|frp|cloudflared|tailscale|zerotier|MeshAgent|Atera|NinjaRMM|Kaseya|Supremo|DWAgent'
Get-CimInstance Win32_Service | Where-Object { $_.Name -match $remotos -or $_.DisplayName -match $remotos } | ForEach-Object {
    L ("service {0} ({1}) {2}/{3} -> {4}" -f $_.Name, $_.DisplayName, $_.State, $_.StartMode, $_.PathName)
    if ($_.State -eq 'Running' -or $_.StartMode -eq 'Auto') { S 'Remote' "remote access service active: $($_.DisplayName)" }
}
Get-Process | Where-Object { $_.Name -match $remotos } | ForEach-Object { S 'Remote' "remote access program running: $($_.Name) $($_.Path)" }
$ts = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).fDenyTSConnections
L "remote desktop denied (fDenyTSConnections=1): $ts"
if ($ts -eq 0) { S 'Remote' 'remote desktop ALLOWED' }
foreach ($k in @("$usuario\.ssh\authorized_keys", "$env:ProgramData\ssh\administrators_authorized_keys")) {
    if (Test-Path $k) { $n = @(Get-Content $k | Where-Object { $_ -match '^ssh-|^ecdsa-' }).Count; L "authorized SSH keys in ${k}: $n"; if ($n) { S 'Remote' "there are $n SSH keys authorized to log in, in $k" } }
}

# --- 3 Sticky keys and debuggers ---------------------------------------------
T 'ACCESSIBILITY AND IFEO'
$cmdHash = (Get-FileHash "$env:windir\System32\cmd.exe").Hash
$psHash  = (Get-FileHash "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe").Hash
foreach ($b in 'sethc','utilman','osk','Magnify','Narrator','DisplaySwitch','AtBroker','EaseOfAccessDialog') {
    $f = "$env:windir\System32\$b.exe"
    if (-not (Test-Path $f)) { continue }
    $h = (Get-FileHash $f).Hash; $s = Get-AuthenticodeSignature $f
    L ("{0,-20} signature={1} {2}" -f "$b.exe", $s.Status, $(if ($h -in $cmdHash, $psHash) {'== CONSOLE!'} else {''}))
    if ($h -in $cmdHash, $psHash -or $s.Status -ne 'Valid') { S 'Accessibility' "$b.exe was replaced or has no valid signature" }
}
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue | ForEach-Object {
    $d = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Debugger
    if ($d) { L "IFEO debugger: $($_.PSChildName) -> $d"; S 'IFEO' "$($_.PSChildName) is redirected to: $d" }
}
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit' -ErrorAction SilentlyContinue | ForEach-Object {
    $m = (Get-ItemProperty $_.PSPath).MonitorProcess; if ($m) { S 'IFEO' "when $($_.PSChildName) closes, this runs: $m" } }

# --- 4 Sign-in hooks -----------------------------------------------------------
T 'WINLOGON, LSA, APPINIT'
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
L "Shell: $($wl.Shell) | Userinit: $($wl.Userinit)"
if ($wl.Shell -ne 'explorer.exe') { S 'Winlogon' "Shell tampered with: $($wl.Shell)" }
if ($wl.Userinit -notmatch '^C:\\Windows\\system32\\userinit\.exe,?$') { S 'Winlogon' "Userinit tampered with: $($wl.Userinit)" }
$wlu = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue).Shell
if ($wlu) { S 'Winlogon' "per-user Shell defined: $wlu" }
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows') {
    $a = (Get-ItemProperty $k -ErrorAction SilentlyContinue).AppInit_DLLs
    L "AppInit_DLLs ($k): $a"; if ($a) { S 'AppInit' "DLL injected into every program: $a" } }
$ac = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCertDlls' -ErrorAction SilentlyContinue
if ($ac -and $ac.ValueCount) { S 'AppCert' 'AppCertDlls are defined' }
$lsa = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
L "LSA Authentication: $($lsa.'Authentication Packages' -join ',') | Notification: $($lsa.'Notification Packages' -join ',') | Security: $($lsa.'Security Packages' -join ',')"
foreach ($p in @($lsa.'Authentication Packages') + @($lsa.'Notification Packages')) { if ($p -and $p -notin 'msv1_0','scecli','rassfm','') { S 'LSA' "non-standard LSA package (can steal passwords): $p" } }
$be = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').BootExecute
L "BootExecute: $($be -join ' | ')"
if (($be -join ' ') -notmatch '^autocheck autochk \*$') { S 'Boot' "BootExecute modified: $($be -join ' | ')" }
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors' -ErrorAction SilentlyContinue | ForEach-Object {
    $d = (Get-ItemProperty $_.PSPath).Driver
    if ($d -and $d -notmatch '^(localspl|tcpmon|usbmon|WSDMon|APMon|AppMon|FXSMON|MsPrint|PrintMonitor|pdfmon|WdMon)\.dll$') { S 'Printing' "non-standard print monitor: $($_.PSChildName) -> $d" } }
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NetSh' -ErrorAction SilentlyContinue | ForEach-Object { $_.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Value -match '\\' } | ForEach-Object { S 'Netsh' "netsh helper with a path: $($_.Value)" } }

# --- 5 Startup: Run keys and folders --------------------------------------------
T 'RUN KEYS AND STARTUP FOLDERS'
foreach ($k in 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run') {
    $i = Get-ItemProperty $k -ErrorAction SilentlyContinue
    if ($i) { $i.PSObject.Properties | Where-Object Name -notlike 'PS*' | ForEach-Object {
        L "$k :: $($_.Name) = $($_.Value)"
        if ("$($_.Value)" -match $lolbin) { S 'Run' "startup entry with a suspicious command: $($_.Name) = $($_.Value)" }
        if ($k -match 'Policies') { S 'Run' "startup entry hidden in Policies: $($_.Name) = $($_.Value)" } } }
}
foreach ($d in "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp") {
    Get-ChildItem $d -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object { L "startup: $($_.FullName)" } }

# --- 6 Scheduled tasks -----------------------------------------------------------
T 'SCHEDULED TASKS'
Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
    $t = $_
    foreach ($a in @($t.Actions)) {
        $cmd = ("$($a.Execute) $($a.Arguments)").Trim()
        if (-not $cmd) { continue }
        $propia = $t.TaskPath -notlike '\Microsoft\*'
        if ($propia) { L ("{0}{1} [{2}] -> {3}" -f $t.TaskPath, $t.TaskName, $t.State, $cmd) }
        if ($cmd -match $lolbin) { S 'Tasks' "$($t.TaskPath)$($t.TaskName) runs something suspicious: $cmd" }
        elseif ($cmd -match $raros -and $propia -and $t.State -ne 'Disabled') { L "   ^ runs from a user folder" }
        if (-not $propia -and $cmd -match $raros) { S 'Tasks' "task with a Microsoft name that runs from a user folder: $($t.TaskPath)$($t.TaskName) -> $cmd" }
    }
}

# --- 7 WMI (invisible persistence) -------------------------------------------------
T 'WMI SUBSCRIPTIONS'
$f = @(Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction SilentlyContinue)
$c = @(Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction SilentlyContinue)
$b = @(Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue)
L "filters: $($f.Count) | consumers: $($c.Count) | bindings: $($b.Count)"
foreach ($x in $c) {
    $d = "$($x.Name): $($x.CommandLineTemplate) $($x.ScriptText)"
    L "consumer $($x.CimClass.CimClassName) $d"
    if ($x.Name -ne 'SCM Event Log Consumer') { S 'WMI' "WMI consumer: $d" }
}

# --- 8 Hijacked COM ---------------------------------------------------------------
T 'USER COM'
Get-ChildItem 'HKCU:\Software\Classes\CLSID' -ErrorAction SilentlyContinue | ForEach-Object {
    $s = Get-ItemProperty (Join-Path $_.PSPath 'InprocServer32') -ErrorAction SilentlyContinue
    $v = if ($s) { $s.'(default)' } else { $null }
    if ($v) { L "$($_.PSChildName) -> $v"; if ($v -match $raros -and $v -notmatch 'OneDrive|Microsoft\\Teams|Dropbox|Google\\Drive') { S 'COM' "user COM component from an odd folder: $($_.PSChildName) -> $v" } }
}

# --- 9 PowerShell profiles ----------------------------------------------------------
T 'POWERSHELL PROFILES'
foreach ($p in "$env:windir\System32\WindowsPowerShell\v1.0\profile.ps1", "$env:windir\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1",
               "$usuario\Documents\WindowsPowerShell\profile.ps1", "$usuario\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
               "$usuario\Documents\PowerShell\profile.ps1", "$usuario\Documents\PowerShell\Microsoft.PowerShell_profile.ps1", "$env:ProgramFiles\PowerShell\7\profile.ps1") {
    if (Test-Path $p) {
        $txt = Get-Content $p -Raw
        L "--- $p ---"; L $txt
        if ($txt -match $lolbin) { S 'PowerShell' "the profile $p contains suspicious commands" }
    }
}

# --- 10 Intercepted traffic -------------------------------------------------------
T 'HOSTS, PROXY AND ROOT CERTIFICATES'
$h = Get-Content "$env:windir\System32\drivers\etc\hosts" | Where-Object { $_ -match '^\s*[^#\s]' }
L "hosts (active lines): $($h -join ' | ')"
foreach ($x in $h) { if ($x -notmatch '^\s*(127\.0\.0\.1|::1|0\.0\.0\.0)\s') { S 'Hosts' "redirection in hosts: $x" } }
$ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
L "user proxy: enabled=$($ie.ProxyEnable) server=$($ie.ProxyServer) PAC=$($ie.AutoConfigURL)"
if ($ie.ProxyEnable -eq 1 -or $ie.AutoConfigURL) { S 'Proxy' "proxy configured: $($ie.ProxyServer) $($ie.AutoConfigURL)" }
$wh = (& netsh.exe winhttp show proxy) -join ' '; L "winhttp: $wh"
if ($wh -notmatch 'Direct access|Acceso directo|directo') { S 'Proxy' "system proxy (WinHTTP): $wh" }
$conocidas = 'Microsoft|DigiCert|GlobalSign|Sectigo|COMODO|USERTrust|AAA Certificate|Entrust|GoDaddy|Starfield|ISRG|Baltimore|VeriSign|Symantec|thawte|QuoVadis|Certum|IdenTrust|Amazon|Google Trust|GTS Root|SSL\.com|Buypass|T-TeleSec|Telekom|Hongkong Post|Actalis|Camerfirma|Certigna|D-TRUST|SwissSign|Go Daddy|Class 3 Public|NetLock|Izenpe|Firmaprofesional|AffirmTrust|Autoridad de Certificacion|Security Communication|SECOM|emSign|HARICA|Hellenic|TWCA|Trustwave|SecureTrust|XRamp|Network Solutions|Chambers|Global Chambersign|UCA|Certainly|Atos|TrustCor|E-Tugra|Microsec|OISTE|WISeKey|CFCA|GDCA|vTrus|NAVER|ANF|Telia|Sonera|Trustis|Cybertrust|Equifax|Starfield|Staat der Nederlanden|DST Root|KISA|ePKI|TUBITAK|Certainly|Sectigo|SZAFIR|Unizeto|Deutsche Telekom|Dhimyotis|Fina|BJCA|LuxTrust|Disig|SK ID|COMODO|Cisco'
foreach ($store in 'Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root') {
    Get-ChildItem $store -ErrorAction SilentlyContinue | Where-Object { $_.Subject -notmatch $conocidas -and $_.Issuer -notmatch $conocidas } | ForEach-Object {
        L "unusual root in ${store}: $($_.Subject) | since $($_.NotBefore.ToString('dd/MM/yyyy')) | thumbprint $($_.Thumbprint)"
        S 'Certificates' "unusual root certificate (can read your encrypted traffic): $($_.Subject) [$store]"
    }
}

# --- 11 Defender -----------------------------------------------------------------------
T 'DEFENDER'
try {
    $mp = Get-MpPreference -ErrorAction Stop; $st = Get-MpComputerStatus -ErrorAction Stop
    L "real time: $(-not $mp.DisableRealtimeMonitoring) | tamper protection: $($st.IsTamperProtected) | signatures: $($st.AntivirusSignatureLastUpdated)"
    if ($mp.DisableRealtimeMonitoring) { S 'Defender' 'real-time protection is OFF' }
    foreach ($e in @($mp.ExclusionPath) + @($mp.ExclusionProcess) + @($mp.ExclusionExtension) | Where-Object { $_ -and $_ -notmatch 'N/A' }) { L "exclusion: $e"; S 'Defender' "Defender exclusion (an area that is not scanned): $e" }
    Get-MpThreatDetection -ErrorAction SilentlyContinue | ForEach-Object { S 'Defender' "detection: $($_.ThreatID) in $($_.Resources -join ',') ($($_.InitialDetectionTime))" }
} catch { L "Defender: $($_.Exception.Message)" }

# --- 12 Connections and listening ports ------------------------------------------------
T 'ACTIVE OUTBOUND CONNECTIONS'
Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0|::$|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|fe80)' } |
    Group-Object OwningProcess | ForEach-Object {
        $p = Get-Process -Id $_.Name -ErrorAction SilentlyContinue
        $dest = ($_.Group | ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" } | Sort-Object -Unique) -join ', '
        L ("{0,-26} {1}" -f $p.Name, $dest)
        if ($p.Path -and $p.Path -match $raros -and $p.Path -notmatch 'LibreWolf|claude|Programs\\(Python|Obsidian|opencode|@opencode)|WindowsApps|Microsoft\\(Teams|OneDrive|Edge)') { S 'Network' "program from a user folder talking to the internet: $($p.Path) -> $dest" }
    }
T 'PORTS LISTENING ON THE NETWORK'
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -notmatch '^(127\.|::1$)' } | Sort-Object LocalPort -Unique | ForEach-Object {
    $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    L ("{0,-6} {1,-16} {2} {3}" -f $_.LocalPort, $_.LocalAddress, $p.Name, $p.Path)
    if ($_.LocalPort -lt 49152 -and $_.LocalPort -notin 135, 139, 445, 3240, 5040, 7680) { S 'Network' "port $($_.LocalPort) open to the network by $($p.Name)" }
}

# --- 13 Edge browser extensions -------------------------------------------------------
T 'EDGE EXTENSIONS'
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Extensions\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $man = Get-ChildItem $_.FullName -Recurse -Filter manifest.json -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($man) { try { $j = Get-Content $man.FullName -Raw | ConvertFrom-Json; L ("{0} | {1} {2} | permissions: {3}" -f $_.Name, $j.name, $j.version, (@($j.permissions) -join ',')) } catch { } }
}

# --- 14 Background downloads (BITS) ---------------------------------------------------
T 'BITS JOBS'
Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | ForEach-Object { L "BITS: $($_.DisplayName) $($_.JobState) $($_.FileList.RemoteName -join ',')"; if ($_.FileList.RemoteName -notmatch 'microsoft|windowsupdate|msedge|office') { S 'BITS' "unusual background download: $($_.DisplayName)" } }

# --- Summary --------------------------------------------------------------------------
$res = @('', '############ SUMMARY ############')
if ($sospechas.Count) { $res += "ITEMS TO REVIEW: $($sospechas.Count)"; $res += $sospechas } else { $res += 'NO SIGNS OF BACKDOORS' }
$previo = Get-Content $inf
Set-Content -Path $inf -Value ($res + '' + $previo) -Encoding UTF8
$res | ForEach-Object { Write-Host $_ }
Write-Bitacora "report: $inf" 'OK'
