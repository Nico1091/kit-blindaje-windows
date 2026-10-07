<#
.SYNOPSIS
    Security status report. READ ONLY: it never changes anything.

.DESCRIPTION
    Goes through everything that matters, scores the state and writes a
    Markdown report inside Reports\.

.EXAMPLE
    .\Audit.ps1
    Full report on screen and to a file.

.EXAMPLE
    .\Audit.ps1 -Cfa
    Only the Controlled Folder Access blocks of the last 7 days.
    This is what to check before switching CFA from audit to blocking.
#>

[CmdletBinding()]
param(
    [switch]$Cfa,
    [int]$Days = 7
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$script:Hallazgos = New-Object System.Collections.ArrayList
$script:Puntos    = 0
$script:PuntosMax = 0

function Add-Hallazgo {
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Asunto,
        [Parameter(Mandatory)][ValidateSet('GOOD','WARN','SERIOUS','INFO')][string]$Estado,
        [string]$Detalle = '',
        [string]$Arreglo = '',
        [int]$Peso = 1
    )
    [void]$script:Hallazgos.Add([pscustomobject]@{
        Area = $Area; Asunto = $Asunto; Estado = $Estado
        Detalle = $Detalle; Arreglo = $Arreglo; Peso = $Peso
    })
    if ($Estado -ne 'INFO') {
        $script:PuntosMax += $Peso
        if ($Estado -eq 'GOOD') { $script:Puntos += $Peso }
    }
    $color = switch ($Estado) { 'GOOD' { 'Green' } 'WARN' { 'Yellow' } 'SERIOUS' { 'Red' } default { 'Gray' } }
    $marca = switch ($Estado) { 'GOOD' { '  OK   ' } 'WARN' { ' WARN  ' } 'SERIOUS' { 'SERIOUS' } default { ' info  ' } }
    Write-Host ("[{0}] {1,-46} {2}" -f $marca, $Asunto, $Detalle) -ForegroundColor $color
}

# ===========================================================================
# CFA MODE: what would have been blocked
# ===========================================================================

if ($Cfa) {
    Write-Titulo "CONTROLLED FOLDER ACCESS -- LAST $Days DAYS"
    $desde = (Get-Date).AddDays(-$Days)
    try {
        # 1123 = real block, 1124 = block that would have happened (audit)
        $ev = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-Windows Defender/Operational'
            Id        = 1123, 1124
            StartTime = $desde
        } -ErrorAction Stop

        if (-not $ev) {
            Write-Host ''
            Write-Host '  No application would have been blocked in this period.' -ForegroundColor Green
            Write-Host '  You can safely switch CFA to blocking:' -ForegroundColor Green
            Write-Host '     Set-MpPreference -EnableControlledFolderAccess Enabled' -ForegroundColor White
        } else {
            $ev | ForEach-Object {
                $x = [xml]$_.ToXml()
                $d = @{}
                $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
                [pscustomobject]@{
                    When    = $_.TimeCreated
                    Type    = if ($_.Id -eq 1123) { 'BLOCKED' } else { 'would have been blocked' }
                    Program = $d['Process']
                    Path    = $d['Path']
                }
            } | Sort-Object Program -Unique | Format-Table -AutoSize

            Write-Host ''
            Write-Host '  To allow one of these programs:' -ForegroundColor Cyan
            Write-Host '     Add-MpPreference -ControlledFolderAccessAllowedApplications "<path>"' -ForegroundColor White
        }
    } catch {
        Write-Host "  No events, or CFA is not active yet. ($($_.Exception.Message))" -ForegroundColor Yellow
    }
    Write-Host ''
    return
}

# ===========================================================================
# FULL REPORT
# ===========================================================================

Write-Host ''
Write-Host '   #############################################################' -ForegroundColor DarkCyan
Write-Host '   #              S E N T I N E L   --   A U D I T             #' -ForegroundColor White
Write-Host '   #        Read only. This script never changes anything.     #' -ForegroundColor DarkCyan
Write-Host '   #############################################################' -ForegroundColor DarkCyan

