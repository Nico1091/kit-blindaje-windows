<#
.SYNOPSIS
    Undoes what Harden.ps1 did.

.DESCRIPTION
    Three modes:

      -Emergency    Network only. Fast, no questions, no backup to choose.
                    This is what you run if you have lost internet.

      (no option)   Lists the backups and fully restores the latest one:
                    firewall, registry and services.

      -Backup X     Restores a specific backup folder.

.EXAMPLE
    .\Restore.ps1 -Emergency
    Restores the firewall and network services and checks that there is internet.

.EXAMPLE
    .\Restore.ps1 -ListBackups
    Shows which backups are available.
#>

[CmdletBinding()]
param(
    [switch]$Emergency,
    [switch]$ListBackups,
    [string]$Backup,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')

# ---------------------------------------------------------------------------

function Get-Respaldos {
    Get-ChildItem -Path $script:DirResp -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'firewall.wfw') } |
        Sort-Object Name -Descending
}

function Show-Respaldos {
    $r = Get-Respaldos
    if (-not $r) { Write-Host '  There are no backups.' -ForegroundColor Yellow; return $null }
    Write-Host ''
    Write-Host '  Available backups:' -ForegroundColor Cyan
    $i = 0
    foreach ($x in $r) {
        $i++
        $fw  = Get-Item (Join-Path $x.FullName 'firewall.wfw') -ErrorAction SilentlyContinue
        $reg = (Get-ChildItem $x.FullName -Filter '*.reg' -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("   [{0}]  {1}   firewall {2} KB, {3} registry keys" -f `
            $i, $x.Name, [math]::Round($fw.Length/1KB), $reg) -ForegroundColor Gray
    }
    Write-Host ''
    return $r
}

# ===========================================================================
# EMERGENCY MODE
# ===========================================================================

function Invoke-Emergency {
    Write-Titulo 'EMERGENCY RESTORE -- NETWORK ONLY'

    $ultimo = Get-Respaldos | Select-Object -First 1
    if (-not $ultimo) {
        Write-Bitacora 'no firewall backup. The safe factory configuration is applied.' 'WARN'
        & netsh.exe advfirewall reset > $null 2>&1
    } else {
        $wfw = Join-Path $ultimo.FullName 'firewall.wfw'
        Write-Bitacora "importing firewall from $($ultimo.Name)" 'INFO'
        & netsh.exe advfirewall reset > $null 2>&1
        $r = & netsh.exe advfirewall import "$wfw" 2>&1
        Write-Bitacora "netsh import: $r" 'INFO'
    }

    # Safe, working state no matter what.
    & netsh.exe advfirewall set allprofiles state on > $null 2>&1
    & netsh.exe advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound > $null 2>&1
    Write-Bitacora 'firewall: inbound blocked, OUTBOUND ALLOWED' 'CHANGE'

    # Remove the rules the Sentinel added, which may get in the way.
    foreach ($n in @('Sentinel-No-Ping-IPv4','Sentinel-No-Ping-IPv6',
                     'Sentinel-Hardening-Local-Subnet')) {
        try { Remove-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-NetFirewallRule -DisplayName 'Sentinel-VM-Isolated-*' -ErrorAction SilentlyContinue } catch { }
    Write-Bitacora 'Sentinel rules removed' 'CHANGE'

    # Network services up.
    foreach ($s in @('Dhcp','Dnscache','nsi','NlaSvc','netprofm','WlanSvc','Wcmsvc','BFE','mpssvc','LanmanWorkstation')) {
        try {
            Set-Service -Name $s -StartupType Automatic -ErrorAction Stop
            if ((Get-Service $s).Status -ne 'Running') { Start-Service -Name $s -ErrorAction SilentlyContinue }
            Write-Bitacora "service $s up" 'OK'
        } catch { Write-Bitacora "service $s : $($_.Exception.Message)" 'WARN' }
    }

    # Network adapters enabled.
    try {
        Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Disabled' } | ForEach-Object {
            Enable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue
            Write-Bitacora "adapter $($_.Name) enabled again" 'CHANGE'
        }
    } catch { }

    # Name resolution back to the state that worked.
    try {
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Nombre 'EnableMulticast' -Valor 1 | Out-Null
        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
        Write-Bitacora 'DNS set back to whatever the network hands out (DHCP)' 'CHANGE'
    } catch { }

    & ipconfig.exe /flushdns > $null 2>&1
    Disable-Reversor -Silencioso

    Write-Host ''
    Write-Titulo 'CHECKING'
    $chk = Test-Conectividad
    Write-Host ''
    if ($chk.Sano) {
        Write-Host '  Internet restored.' -ForegroundColor Green
    } else {
        Write-Host '  STILL NO CONNECTION. Try, in this order:' -ForegroundColor Red
        Write-Host '    1. Disconnect and reconnect the Wi-Fi.' -ForegroundColor Yellow
        Write-Host '    2. Restart the computer.' -ForegroundColor Yellow
        Write-Host '    3. As a last resort, in PowerShell as administrator:' -ForegroundColor Yellow
        Write-Host '         netsh winsock reset' -ForegroundColor White
        Write-Host '         netsh int ip reset' -ForegroundColor White
        Write-Host '       and RESTART (those two leave the network stack half-done until a restart).' -ForegroundColor Yellow
        Write-Host '    4. System Restore to the "Sentinel" restore point.' -ForegroundColor Yellow
    }
    Write-Host ''
}

# ===========================================================================
# FULL RESTORE
# ===========================================================================

function Invoke-RestauracionCompleta {
    param([string]$Carpeta)

    Write-Titulo "FULL RESTORE FROM $(Split-Path $Carpeta -Leaf)"

    # 1) Firewall
    $wfw = Join-Path $Carpeta 'firewall.wfw'
    if (Test-Path $wfw) {
        & netsh.exe advfirewall reset > $null 2>&1
        $r = & netsh.exe advfirewall import "$wfw" 2>&1
        Write-Bitacora "firewall restored ($r)" 'CHANGE'
    } else { Write-Bitacora 'there is no firewall.wfw in this backup' 'ERROR' }

    foreach ($n in @('Sentinel-No-Ping-IPv4','Sentinel-No-Ping-IPv6','Sentinel-Hardening-Local-Subnet')) {
        try { Remove-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue } catch { }
    }
    try { Remove-NetFirewallRule -DisplayName 'Sentinel-VM-Isolated-*' -ErrorAction SilentlyContinue } catch { }

    # 2) Registry
    $n = 0
    foreach ($f in Get-ChildItem $Carpeta -Filter '*.reg' -ErrorAction SilentlyContinue) {
        & reg.exe import "$($f.FullName)" > $null 2>&1
        if ($LASTEXITCODE -eq 0) { $n++; Write-Bitacora "registry restored: $($f.BaseName)" 'CHANGE' }
        else { Write-Bitacora "could not import $($f.BaseName)" 'WARN' }
    }
    Write-Bitacora "registry keys restored: $n" 'OK'

    # 3) Services, back to the exact state they had
    $js = Join-Path $Carpeta 'state.json'
    if (Test-Path $js) {
        try {
            $est = Get-Content $js -Raw | ConvertFrom-Json
            $n = 0
            foreach ($s in $est.servicios) {
                try {
                    $actual = Get-Service -Name $s.Name -ErrorAction Stop
                    if ($actual.StartType -ne $s.StartType) {
                        Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction Stop
                        $n++
                    }
                    if ($s.Status -eq 'Running' -and $actual.Status -ne 'Running') {
                        Start-Service -Name $s.Name -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
            Write-Bitacora "services back to their original state: $n corrected" 'CHANGE'

            # DNS
            foreach ($d in $est.dns) {
                try {
                    if ($d.ServerAddresses -and $d.ServerAddresses.Count -gt 0) {
                        Set-DnsClientServerAddress -InterfaceIndex $d.InterfaceIndex -ServerAddresses $d.ServerAddresses -ErrorAction Stop
                        Write-Bitacora "DNS of $($d.InterfaceAlias) set back to $($d.ServerAddresses -join ', ')" 'CHANGE'
                    }
                } catch { }
            }

            # NetBIOS
            foreach ($nb in $est.netbios) {
                try {
                    $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "SettingID='$($nb.SettingID)'" -ErrorAction Stop
                    if ($cfg) { Invoke-CimMethod -InputObject $cfg -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]$nb.TcpipNetbiosOptions } -ErrorAction SilentlyContinue | Out-Null }
                } catch { }
            }
        } catch { Write-Bitacora "state.json unreadable: $($_.Exception.Message)" 'ERROR' }
    }

    # 4) VMware adapters
    foreach ($vmnet in @('VMware Network Adapter VMnet1','VMware Network Adapter VMnet8')) {
        try { Enable-NetAdapter -Name $vmnet -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    }

    # 5) .vmx files: if there is a Sentinel copy, it is put back.
    $n = 0
    foreach ($base in @("$env:USERPROFILE\Documents\Virtual Machines", "$env:USERPROFILE\vmware", 'D:\VMs')) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -Filter '*.vmx.sentinel-copy' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $orig = $_.FullName -replace '\.sentinel-copy$',''
            try { Copy-Item $_.FullName $orig -Force -ErrorAction Stop; $n++ } catch { }
        }
    }
    if ($n) { Write-Bitacora ".vmx files back to their original version: $n" 'CHANGE' }

    Disable-Reversor -Silencioso

    Write-Host ''
    Write-Titulo 'CHECKING'
    Test-Conectividad | Out-Null
    Write-Host ''
    Write-Host '  Restore finished. RESTART so everything goes back in place.' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Note: Defender preferences (CFA, ASR rules, network protection)' -ForegroundColor DarkGray
    Write-Host '  are NOT reverted here on purpose: they are protections, not system' -ForegroundColor DarkGray
    Write-Host '  configuration, and removing them leaves you worse off than before. If you' -ForegroundColor DarkGray
    Write-Host '  really want to undo them:' -ForegroundColor DarkGray
    Write-Host '     Set-MpPreference -EnableControlledFolderAccess Disabled' -ForegroundColor White
    Write-Host ''
}

# ===========================================================================
# MAIN
# ===========================================================================

Write-Host ''
Write-Host '   #############################################################' -ForegroundColor DarkCyan
Write-Host '   #           S E N T I N E L   --   R E S T O R E            #' -ForegroundColor White
Write-Host '   #############################################################' -ForegroundColor DarkCyan

if ($ListBackups) { Show-Respaldos | Out-Null; return }

if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos @(
    $(if ($Emergency)   { '-Emergency' })
    $(if ($NoPrompt) { '-NoPrompt' })
    $(if ($Backup)     { '-Backup'; $Backup })
) )) { return }

if ($Emergency) { Invoke-Emergency; return }

$destino = $null
if ($Backup) {
    $destino = if (Test-Path $Backup) { $Backup } else { Join-Path $script:DirResp $Backup }
    if (-not (Test-Path $destino)) { Write-Host "  Does not exist: $destino" -ForegroundColor Red; return }
} else {
    $lista = Show-Respaldos
    if (-not $lista) { return }
    if ($NoPrompt) {
        $destino = $lista[0].FullName
    } else {
        $sel = Read-Host '  Number to restore (Enter = the most recent, X = exit)'
        if ($sel -match '^[xX]') { Write-Host '  Cancelled.' -ForegroundColor Green; return }

        if ([string]::IsNullOrWhiteSpace($sel)) {
            $destino = $lista[0].FullName
        } elseif ($sel -match '^\s*\d+\s*$' -and ([int]$sel) -ge 1 -and ([int]$sel) -le $lista.Count) {
            $destino = $lista[[int]$sel - 1].FullName
        } else {
            # Restoring is a delicate operation: on an answer that is not understood,
            # it exits. Guessing here would mean restoring a backup the user did
            # not ask for.
            Write-Host "  '$sel' is not a valid option (there are $($lista.Count) backups)." -ForegroundColor Red
            Write-Host '  Nothing is touched. Run it again and pick a number from the list.' -ForegroundColor Yellow
            return
        }
    }
}

Write-Host ''
Write-Host "  About to restore: $destino" -ForegroundColor Yellow
if (-not $NoPrompt) {
    if ((Read-Host '  Type RESTORE to confirm') -ne 'RESTORE') {
        Write-Host '  Cancelled. Nothing was touched.' -ForegroundColor Green; return
    }
}

Invoke-RestauracionCompleta -Carpeta $destino