$elevado = Test-Elevado
if (-not $elevado) {
    Write-Host ''
    Write-Host '  Without administrator rights you will not see the Defender' -ForegroundColor Yellow
    Write-Host '  exclusions or some logs. For the full report, run' -ForegroundColor Yellow
    Write-Host '  this console as administrator.' -ForegroundColor Yellow
}

# --- System ----------------------------------------------------------------
Write-Titulo 'SYSTEM'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$edicion = $cv.EditionID
Add-Hallazgo -Area 'System' -Asunto 'Windows edition' -Estado 'INFO' `
    -Detalle "$edicion, version $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR)"
if ($edicion -eq 'Core') {
    Add-Hallazgo -Area 'System' -Asunto 'Home edition limits' -Estado 'INFO' `
        -Detalle 'no group policy, no manageable BitLocker, no AppLocker, telemetry floor at "Required"'
}

try {
    $ult = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    $dias = if ($ult.InstalledOn) { [int]((Get-Date) - $ult.InstalledOn).TotalDays } else { 999 }
    Add-Hallazgo -Area 'System' -Asunto 'Patch age' -Peso 3 `
        -Estado $(if ($dias -le 45) { 'GOOD' } elseif ($dias -le 75) { 'WARN' } else { 'SERIOUS' }) `
        -Detalle "latest: $($ult.HotFixID), $dias days ago" `
        -Arreglo 'Settings > Windows Update > Check for updates'
} catch { }

# --- Defender --------------------------------------------------------------
Write-Titulo 'DEFENDER'
try {
    $st = Get-MpComputerStatus
    $pf = Get-MpPreference

    Add-Hallazgo -Area 'Defender' -Asunto 'Real-time protection' -Peso 3 `
        -Estado $(if ($st.RealTimeProtectionEnabled) { 'GOOD' } else { 'SERIOUS' }) `
        -Detalle $st.RealTimeProtectionEnabled
    Add-Hallazgo -Area 'Defender' -Asunto 'Tamper protection' -Peso 3 `
        -Estado $(if ($st.IsTamperProtected) { 'GOOD' } else { 'SERIOUS' }) `
        -Detalle $st.IsTamperProtected `
        -Arreglo 'Windows Security > Virus & threat protection > Manage settings'
    Add-Hallazgo -Area 'Defender' -Asunto 'Behavior monitoring' -Peso 2 `
        -Estado $(if ($st.BehaviorMonitorEnabled) { 'GOOD' } else { 'SERIOUS' }) -Detalle $st.BehaviorMonitorEnabled

    $edadFirmas = if ($st.AntivirusSignatureLastUpdated) { [int]((Get-Date) - $st.AntivirusSignatureLastUpdated).TotalDays } else { 99 }
    Add-Hallazgo -Area 'Defender' -Asunto 'Signature age' -Peso 2 `
        -Estado $(if ($edadFirmas -le 3) { 'GOOD' } elseif ($edadFirmas -le 7) { 'WARN' } else { 'SERIOUS' }) `
        -Detalle "$edadFirmas days"

    Add-Hallazgo -Area 'Defender' -Asunto 'Controlled Folder Access' -Peso 3 `
        -Estado $(switch ($pf.EnableControlledFolderAccess) { 1 { 'GOOD' } 2 { 'WARN' } default { 'SERIOUS' } }) `
        -Detalle $(switch ($pf.EnableControlledFolderAccess) { 0 { 'OFF -- it is the built-in anti-ransomware defense' } 1 { 'blocking' } 2 { 'in audit mode (records but does not block)' } default { '?' } }) `
        -Arreglo 'Harden.ps1 -Apply -Layers ransomware'

    Add-Hallazgo -Area 'Defender' -Asunto 'Network protection' -Peso 3 `
        -Estado $(switch ($pf.EnableNetworkProtection) { 1 { 'GOOD' } 2 { 'WARN' } default { 'SERIOUS' } }) `
        -Detalle $(if ($pf.EnableNetworkProtection -eq 0) { 'OFF -- does not cut connections to command and control domains' } else { 'active' }) `
        -Arreglo 'Harden.ps1 -Apply -Layers defender'

    Add-Hallazgo -Area 'Defender' -Asunto 'Cloud block level' -Peso 2 `
        -Estado $(if ($pf.CloudBlockLevel -ge 2) { 'GOOD' } else { 'WARN' }) `
        -Detalle $(switch ($pf.CloudBlockLevel) { 0 { 'default (low)' } 2 { 'high' } 4 { 'high plus' } 6 { 'zero tolerance' } default { $pf.CloudBlockLevel } })

    $nAsr = if ($pf.AttackSurfaceReductionRules_Ids) { $pf.AttackSurfaceReductionRules_Ids.Count } else { 0 }
    $bloqueando = 0
    if ($pf.AttackSurfaceReductionRules_Actions) {
        $bloqueando = ($pf.AttackSurfaceReductionRules_Actions | Where-Object { $_ -eq 1 } | Measure-Object).Count
    }
    Add-Hallazgo -Area 'Defender' -Asunto 'ASR rules configured' -Peso 3 `
        -Estado $(if ($nAsr -ge 18) { 'GOOD' } elseif ($nAsr -ge 10) { 'WARN' } else { 'SERIOUS' }) `
        -Detalle "$nAsr of 19 ($bloqueando in block mode)" `
        -Arreglo 'Harden.ps1 -Apply -Layers defender'

    # Exclusions are the first thing an attacker touches.
    if ($elevado) {
        $ex = @()
        if ($pf.ExclusionPath)      { $ex += $pf.ExclusionPath }
        if ($pf.ExclusionProcess)   { $ex += $pf.ExclusionProcess }
        if ($pf.ExclusionExtension) { $ex += $pf.ExclusionExtension }
        Add-Hallazgo -Area 'Defender' -Asunto 'Exclusions' -Peso 3 `
            -Estado $(if ($ex.Count -eq 0) { 'GOOD' } else { 'WARN' }) `
            -Detalle $(if ($ex.Count -eq 0) { 'none -- as it should be' } else { "$($ex.Count): $($ex -join ' | ')" }) `
            -Arreglo 'Review them one by one. An attacker ALWAYS adds an exclusion first.'
    } else {
        Add-Hallazgo -Area 'Defender' -Asunto 'Exclusions' -Estado 'INFO' -Detalle 'requires administrator'
    }
} catch { Add-Hallazgo -Area 'Defender' -Asunto 'Defender query' -Estado 'SERIOUS' -Detalle $_.Exception.Message -Peso 3 }

# --- Firewall --------------------------------------------------------------
Write-Titulo 'FIREWALL AND NETWORK'
try {
    foreach ($p in Get-NetFirewallProfile) {
        Add-Hallazgo -Area 'Firewall' -Asunto "Profile $($p.Name): enabled" -Peso 2 `
            -Estado $(if ($p.Enabled) { 'GOOD' } else { 'SERIOUS' }) -Detalle $p.Enabled
        Add-Hallazgo -Area 'Firewall' -Asunto "Profile $($p.Name): inbound" -Peso 1 `
            -Estado $(if ($p.DefaultInboundAction -eq 'Block') { 'GOOD' } else { 'WARN' }) `
            -Detalle $p.DefaultInboundAction `
            -Arreglo $(if ($p.DefaultInboundAction -ne 'Block') { 'NotConfigured inherits Block, but an inherited value can change without you noticing' } else { '' })
    }
    $reg = (Get-NetFirewallProfile | Where-Object { $_.LogBlocked -eq $true } | Measure-Object).Count
    Add-Hallazgo -Area 'Firewall' -Asunto 'Logging of blocked connections' -Peso 2 `
        -Estado $(if ($reg -eq 3) { 'GOOD' } else { 'WARN' }) `
        -Detalle "$reg of 3 profiles" -Arreglo 'Without a log there is no forensics'

    $entrada = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction SilentlyContinue
    $nEnt = ($entrada | Measure-Object).Count
    $nPub = ($entrada | Where-Object { $_.Profile -match 'Public' -or $_.Profile -eq 'Any' } | Measure-Object).Count
    Add-Hallazgo -Area 'Firewall' -Asunto 'Allowed inbound rules' -Peso 2 `
        -Estado $(if ($nEnt -le 60) { 'GOOD' } elseif ($nEnt -le 130) { 'WARN' } else { 'SERIOUS' }) `
        -Detalle "$nEnt in total, $nPub reach the public profile" `
        -Arreglo 'Harden.ps1 -Apply -Layers ports'
} catch { }

# --- Exposed ports ---------------------------------------------------------
try {
    $exp = Get-NetTCPConnection -State Listen -ErrorAction Stop |
           Where-Object { $_.LocalAddress -in '0.0.0.0','::' }
    $criticos = $exp | Where-Object { $_.LocalPort -in 135,139,445,3389,5985,5986,47001 }
    Add-Hallazgo -Area 'Exposure' -Asunto 'Critical ports listening on all interfaces' -Peso 3 `
        -Estado $(if (-not $criticos) { 'GOOD' } else { 'SERIOUS' }) `
        -Detalle $(if ($criticos) { ($criticos.LocalPort | Sort-Object -Unique) -join ', ' } else { 'none' }) `
        -Arreglo 'SMB (445/139), RPC (135) and WinRM (5985/47001) have no business on a personal laptop'

    $todos = ($exp | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique)
    Add-Hallazgo -Area 'Exposure' -Asunto 'All ports on 0.0.0.0 or ::' -Estado 'INFO' -Detalle ($todos -join ', ')
} catch { }

# --- Risky services --------------------------------------------------------
$riesgo = @{
    'WinRM'          = 'remote management'
    'TermService'    = 'remote desktop'
    'RemoteRegistry' = 'remote registry'
    'LanmanServer'   = 'SMB server with ADMIN$, C$ and IPC$'
    'SSDPSRV'        = 'UPnP discovery'
    'upnphost'       = 'UPnP host'
    'FDResPub'       = 'announces you on the network'
    'lltdsvc'        = 'draws you on the network map'
    'lfsvc'          = 'geolocation'
    'DiagTrack'      = 'telemetry'
    # Turned off with Windows-Services.ps1; warn if a Windows update
    # turns them back on.
    'WSearch'        = 'search indexer (catalog of your files)'
    'MapsBroker'     = 'offline maps'
    'TrkWks'         = 'distributed link tracking'
    'PcaSvc'         = 'program compatibility assistant'
}
foreach ($s in $riesgo.Keys) {
    try {
        $o = Get-Service -Name $s -ErrorAction Stop
        $malo = ($o.Status -eq 'Running' -or $o.StartType -eq 'Automatic')
        Add-Hallazgo -Area 'Services' -Asunto "$s ($($riesgo[$s]))" -Peso 2 `
            -Estado $(if ($malo) { 'WARN' } else { 'GOOD' }) `
            -Detalle "$($o.Status) / $($o.StartType)" `
            -Arreglo $(if ($malo) { 'Harden.ps1 -Apply -Layers ports,stealth,privacy' } else { '' })
    } catch { }
}

# --- Locks -----------------------------------------------------------------
Write-Titulo 'SYSTEM LOCKS'
function Get-Reg { param($r,$n) try { return (Get-ItemProperty -Path $r -Name $n -ErrorAction Stop).$n } catch { return $null } }

$pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$uac = Get-Reg $pol 'ConsentPromptBehaviorAdmin'
Add-Hallazgo -Area 'Locks' -Asunto 'UAC: prompt behavior' -Peso 3 `
    -Estado $(if ($uac -in 1,2) { 'GOOD' } elseif ($uac -eq 5) { 'WARN' } else { 'SERIOUS' }) `
    -Detalle $(switch ($uac) { 0 { 'elevate without asking -- very serious' } 2 { 'always ask for consent' } 5 { 'only for non-Windows binaries (default)' } default { "$uac" } }) `
    -Arreglo 'With 5, UAC bypasses through auto-elevation (fodhelper, sdclt) work. With 2, they do not.'

Add-Hallazgo -Area 'Locks' -Asunto 'UAC: secure desktop' -Peso 2 `
    -Estado $(if ((Get-Reg $pol 'PromptOnSecureDesktop') -eq 1) { 'GOOD' } else { 'WARN' }) `
    -Detalle $(if ((Get-Reg $pol 'PromptOnSecureDesktop') -eq 1) { 'active: no program can fake the prompt' } else { 'inactive' })
Add-Hallazgo -Area 'Locks' -Asunto 'Windows Script Host' -Peso 2 `
    -Estado $(if ((Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled') -eq 0) { 'GOOD' } else { 'WARN' }) `
    -Detalle $(if ((Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled') -eq 0) { 'disabled' } else { 'ACTIVE -- .vbs and .js files run on double-click' })
$autorun = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun'
Add-Hallazgo -Area 'Locks' -Asunto 'Drive autorun' -Peso 2 `
    -Estado $(if ($autorun -eq 255) { 'GOOD' } else { 'WARN' }) `
    -Detalle $(if ($autorun -eq 255) { 'disabled on all drives' } elseif ($null -eq $autorun) { 'not set: a hostile USB runs by itself' } else { "value $autorun (255 = all drives)" })
Add-Hallazgo -Area 'Locks' -Asunto 'File extensions visible' -Peso 1 `
    -Estado $(if ((Get-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt') -eq 0) { 'GOOD' } else { 'WARN' }) `
    -Detalle 'without this, invoice.pdf.exe looks like invoice.pdf'
$sbl = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging'
Add-Hallazgo -Area 'Locks' -Asunto 'PowerShell script block logging' -Peso 2 `
    -Estado $(if ($sbl -eq 1) { 'GOOD' } else { 'WARN' }) `
    -Detalle $(if ($sbl -eq 1) { 'active' } else { 'not set: a PowerShell attack would leave no reconstructable trace' })

# Delivery Optimization: by default your computer shares pieces of updates
# with strangers over the internet, and listens on 7680 to do so.
$dod = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode'
if ($null -eq $dod) { $dod = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' }
Add-Hallazgo -Area 'Exposure' -Asunto 'Delivery Optimization (Windows Update P2P)' -Peso 2 `
    -Estado $(if ($dod -in 0,99) { 'GOOD' } else { 'WARN' }) `
    -Detalle $(switch ($dod) { 0 { 'HTTP only, no P2P' } 1 { 'P2P on the local network' } 2 { 'P2P in the domain' } 3 { 'P2P WITH THE INTERNET -- shares with strangers' } 99 { 'simple mode' } default { 'not set: by default it shares over P2P and listens on port 7680' } }) `
    -Arreglo 'Harden.ps1 -Apply -Layers privacy'

# --- Credentials -----------------------------------------------------------
Write-Titulo 'CREDENTIALS AND KERNEL'
$lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
Add-Hallazgo -Area 'Credentials' -Asunto 'LSA protection (RunAsPPL)' -Peso 3 `
    -Estado $(if ((Get-Reg $lsa 'RunAsPPL') -in 1,2) { 'GOOD' } else { 'SERIOUS' }) `
    -Detalle "RunAsPPL = $(Get-Reg $lsa 'RunAsPPL')" -Arreglo 'Without this, mimikatz reads lsass effortlessly'
Add-Hallazgo -Area 'Credentials' -Asunto 'NTLM compatibility level' -Peso 2 `
    -Estado $(if ((Get-Reg $lsa 'LmCompatibilityLevel') -ge 5) { 'GOOD' } else { 'WARN' }) `
    -Detalle "level $(Get-Reg $lsa 'LmCompatibilityLevel') (5 = NTLMv2 only)"
Add-Hallazgo -Area 'Credentials' -Asunto 'WDigest (clear-text passwords in memory)' -Peso 3 `
    -Estado $(if ((Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential') -eq 0) { 'GOOD' } else { 'WARN' })
Add-Hallazgo -Area 'Kernel' -Asunto 'Vulnerable driver blocklist (anti-BYOVD)' -Peso 3 `
    -Estado $(if ((Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable') -eq 1) { 'GOOD' } else { 'SERIOUS' }) `
    -Arreglo 'It is how modern ransomware kills the antivirus. It works without HVCI and does not affect VMware.'

try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    Add-Hallazgo -Area 'Kernel' -Asunto 'Memory integrity (HVCI)' -Estado 'INFO' `
        -Detalle $(if ($dg.SecurityServicesRunning -contains 2) { 'active' } else { 'inactive -- conscious decision: it breaks VMware' })
} catch { }

# --- Accounts --------------------------------------------------------------
Write-Titulo 'ACCOUNTS'
try {
    $admins = Get-LocalGroupMember -Group (Get-LocalGroup | Where-Object { $_.SID.Value -eq 'S-1-5-32-544' }).Name -ErrorAction Stop
    Add-Hallazgo -Area 'Accounts' -Asunto 'Local administrators' -Peso 2 `
        -Estado $(if ($admins.Count -le 2) { 'GOOD' } else { 'WARN' }) `
        -Detalle ($admins.Name -join ', ')
    $hab = Get-LocalUser | Where-Object { $_.Enabled }
    Add-Hallazgo -Area 'Accounts' -Asunto 'Enabled local accounts' -Estado 'INFO' -Detalle ($hab.Name -join ', ')
    $admLocal = Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' }
    Add-Hallazgo -Area 'Accounts' -Asunto 'Built-in Administrator account' -Peso 2 `
        -Estado $(if (-not $admLocal.Enabled) { 'GOOD' } else { 'SERIOUS' }) `
        -Detalle $(if ($admLocal.Enabled) { 'ENABLED' } else { 'disabled' })
} catch { }

# --- Persistence -----------------------------------------------------------
Write-Titulo 'PERSISTENCE'
try {
    $wmi = Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction Stop
    Add-Hallazgo -Area 'Persistence' -Asunto 'WMI event subscriptions' -Peso 3 `
        -Estado $(if (-not $wmi) { 'GOOD' } else { 'WARN' }) `
        -Detalle $(if ($wmi) { "$($wmi.Count): $($wmi.Name -join ', ')" } else { 'none' }) `
        -Arreglo 'It is fileless persistence, almost invisible. Investigate each one.'
} catch { Add-Hallazgo -Area 'Persistence' -Asunto 'WMI subscriptions' -Estado 'INFO' -Detalle 'requires administrator' }

foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows',
                 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows')) {
    $v = Get-Reg $k 'AppInit_DLLs'
    if ($v) { Add-Hallazgo -Area 'Persistence' -Asunto 'AppInit_DLLs' -Estado 'SERIOUS' -Peso 3 -Detalle $v `
        -Arreglo 'It is injected into every process that loads user32.dll. It should be empty.' }
}
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
foreach ($n in @('Userinit','Shell')) {
    $v = Get-Reg $wl $n
    $esperado = if ($n -eq 'Userinit') { 'userinit.exe' } else { 'explorer.exe' }
    Add-Hallazgo -Area 'Persistence' -Asunto "Winlogon\$n" -Peso 3 `
        -Estado $(if ($v -and ($v -replace '[\s,]','') -match "(?i)$([regex]::Escape($esperado))$") { 'GOOD' } else { 'WARN' }) -Detalle $v
}
try {
    $ifeo = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction Stop |
            Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Debugger }
    Add-Hallazgo -Area 'Persistence' -Asunto 'Debugger hijacking (IFEO)' -Peso 3 `
        -Estado $(if (-not $ifeo) { 'GOOD' } else { 'SERIOUS' }) `
        -Detalle $(if ($ifeo) { ($ifeo.PSChildName -join ', ') } else { 'none' })
} catch { }
try {
    $t = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }
    Add-Hallazgo -Area 'Persistence' -Asunto 'Non-Microsoft scheduled tasks' -Estado 'INFO' `
        -Detalle "$($t.Count): $(($t.TaskName | Select-Object -First 8) -join ', ')"
} catch { }

# --- Backups ---------------------------------------------------------------
Write-Titulo 'RECOVERY'
try {
    $sc = Get-CimInstance Win32_ShadowCopy -ErrorAction Stop
    Add-Hallazgo -Area 'Recovery' -Asunto 'Volume shadow copies' -Peso 3 `
        -Estado $(if ($sc) { 'GOOD' } else { 'SERIOUS' }) `
        -Detalle $(if ($sc) { "$($sc.Count) shadow copies" } else { 'NONE -- no safety net against ransomware' }) `
        -Arreglo 'Harden.ps1 -Apply -Layers ransomware'
} catch { Add-Hallazgo -Area 'Recovery' -Asunto 'Volume shadow copies' -Estado 'INFO' -Detalle 'requires administrator' }

# ===========================================================================
# SUMMARY AND FILE
# ===========================================================================

$nota = if ($script:PuntosMax -gt 0) { [math]::Round(100 * $script:Puntos / $script:PuntosMax) } else { 0 }
$graves  = @($script:Hallazgos | Where-Object { $_.Estado -eq 'SERIOUS' })
$avisos  = @($script:Hallazgos | Where-Object { $_.Estado -eq 'WARN' })

Write-Titulo 'SUMMARY'
Write-Host ''
Write-Host ("   Score: {0} / 100" -f $nota) -ForegroundColor $(if ($nota -ge 85) { 'Green' } elseif ($nota -ge 60) { 'Yellow' } else { 'Red' })
Write-Host ("   Serious: {0}   Warnings: {1}" -f $graves.Count, $avisos.Count) -ForegroundColor Gray
Write-Host ''
if ($graves) {
    Write-Host '   THE SERIOUS ITEMS:' -ForegroundColor Red
    $graves | ForEach-Object { Write-Host ("     - {0}: {1}" -f $_.Asunto, $_.Detalle) -ForegroundColor Red }
    Write-Host ''
}

# Markdown report
$fichero = Join-Path $script:DirInf ("audit-$script:Sello.md")
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Security audit")
[void]$md.AppendLine("")
[void]$md.AppendLine("**Computer:** $env:COMPUTERNAME  ")
[void]$md.AppendLine("**Date:** $(Get-Date -Format 'dd/MM/yyyy HH:mm')  ")
[void]$md.AppendLine("**System:** $($cv.ProductName) ($edicion) $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR)  ")
[void]$md.AppendLine("**Score:** $nota / 100 -- $($graves.Count) serious, $($avisos.Count) warnings")
[void]$md.AppendLine("")
foreach ($area in ($script:Hallazgos | Select-Object -ExpandProperty Area -Unique)) {
    [void]$md.AppendLine("## $area")
    [void]$md.AppendLine("")
    foreach ($h in ($script:Hallazgos | Where-Object { $_.Area -eq $area })) {
        $marca = switch ($h.Estado) { 'GOOD' { 'OK' } 'WARN' { 'WARN' } 'SERIOUS' { 'SERIOUS' } default { 'info' } }
        [void]$md.AppendLine("- **[$marca] $($h.Asunto)** -- $($h.Detalle)")
        if ($h.Arreglo) { [void]$md.AppendLine("  - *$($h.Arreglo)*") }
    }
    [void]$md.AppendLine("")
}
Set-Content -Path $fichero -Value $md.ToString() -Encoding UTF8
Write-Host "   Report: $fichero" -ForegroundColor Cyan

# The score goes into a separate file so Run-All.ps1 can compare
# before and after without parsing the report.
try {
    @{
        puntuacion = $nota
        graves     = $graves.Count
        avisos     = $avisos.Count
        cuando     = (Get-Date).ToString('o')
        elevado    = $elevado
        informe    = $fichero
    } | ConvertTo-Json | Set-Content -Path (Join-Path $script:DirBase 'latest-score.json') -Encoding UTF8
} catch { }

Write-Host ''
