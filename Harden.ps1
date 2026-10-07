<#
.SYNOPSIS
    Windows 11 Home hardening. Layer by layer, with a backup, a connectivity
    check after each layer and a timed reverter.

.DESCRIPTION
    WITHOUT ARGUMENTS IT CHANGES NOTHING. It prints what it would do and exits.
    To apply for real you have to type -Apply.

    Layers:
      1  defender     Defender at maximum, CFA, full ASR, network protection
      2  ports        Strict firewall, rule sweep, exposed services
      3  locks        UAC, WSH, PowerShell v2, autorun, macros, auditing
      4  privacy      Minimum telemetry, location, advertising, Recall, DNS
      5  stealth      Silence on the local network: no discovery, no ping
      6  vm           VMware isolation: VMs do not touch the physical network
      7  drivers      Vulnerable driver blocklist (anti-BYOVD)
      8  credentials  NTLMv2 only, no WDigest, no memory dumps
      9  ransomware   CFA, shadow copy protection, system restore

.EXAMPLE
    .\Harden.ps1
    Dry run. Touches nothing. This is what you should run first.

.EXAMPLE
    .\Harden.ps1 -Apply
    Applies the nine layers, with a 10-minute reverter on those that touch the network.

.EXAMPLE
    .\Harden.ps1 -Apply -Layers defender,ransomware
    Only those two layers.
#>

[CmdletBinding()]
param(
    [switch]$Apply,

    [ValidateSet('defender','ports','locks','privacy','stealth','vm','drivers','credentials','ransomware')]
    [string[]]$Layers = @('defender','ports','locks','privacy','stealth','vm','drivers','credentials','ransomware'),

    [int]$RevertMinutes = 10,

    # Skips the human confirmation. Only for unattended use: if connectivity
    # fails it still reverts by itself, but you lose the last filter.
    [switch]$NoPrompt,

    # Randomizes the Wi-Fi MAC. Disconnects and reconnects the adapter.
    [switch]$RandomizeMAC,

    # Cuts the Windows connectivity probe. Side effect: the network icon
    # will say "no internet" forever, even though you can browse.
    [switch]$CutMicrosoftProbe,

    # Blocks outbound traffic by default. Do NOT use without an allow list.
    [switch]$BlockOutbound,

    # Passed by Run-All.ps1: we are already elevated and the user already said yes,
    # so there is no need to ask again. It does NOT affect the confirmation that there
    # is still internet: that one always stays, it is the one that really protects.
    [switch]$Orchestrated
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')

$Simular = -not $Apply

# ---------------------------------------------------------------------------

function Show-Cabecera {
    if (-not $Orchestrated) { Clear-Host }
    Write-Host ''
    Write-Host '   #############################################################' -ForegroundColor DarkCyan
    Write-Host '   #                     S E N T I N E L                       #' -ForegroundColor White
    Write-Host '   #              Windows 11 Home hardening                    #' -ForegroundColor DarkCyan
    Write-Host '   #############################################################' -ForegroundColor DarkCyan
    Write-Host ''
    if ($Simular) {
        Write-Host '   DRY RUN MODE. Absolutely nothing will be changed.' -ForegroundColor Green
        Write-Host '   To apply for real:  .\Harden.ps1 -Apply' -ForegroundColor DarkGray
    } else {
        Write-Host '   REAL MODE. Changes will be applied to the system.' -ForegroundColor Yellow
    }
    Write-Host ("   Layers: " + ($Layers -join ', ')) -ForegroundColor DarkGray
    Write-Host ("   Log: " + $script:Log) -ForegroundColor DarkGray
    Write-Host ''
}

# ===========================================================================
# LAYER 1 -- DEFENDER AT MAXIMUM
# Connectivity risk: none.
# ===========================================================================

function Invoke-CapaDefender {
    Write-Titulo 'LAYER 1 -- DEFENDER AT MAXIMUM'

    Set-PreferenciaDefender -Nombre 'EnableNetworkProtection' -Valor 1 -Simular:$Simular `
        -Motivo 'cuts connections to command and control domains' | Out-Null
    Set-PreferenciaDefender -Nombre 'CloudBlockLevel' -Valor 2 -Simular:$Simular `
        -Motivo 'cloud block at high level' | Out-Null
    Set-PreferenciaDefender -Nombre 'CloudExtendedTimeout' -Valor 50 -Simular:$Simular `
        -Motivo 'gives the cloud time to decide before letting a binary run' | Out-Null
    Set-PreferenciaDefender -Nombre 'PUAProtection' -Valor 1 -Simular:$Simular `
        -Motivo 'blocks unwanted software' | Out-Null
    Set-PreferenciaDefender -Nombre 'MAPSReporting' -Valor 2 -Simular:$Simular `
        -Motivo 'advanced cloud protection' | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableRemovableDriveScanning' -Valor $false -Simular:$Simular `
        -Motivo 'scan USB drives when plugged in' | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableArchiveScanning' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableEmailScanning' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableBehaviorMonitoring' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableScriptScanning' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'ScanScheduleDay' -Valor 0 -Simular:$Simular `
        -Motivo 'weekly full scan' | Out-Null
    Set-PreferenciaDefender -Nombre 'SignatureUpdateInterval' -Valor 2 -Simular:$Simular `
        -Motivo 'signatures every 2 hours' | Out-Null

    # --- ASR rules ----------------------------------------------------------
    # All 19 rules. The one for prevalence-based executables goes in AUDIT,
    # not block: it would break your own compiled executables, which by
    # definition have no prevalence.
    Write-Host ''
    Write-Bitacora 'attack surface reduction (ASR) rules' 'INFO'

    $asr = [ordered]@{
        '56A863A9-875E-4185-98A7-B882C64B5CE5' = @(1,'abuse of exploited vulnerable signed drivers')
        '7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C' = @(1,'Adobe Reader creating child processes')
        'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' = @(1,'Office creating child processes')
        '9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2' = @(1,'CREDENTIAL THEFT FROM LSASS')
        'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550' = @(1,'executables arriving by email')
        '5BEB7EFE-FD9A-4556-801D-275E5FFC04CC' = @(1,'obfuscated scripts')
        'D3E037E1-3EB8-44C8-A917-57927947596D' = @(1,'JS/VBS launching downloaded executables')
        '3B576869-A4EC-4529-8536-B80A7769E899' = @(1,'Office creating executable content')
        '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84' = @(1,'Office injecting into other processes')
        '26190899-1602-49E8-8B27-EB1D0A1CE869' = @(1,'Outlook creating child processes')
        'E6DB77E5-3DF2-4CF1-B95A-636979351E5B' = @(1,'persistence through WMI event subscription')
        'D1E49AAC-8F56-4280-B9BA-993A6D77406C' = @(1,'processes created by PsExec and WMI')
        '33DDEDF1-C6E0-47CB-833E-DE6133960387' = @(1,'REBOOT INTO SAFE MODE -- it is how ransomware dodges the antivirus')
        'B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4' = @(1,'unsigned processes from USB')
        'C0033C00-D16D-4114-A5A0-DC9B3A7D2CEB' = @(1,'copied or impersonated system tools')
        '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B' = @(1,'Win32 calls from Office macros')
        'C1DB55AB-C21A-4637-BB3F-A12568109D35' = @(1,'advanced ransomware protection')
        'A8F5898E-1DC8-49A9-9878-85004B8A61E6' = @(1,'webshell creation')
        '01443614-CD74-433A-B99E-2ECDC07BFC25' = @(2,'low-prevalence executables -- IN AUDIT so your own .exe files keep working')
    }

    foreach ($id in $asr.Keys) {
        $accion = $asr[$id][0]
        $texto  = $asr[$id][1]
        if ($Simular) {
            Write-Bitacora ("DRY RUN -> ASR {0} = {1}  ({2})" -f $id.Substring(0,8), $accion, $texto) 'DRYRUN'
            continue
        }
        try {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions $accion -ErrorAction Stop
            Write-Bitacora ("ASR {0} = {1}  ({2})" -f $id.Substring(0,8), $accion, $texto) 'CHANGE'
        } catch {
            Write-Bitacora ("ASR {0} FAILED: {1}" -f $id.Substring(0,8), $_.Exception.Message) 'WARN'
        }
    }

    # --- Honest check -------------------------------------------------------
    if (-not $Simular) {
        $p = Get-MpPreference
        $puestas = if ($p.AttackSurfaceReductionRules_Ids) { $p.AttackSurfaceReductionRules_Ids.Count } else { 0 }
        Write-Bitacora "ASR rules active now: $puestas of 19" $(if ($puestas -ge 19) { 'OK' } else { 'WARN' })
    }
}

# ===========================================================================
# LAYER 2 -- CLOSE THE DOORS
# Risk: low. Outbound stays intact. Reverter armed anyway.
# ===========================================================================

function Invoke-CapaPuertos {
    Write-Titulo 'LAYER 2 -- CLOSE THE DOORS'

    # --- Explicit firewall --------------------------------------------------
    # NotConfigured inherits the default, but an inherited value is a value
    # someone can change without it being noticed. It is made explicit.
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> inbound BLOCKED by default on all three profiles; outbound INTACT' 'DRYRUN'
        Write-Bitacora 'DRY RUN -> firewall logging enabled (32 MB per profile)' 'DRYRUN'
    } else {
        try {
            Set-NetFirewallProfile -Profile Domain,Private,Public `
                -Enabled True `
                -DefaultInboundAction Block `
                -DefaultOutboundAction Allow `
                -NotifyOnListen True `
                -LogBlocked True -LogAllowed False -LogMaxSizeKilobytes 32767 `
                -LogFileName '%systemroot%\system32\LogFiles\Firewall\pfirewall.log' `
                -ErrorAction Stop
            Write-Bitacora 'inbound blocked by default on all three profiles; outbound intact' 'CHANGE'
            Write-Bitacora 'firewall logging enabled -- without a log there is no forensics' 'CHANGE'
        } catch {
            Write-Bitacora "FAILED configuring profiles: $($_.Exception.Message)" 'ERROR'
        }
    }

    # --- Inbound rule sweep -------------------------------------------------
    # They are DISABLED, not deleted. Going back means setting Enabled True.
    Write-Host ''
    Write-Bitacora 'inbound rule sweep' 'INFO'

    # a) Discovery groups that have no business on someone else's network
    $gruposFuera = @(
        # The comparison ignores accents and case, so a piece of the name is
        # enough. Each group is listed in Spanish and English because Windows
        # shows the names in its own language.
        'Deteccion de redes','Network Discovery',
        'Wi-Fi Direct','WFD','Servicio WLAN',
        'Proyeccion inalambrica','Projection',
        'Optimizacion de distribucion','Delivery Optimization', # Windows Update P2P
        'Plataforma de dispositivos conectados','Connected Devices Platform',
        'MyASUS',
        'Funcionalidad de transmitir en dispositivo','Cast to Device',
        'Teredo',
        'mDNS',
        'Uso compartido de proximidad','Proximity Sharing',
        'Fuente de red de Microsoft Media Foundation','Media Foundation Network Source',
        'Uso compartido de archivos e impresoras','File and Printer Sharing',
        'AllJoyn Router',
        'Deteccion de funcion','Function Discovery',
        'Paquete de experiencia de caracteristicas de Windows','Windows Feature Experience'
    )
    # All the queries below go through Get-ReglasEntrada, and not on a whim:
    # "Get-NetFirewallRule -DisplayName X -Direction Inbound" is a PowerShell
    # ERROR -- those parameters live in different sets and cannot be combined.
    # The first version did it that way, inside an empty catch, and the result
    # was that three whole sweeps returned zero without any warning. It queries
    # by a single criterion and filters afterwards.
    $n = 0
    foreach ($g in $gruposFuera) {
        $reglas = Get-ReglasEntrada -Grupo $g -SoloHabilitadas
        foreach ($r in $reglas) {
            if ($Simular) { Write-Bitacora "DRY RUN -> disable '$($r.DisplayName)'" 'DRYRUN' }
            else { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
            $n++
        }
    }
    Write-Bitacora "discovery rules disabled: $n" $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })

    # b) Own services that ONLY listen on 127.0.0.1.
    #    The Windows firewall does not filter loopback: these rules
    #    add nothing and only add attack surface. Removing them breaks nothing.
    $soloLocal = @('python.exe','Node.js JavaScript Runtime','LM Studio','postman.exe',
                   'Packet Tracer Executable','podman desktop.exe','Microsoft Office Outlook',
                   'AsusSwitchNet','AsusSwitchNetMDNS','MyASUS')
    $n = 0
    foreach ($nombre in $soloLocal) {
        foreach ($r in (Get-ReglasEntrada -Nombre $nombre -SoloHabilitadas)) {
            if ($Simular) { Write-Bitacora "DRY RUN -> disable inbound for '$($r.DisplayName)'" 'DRYRUN' }
            else { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
            $n++
        }
    }
    Write-Bitacora "rules for services that only listen locally: $n disabled" $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })

    # c) What must never accept connections.
    #    adb.exe is the serious case when its rule points to a temporary folder:
    #    a replaceable binary in a temp path with inbound allowed on public
    #    networks is a backdoor waiting for someone to use it.
    $prohibidos = @('adb.exe','lolminer.exe','zephyrd.exe')
    $n = 0
    foreach ($nombre in $prohibidos) {
        foreach ($r in (Get-ReglasEntrada -Nombre $nombre)) {
            if ($Simular) { Write-Bitacora "DRY RUN -> DELETE inbound rule '$($r.DisplayName)'" 'DRYRUN' }
            else {
                try { Remove-NetFirewallRule -Name $r.Name -ErrorAction Stop }
                catch { Write-Bitacora "could not delete '$($r.DisplayName)': $($_.Exception.Message)" 'WARN'; continue }
            }
            $n++
        }
    }
    Write-Bitacora "inbound rules deleted (adb, miners): $n" $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })

    # d) Games: they stay on private networks and leave the public one.
    $juegos = @('Steam','Steam Web Helper','Grand Theft Auto V Enhanced','God of War','Fallout 4','Game Bar')
    $n = 0
    foreach ($nombre in $juegos) {
        foreach ($r in (Get-ReglasEntrada -Nombre $nombre -SoloHabilitadas)) {
            if ($r.Profile -match 'Public' -or $r.Profile -eq 'Any') {
                if ($Simular) { Write-Bitacora "DRY RUN -> '$($r.DisplayName)' out of the public profile" 'DRYRUN' }
                else {
                    try { Set-NetFirewallRule -Name $r.Name -Profile Domain,Private -ErrorAction Stop }
                    catch { Write-Bitacora "could not move '$($r.DisplayName)': $($_.Exception.Message)" 'WARN'; continue }
                }
                $n++
            }
        }
    }
    Write-Bitacora "game rules taken out of the public profile: $n" $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })

    # e) Edge mDNS duplicates piled up by updates
    try {
        $dup = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction Stop |
               Where-Object { $_.DisplayName -like '*mDNS*' }
        $n = ($dup | Measure-Object).Count
        if (-not $Simular) { $dup | ForEach-Object { Disable-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue } }
        Write-Bitacora "mDNS rules disabled: $n" $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })
    } catch { }

    # --- SMB: encryption and no anonymous access ----------------------------
    # This goes BEFORE stopping LanmanServer: with the service stopped, some of
    # these settings fail. First it is hardened, then it is turned off.
    Write-Host ''
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> SMB: encryption required, signing required, no SMB1' 'DRYRUN'
    } else {
        # Careful: -EnableInsecureGuestLogons does NOT exist in Set-SmbServerConfiguration
        # (it belongs to the Client variant). Putting it here made the WHOLE command
        # fail, so none of the server SMB settings were applied. And since each
        # setting goes separately, if one fails the others still get in.
        $ajustesSmb = [ordered]@{
            EnableSMB1Protocol       = $false
            RequireSecuritySignature = $true
            EncryptData              = $true
            RejectUnencryptedAccess  = $true
        }
        $puestos = 0
        foreach ($k in $ajustesSmb.Keys) {
            $arg = @{ $k = $ajustesSmb[$k] }
            try { Set-SmbServerConfiguration @arg -Force -ErrorAction Stop; $puestos++ }
            catch { Write-Bitacora "SMB server, $k : $($_.Exception.Message)" 'WARN' }
        }
        Write-Bitacora "SMB server hardened: $puestos of $($ajustesSmb.Count) settings" `
            $(if ($puestos -eq $ajustesSmb.Count) { 'CHANGE' } else { 'WARN' })
        try {
            Set-SmbClientConfiguration -RequireSecuritySignature $true -EnableInsecureGuestLogons $false `
                -Force -ErrorAction Stop
            Write-Bitacora 'SMB client: signing required, no insecure guest logons' 'CHANGE'
        } catch { Write-Bitacora "SMB client: $($_.Exception.Message)" 'WARN' }
    }

    # --- Exposed services ---------------------------------------------------
    Write-Host ''
    Write-Bitacora 'remote access and exposure services' 'INFO'

    Set-EstadoServicio -Nombre 'WinRM' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'it was LISTENING on ::5985 and ::47001, remote management open on foreign Wi-Fi' | Out-Null
    Set-EstadoServicio -Nombre 'LanmanServer' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'it published ADMIN$, C$ and IPC$ with port 445 on every interface' | Out-Null
    Set-EstadoServicio -Nombre 'SSDPSRV' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'UPnP discovery, unnecessary' | Out-Null
    Set-EstadoServicio -Nombre 'upnphost' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'RemoteRegistry' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'RemoteAccess' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'SessionEnv' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'TermService' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'remote desktop, already denied by registry' | Out-Null
    Set-EstadoServicio -Nombre 'UmRdpService' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'WMPNetworkSvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'WerSvc' -Arranque Manual -Simular:$Simular | Out-Null

    # LanmanWorkstation STAYS: it is the client. Without it you could not reach
    # other people's shares. What is turned off is the server.

    # --- RDP and remote assistance through the registry ---------------------
    Set-ValorRegistro -Ruta 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Nombre 'fDenyTSConnections' -Valor 1 -Simular:$Simular -Motivo 'remote desktop denied' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Nombre 'fAllowToGetHelp' -Valor 0 -Simular:$Simular -Motivo 'remote assistance denied' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Nombre 'fAllowUnsolicited' -Valor 0 -Simular:$Simular | Out-Null
}

# ===========================================================================
# LAYER 3 -- SYSTEM LOCKS
# ===========================================================================

function Invoke-CapaCerrojos {
    Write-Titulo 'LAYER 3 -- SYSTEM LOCKS'

    $pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    # UAC at maximum. ConsentPromptBehaviorAdmin = 2 ALWAYS asks for consent,
    # even for Windows binaries. That defeats the bypasses that abuse
    # auto-elevating executables: fodhelper, computerdefaults, sdclt, eventvwr.
    # Price: more prompts. It is the right price.
    Set-ValorRegistro -Ruta $pol -Nombre 'EnableLUA' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'ConsentPromptBehaviorAdmin' -Valor 2 -Simular:$Simular `
        -Motivo 'consent ALWAYS: closes UAC bypasses through auto-elevation' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'ConsentPromptBehaviorUser' -Valor 0 -Simular:$Simular `
        -Motivo 'standard users cannot elevate' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'PromptOnSecureDesktop' -Valor 1 -Simular:$Simular `
        -Motivo 'secure desktop: no program can fake the prompt' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'FilterAdministratorToken' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'EnableInstallerDetection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'EnableSecureUIAPaths' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'ValidateAdminCodeSignatures' -Valor 1 -Simular:$Simular `
        -Motivo 'only signed, valid code is elevated' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'LocalAccountTokenFilterPolicy' -Valor 0 -Simular:$Simular `
        -Motivo 'prevents remote elevation with a local account' | Out-Null

    # Windows Script Host: kills double-click .vbs and .js files, the classic
    # ransomware vector by email.
    #
    # BUT if the computer has its own launchers written as .vbs, turning WSH off
    # outright breaks them. So they are first migrated to equivalents that do not
    # need it, and it is turned off ONLY if the migration goes well.
    Write-Host ''
    Write-Bitacora 'before touching Windows Script Host: migrating your .vbs launchers' 'INFO'
    $migrador = Join-Path $PSScriptRoot 'Migrate-Launchers.ps1'
    $seguro = $false
    if (Test-Path $migrador) {
        try {
            $seguro = if ($Simular) { & $migrador } else { & $migrador -Apply }
            $seguro = [bool]($seguro | Select-Object -Last 1)
        } catch {
            Write-Bitacora "the migrator failed: $($_.Exception.Message)" 'ERROR'
            $seguro = $false
        }
    } else {
        Write-Bitacora "cannot find $migrador" 'ERROR'
    }

    if ($seguro) {
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' `
            -Nombre 'Enabled' -Valor 0 -Simular:$Simular -Motivo 'no double-click .vbs or .js' | Out-Null
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows Script Host\Settings' `
            -Nombre 'Enabled' -Valor 0 -Simular:$Simular | Out-Null
    } else {
        Write-Bitacora 'WINDOWS SCRIPT HOST STAYS ENABLED.' 'WARN'
        Write-Bitacora 'The migration of your launchers did not go cleanly, and breaking your' 'WARN'
        Write-Bitacora 'launchers is worse than leaving WSH on. Fix the' 'WARN'
        Write-Bitacora 'migration and run again:  .\Harden.ps1 -Apply -Layers locks' 'WARN'
    }

    # Autorun / Autoplay: 255 = all drives.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Nombre 'NoDriveTypeAutoRun' -Valor 255 -Simular:$Simular -Motivo 'hostile USB' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Nombre 'NoAutorun' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' `
        -Nombre 'NoAutoplayfornonVolume' -Valor 1 -Simular:$Simular | Out-Null

    # Visible extensions: so invoice.pdf.exe stops disguising itself.
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Nombre 'HideFileExt' -Valor 0 -Simular:$Simular -Motivo 'always see the real extension' | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Nombre 'Hidden' -Valor 1 -Simular:$Simular | Out-Null

    # Office macros from the internet: blocked.
    foreach ($app in 'Word','Excel','PowerPoint','Access','Publisher','Outlook','Visio') {
        Set-ValorRegistro -Ruta "HKCU:\SOFTWARE\Microsoft\Office\16.0\$app\Security" `
            -Nombre 'BlockContentExecutionFromInternet' -Valor 1 -Simular:$Simular | Out-Null
        Set-ValorRegistro -Ruta "HKCU:\SOFTWARE\Microsoft\Office\16.0\$app\Security" `
            -Nombre 'VBAWarnings' -Valor 4 -Simular:$Simular | Out-Null
    }
    Write-Bitacora 'Office macros from the internet: blocked' $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })

    # PowerShell script block logging and command line in event 4688.
    # Without this, a PowerShell attack leaves no reconstructable trace.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' `
        -Nombre 'EnableScriptBlockLogging' -Valor 1 -Simular:$Simular `
        -Motivo 'every script block is logged' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' `
        -Nombre 'EnableModuleLogging' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames' `
        -Nombre '*' -Valor '*' -Tipo String -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' `
        -Nombre 'ProcessCreationIncludeCmdLine_Enabled' -Valor 1 -Simular:$Simular `
        -Motivo 'event 4688 will include the full command line' | Out-Null

    if ($Simular) {
        Write-Bitacora 'DRY RUN -> process, logon and policy auditing' 'DRYRUN'
        Write-Bitacora 'DRY RUN -> PowerShell v2 removed' 'DRYRUN'
    } else {
        # The subcategory name depends on the language of Windows, hence both.
        foreach ($cat in @('Creacion de procesos','Process Creation')) {
            & auditpol.exe /set /subcategory:"$cat" /success:enable /failure:enable > $null 2>&1
        }
        foreach ($guid in @('{0CCE922B-69AE-11D9-BED3-505054503030}',  # Process creation
                            '{0CCE9215-69AE-11D9-BED3-505054503030}',  # Logon
                            '{0CCE9217-69AE-11D9-BED3-505054503030}',  # Logoff
                            '{0CCE9228-69AE-11D9-BED3-505054503030}',  # Sensitive privilege use
                            '{0CCE922F-69AE-11D9-BED3-505054503030}',  # Audit policy change
                            '{0CCE9235-69AE-11D9-BED3-505054503030}',  # User account management
                            '{0CCE9226-69AE-11D9-BED3-505054503030}')) { # System services
            & auditpol.exe /set /subcategory:"$guid" /success:enable /failure:enable > $null 2>&1
        }
        Write-Bitacora 'auditing enabled: processes, logons, privileges, policy changes' 'CHANGE'

        # PowerShell v2: closes the downgrade attack that evades logging.
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop
            if ($f.State -eq 'Enabled') {
                Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -ErrorAction Stop | Out-Null
                Write-Bitacora 'PowerShell v2 removed: no downgrade attack' 'CHANGE'
            } else { Write-Bitacora 'PowerShell v2 was already gone' 'INFO' }
        } catch { Write-Bitacora "PowerShell v2: $($_.Exception.Message)" 'WARN' }

        # Larger event logs: the factory ones are overwritten within days.
        foreach ($lg in @('Security','System','Application','Microsoft-Windows-PowerShell/Operational',
                          'Microsoft-Windows-Windows Defender/Operational')) {
            & wevtutil.exe sl "$lg" /ms:196608000 > $null 2>&1
        }
        Write-Bitacora 'event logs enlarged to 192 MB: history survives for weeks' 'CHANGE'
    }
}

# ===========================================================================
# LAYER 4 -- PRIVACY AND TELEMETRY
# ===========================================================================

function Invoke-CapaPrivacidad {
    Write-Titulo 'LAYER 4 -- PRIVACY AND TELEMETRY'

    Write-Bitacora 'HONEST WARNING: on Windows 11 HOME the telemetry value 0 is only' 'WARN'
    Write-Bitacora 'respected by Enterprise and Education. Here the real floor is 1' 'WARN'
    Write-Bitacora '(Required). It is set to 0 anyway just in case, but do not rely on it.' 'WARN'

    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'AllowTelemetry' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' `
        -Nombre 'AllowTelemetry' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'AllowDeviceNameInTelemetry' -Valor 0 -Simular:$Simular `
        -Motivo 'the computer name does not travel' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'DoNotShowFeedbackNotifications' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'LimitDiagnosticLogCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'LimitDumpCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'DisableOneSettingsDownloads' -Valor 1 -Simular:$Simular | Out-Null

    # Advertising and identifiers
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' `
        -Nombre 'DisabledByGroupPolicy' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' `
        -Nombre 'Enabled' -Valor 0 -Simular:$Simular | Out-Null

    # Activity history and timeline
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'PublishUserActivities' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'UploadUserActivities' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'EnableActivityFeed' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'AllowCrossDeviceClipboard' -Valor 0 -Simular:$Simular | Out-Null

    # Recall and Windows AI: no screenshots of everything you do.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' `
        -Nombre 'DisableAIDataAnalysis' -Valor 1 -Simular:$Simular `
        -Motivo 'Recall off: no continuous screen captures' | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' `
        -Nombre 'DisableAIDataAnalysis' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' `
        -Nombre 'AllowRecallEnablement' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' `
        -Nombre 'TurnOffWindowsCopilot' -Valor 1 -Simular:$Simular | Out-Null

    # Suggested content, system advertising and Bing in the Start menu
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Nombre 'DisableWindowsConsumerFeatures' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Nombre 'DisableSoftLanding' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' `
        -Nombre 'DisableCloudOptimizedContent' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
        -Nombre 'SilentInstalledAppsEnabled' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' `
        -Nombre 'SubscribedContent-338388Enabled' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
        -Nombre 'DisableWebSearch' -Valor 1 -Simular:$Simular -Motivo 'what you type in Start does not go to the internet' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
        -Nombre 'ConnectedSearchUseWeb' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
        -Nombre 'AllowCortana' -Valor 0 -Simular:$Simular | Out-Null

    # Delivery Optimization. By default your computer HANDS OUT pieces of
    # updates to strangers over the internet, and that is why it listens on 7680
    # on every interface. With 0 it only downloads over HTTP and that port
    # closes. Windows Update keeps working the same.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' `
        -Nombre 'DODownloadMode' -Valor 0 -Simular:$Simular `
        -Motivo 'no P2P: closes port 7680 and you stop handing out to strangers' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' `
        -Nombre 'DODownloadMode' -Valor 0 -Simular:$Simular | Out-Null

    # Typing, speech and ink
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' `
        -Nombre 'RestrictImplicitTextCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' `
        -Nombre 'RestrictImplicitInkCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' `
        -Nombre 'AllowInputPersonalization' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' `
        -Nombre 'AllowSpeechModelUpdate' -Valor 0 -Simular:$Simular | Out-Null

    # LOCATION -- often set to Allow at machine AND user level.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' `
        -Nombre 'Value' -Valor 'Deny' -Tipo String -Simular:$Simular -Motivo 'location closed for the whole computer' | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' `
        -Nombre 'Value' -Valor 'Deny' -Tipo String -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Nombre 'DisableLocation' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Nombre 'DisableLocationScripting' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Nombre 'DisableWindowsLocationProvider' -Valor 1 -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'lfsvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'geolocation service' | Out-Null

    # Other collectors
    Set-EstadoServicio -Nombre 'DiagTrack' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'connected user experiences and telemetry' | Out-Null
    Set-EstadoServicio -Nombre 'dmwappushservice' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'diagnosticshub.standardcollector.service' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'RetailDemo' -Arranque Disabled -Detener -Simular:$Simular | Out-Null

    # Commercial suggestion tasks (the SoftLanding ones)
    if (-not $Simular) {
        $tareasFuera = @(
            '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\Feedback\Siuf\DmClient',
            '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
            '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
        )
        $n = 0
        foreach ($t in $tareasFuera) {
            $ruta = Split-Path $t -Parent
            $nom  = Split-Path $t -Leaf
            try { Disable-ScheduledTask -TaskPath "$ruta\" -TaskName $nom -ErrorAction Stop | Out-Null; $n++ } catch { }
        }
        try {
            Get-ScheduledTask -TaskPath '\SoftLanding\*' -ErrorAction Stop |
                Where-Object { $_.State -ne 'Disabled' } |
                ForEach-Object { Disable-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction SilentlyContinue | Out-Null; $n++ }
        } catch { }
        Write-Bitacora "telemetry and suggestion tasks disabled: $n" 'CHANGE'
    } else {
        Write-Bitacora 'DRY RUN -> disable telemetry, CEIP and SoftLanding tasks' 'DRYRUN'
    }

    # --- DNS -----------------------------------------------------------------
    # If the adapter points to a dead 127.0.0.1, every query waits for a dead
    # server before falling back. 1.1.1.2 / 1.0.0.2 are Cloudflare's resolvers
    # that also block malware.
    $wifi = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'VMware|Npcap|Loopback|Virtual' } |
            Select-Object -First 1
    # If Movie-Grade left Unbound resolving locally, DNS is already
    # better than with any third party: it is not touched.
    $unbound = Get-Service -Name 'unbound' -ErrorAction SilentlyContinue
    if ($unbound -and $unbound.Status -eq 'Running') {
        Write-Bitacora 'DNS: resolved by Unbound on this computer (Movie-Grade); not touched' 'INFO'
        $wifi = $null
    }
    if ($wifi) {
        if ($Simular) {
            Write-Bitacora "DRY RUN -> DNS of '$($wifi.Name)' = 1.1.1.2 and 1.0.0.2, with DNS over HTTPS" 'DRYRUN'
        } else {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $wifi.InterfaceIndex `
                    -ServerAddresses ('1.1.1.2','1.0.0.2') -ErrorAction Stop
                Write-Bitacora "DNS of '$($wifi.Name)' -> 1.1.1.2 / 1.0.0.2 (they block malware)" 'CHANGE'

                # DNS over HTTPS: your provider stops seeing which domains you visit.
                foreach ($srv in @(@('1.1.1.2','https://security.cloudflare-dns.com/dns-query'),
                                   @('1.0.0.2','https://security.cloudflare-dns.com/dns-query'))) {
                    try {
                        Add-DnsClientDohServerAddress -ServerAddress $srv[0] -DohTemplate $srv[1] `
                            -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop | Out-Null
                    } catch {
                        try { Set-DnsClientDohServerAddress -ServerAddress $srv[0] -DohTemplate $srv[1] `
                                -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop | Out-Null } catch { }
                    }
                }
                Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' `
                    -Nombre 'EnableAutoDoh' -Valor 2 -Simular:$false -Motivo 'encrypted DNS required' | Out-Null
                Write-Bitacora 'DNS over HTTPS enabled: your provider stops seeing the domains you visit' 'CHANGE'
                & ipconfig.exe /flushdns > $null 2>&1
            } catch { Write-Bitacora "DNS: $($_.Exception.Message)" 'WARN' }
        }
    }
}

# ===========================================================================
# LAYER 5 -- STEALTH ON THE LOCAL NETWORK
# "Do not show up on my network and still be connected."
# Risk: low, but it touches the network. Reverter armed.
# ===========================================================================

function Invoke-CapaSigilo {
    Write-Titulo 'LAYER 5 -- STEALTH ON THE LOCAL NETWORK'

    Write-Bitacora 'HONEST LIMIT: this removes you from the network map, from ping' 'WARN'
    Write-Bitacora 'replies and from every discovery protocol. It does NOT make you invisible:' 'WARN'
    Write-Bitacora 'whoever controls the router sees you in the ARP table and in DHCP, and anyone' 'WARN'
    Write-Bitacora 'on your network finds you with an ARP sweep. That is layer 2 physics' 'WARN'
    Write-Bitacora 'and no Windows setting changes it.' 'WARN'
    Write-Host ''

    # --- Discovery services --------------------------------------------------
    Set-EstadoServicio -Nombre 'FDResPub' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'resource publication: it is what announces you to others' | Out-Null
    Set-EstadoServicio -Nombre 'fdPHost' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'lltdsvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'link-layer topology: it is what draws you on the network map' | Out-Null
    Set-EstadoServicio -Nombre 'LanmanServer' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'CDPSvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'connected devices platform, listening on 0.0.0.0:5040' | Out-Null
    Set-EstadoServicio -Nombre 'CDPUserSvc' -Arranque Manual -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'DevicePickerUserSvc' -Arranque Disabled -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'DevicesFlowUserSvc' -Arranque Disabled -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'PNRPsvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'p2psvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'p2pimsvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'PNRPAutoReg' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'iphlpsvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'IPv6 tunnels (Teredo, 6to4, ISATAP): attack surface you do not use' | Out-Null

    # --- Insecure name resolution --------------------------------------------
    # LLMNR and NetBIOS are the basis of Responder attacks: someone on your
    # network answers "I am that computer" and takes your NTLM hash.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' `
        -Nombre 'EnableMulticast' -Valor 0 -Simular:$Simular `
        -Motivo 'LLMNR off: stops name poisoning' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' `
        -Nombre 'EnableMDNS' -Valor 0 -Simular:$Simular -Motivo 'mDNS off' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' `
        -Nombre 'NodeType' -Valor 2 -Simular:$Simular -Motivo 'NetBIOS point-to-point only, no broadcast' | Out-Null

    # NetBIOS over TCP/IP per adapter: 2 = disabled.
    # The default is 0 (= "whatever DHCP says"), that is, at the mercy of the network.
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> NetBIOS over TCP/IP disabled on every adapter' 'DRYRUN'
    } else {
        $n = 0
        try {
            Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop | ForEach-Object {
                $r = Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } -ErrorAction SilentlyContinue
                if ($r -and $r.ReturnValue -in @(0,1)) { $n++ }
            }
        } catch { }
        Write-Bitacora "NetBIOS over TCP/IP disabled on $n adapters" 'CHANGE'
    }

    # NoActiveProbe stays OUT of the default hardening, and not by oversight.
    #
    # It cuts the connectivity probe Windows makes against Microsoft, which
    # sounds good. The problem is the side effect: the network icon starts
    # showing "no internet" EVEN WHILE you browse perfectly, and several
    # applications that ask the Network List Manager believe it and behave
    # as if they were offline.
    #
    # Privacy gain: minimal. Cost: you go crazy thinking the hardening broke
    # your network when it did not. With -CutMicrosoftProbe it is enabled
    # anyway, knowing what it implies.
    if ($CutMicrosoftProbe) {
        Write-Bitacora 'WARN: the network icon will show "no internet" even though you can browse.' 'WARN'
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' `
            -Nombre 'NoActiveProbe' -Valor 1 -Simular:$Simular `
            -Motivo 'no active probe toward Microsoft (at the cost of the network indicator)' | Out-Null
    } else {
        Write-Bitacora 'Windows connectivity probe: left as it is.' 'INFO'
        Write-Bitacora '  Cutting it would make the network icon always say "no internet".' 'INFO'
        Write-Bitacora '  If you still want it:  .\Harden.ps1 -Apply -CutMicrosoftProbe' 'INFO'
    }

    # WPAD: automatic proxy detection is a classic interception vector.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' `
        -Nombre 'WpadOverride' -Valor 1 -Simular:$Simular -Motivo 'WPAD disabled' | Out-Null
    Set-EstadoServicio -Nombre 'WinHttpAutoProxySvc' -Arranque Manual -Simular:$Simular | Out-Null

    # --- Do not announce yourself through DNS or DHCP ------------------------
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
        -Nombre 'DisableDynamicUpdate' -Valor 1 -Simular:$Simular `
        -Motivo 'do not register your name in the DNS of someone else''s network' | Out-Null
    if (-not $Simular) {
        try {
            Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
                Set-DnsClient -InterfaceIndex $_.InterfaceIndex -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue
                Set-DnsClient -InterfaceIndex $_.InterfaceIndex -UseSuffixWhenRegistering $false -ErrorAction SilentlyContinue
            }
            Write-Bitacora 'adapters stop registering their address in the network DNS' 'CHANGE'
        } catch { }
    }

    # --- Do not answer ping --------------------------------------------------
    # ONLY echo (type 8) is blocked. Types 3 and 11 are let through: without
    # them path MTU discovery breaks and some websites stop loading.
    # This is the mistake that ruins connectivity in most guides.
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> no ping replies (echo only; ICMP types 3 and 11 preserved)' 'DRYRUN'
    } else {
        foreach ($sp in @(@('Sentinel-No-Ping-IPv4','ICMPv4','8:*'),
                          @('Sentinel-No-Ping-IPv6','ICMPv6','128:*'))) {
            try { Remove-NetFirewallRule -DisplayName $sp[0] -ErrorAction SilentlyContinue } catch { }
            try {
                New-NetFirewallRule -DisplayName $sp[0] -Direction Inbound -Action Block `
                    -Protocol $sp[1] -IcmpType $sp[2] -Profile Any -Enabled True `
                    -Description 'Do not answer echo. Types 3 and 11 are still allowed so MTU discovery keeps working.' `
                    -ErrorAction Stop | Out-Null
            } catch { Write-Bitacora "no-ping rule: $($_.Exception.Message)" 'WARN' }
        }
        Write-Bitacora 'the computer stops answering ping; ICMP types 3 and 11 preserved' 'CHANGE'
    }

    # --- Protect yourself from your own network ------------------------------
    # Explicit block of all inbound from the local subnet. Block rules weigh
    # more than allow rules, so this overrides any stray rule that slipped in.
    # It does NOT affect outbound or the replies to traffic you start.
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> explicit block of all inbound from the local subnet' 'DRYRUN'
    } else {
        try { Remove-NetFirewallRule -DisplayName 'Sentinel-Hardening-Local-Subnet' -ErrorAction SilentlyContinue } catch { }
        try {
            New-NetFirewallRule -DisplayName 'Sentinel-Hardening-Local-Subnet' `
                -Direction Inbound -Action Block -RemoteAddress LocalSubnet `
                -Profile Public,Private -Enabled True `
                -Description 'Nobody on the local network can start connections to this computer. Traffic YOU start keeps working: its replies are stateful traffic.' `
                -ErrorAction Stop | Out-Null
            Write-Bitacora 'nobody on your local network can start connections to you' 'CHANGE'
        } catch { Write-Bitacora "subnet rule: $($_.Exception.Message)" 'WARN' }
    }

    # --- Network profile always public ---------------------------------------
    if (-not $Simular) {
        try {
            Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $_.NetworkCategory -ne 'Public' } | ForEach-Object {
                Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Public -ErrorAction SilentlyContinue
                Write-Bitacora "profile of '$($_.Name)' set to Public" 'CHANGE'
            }
        } catch { }
    }

    # --- Random MAC: only if explicitly requested ----------------------------
    if ($RandomizeMAC) {
        Write-Bitacora 'WARN: changing the MAC disconnects and reconnects the Wi-Fi' 'WARN'
        if ($Simular) {
            Write-Bitacora 'DRY RUN -> Wi-Fi MAC randomized' 'DRYRUN'
        } else {
            try {
                $ad = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN' } | Select-Object -First 1
                if ($ad) {
                    # Unicast, locally administered: second bit of the first octet set to 1.
                    $b = 1..5 | ForEach-Object { '{0:X2}' -f (Get-Random -Min 0 -Max 256) }
                    $mac = '02' + ($b -join '')
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -RegistryKeyword 'NetworkAddress' -RegistryValue $mac -ErrorAction Stop
                    Restart-NetAdapter -Name $ad.Name -Confirm:$false -ErrorAction Stop
                    Write-Bitacora "Wi-Fi MAC changed to $mac (locally administered)" 'CHANGE'
                }
            } catch { Write-Bitacora "MAC: $($_.Exception.Message). Turn it on by hand in Settings > Network > Wi-Fi > Random hardware addresses." 'WARN' }
        }
    } else {
        Write-Bitacora 'MAC untouched. To randomize it: -RandomizeMAC (reconnects the Wi-Fi),' 'INFO'
        Write-Bitacora 'or by hand in Settings > Network & internet > Wi-Fi > Random hardware addresses.' 'INFO'
    }
}

# ===========================================================================
# LAYER 6 -- VIRTUAL MACHINE ISOLATION
# "They must never connect to my local network."
# ===========================================================================

function Invoke-CapaVM {
    Write-Titulo 'LAYER 6 -- VIRTUAL MACHINE ISOLATION'

    $hayVMware = Get-Service -Name 'VMware*','VMnet*' -ErrorAction SilentlyContinue
    if (-not $hayVMware) {
        Write-Bitacora 'VMware not detected on this computer; layer skipped' 'INFO'
        return
    }

    Write-Bitacora 'strategy: VMs lose NAT and DHCP, they stay on an isolated host-only' 'INFO'
    Write-Bitacora 'network, and the firewall cuts any path from the virtual subnets' 'INFO'
    Write-Bitacora 'to your physical network. A compromised VM reaches nothing.' 'INFO'
    Write-Host ''

    # --- Cut the VMs' outbound ------------------------------------------------
    Set-EstadoServicio -Nombre 'VMware NAT Service' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'without NAT the VMs reach neither the internet nor your LAN' | Out-Null
    Set-EstadoServicio -Nombre 'VMnetDHCP' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'without virtual DHCP the VMs get no automatic network configuration' | Out-Null
    Set-EstadoServicio -Nombre 'VMUSBArbService' -Arranque Manual -Simular:$Simular `
        -Motivo 'USB arbitrator: only when you really use a VM' | Out-Null

    # --- Wall between the virtual subnets and the physical network ------------
    $subredesVM = @('192.168.0.0/16','172.16.0.0/12','10.0.0.0/8')
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> rules that block traffic from the VMnet subnets to the physical network' 'DRYRUN'
    } else {
        try { Remove-NetFirewallRule -DisplayName 'Sentinel-VM-Isolated-*' -ErrorAction SilentlyContinue } catch { }
        $idx = 0
        foreach ($vmnet in @('VMware Network Adapter VMnet1','VMware Network Adapter VMnet8')) {
            $ad = Get-NetAdapter -Name $vmnet -ErrorAction SilentlyContinue
            if (-not $ad) { continue }
            $idx++
            try {
                New-NetFirewallRule -DisplayName "Sentinel-VM-Isolated-In-$idx" `
                    -Direction Inbound -Action Block -InterfaceAlias $vmnet -Profile Any -Enabled True `
                    -Description 'Nothing coming from this virtual network enters the host.' -ErrorAction Stop | Out-Null
                New-NetFirewallRule -DisplayName "Sentinel-VM-Isolated-Out-$idx" `
                    -Direction Outbound -Action Block -InterfaceAlias $vmnet -Profile Any -Enabled True `
                    -Description 'The host starts nothing toward this virtual network.' -ErrorAction Stop | Out-Null
                Write-Bitacora "$vmnet isolated in both directions" 'CHANGE'
            } catch { Write-Bitacora "isolation of $vmnet : $($_.Exception.Message)" 'WARN' }
        }
        # And the virtual adapters, down while not in use.
        foreach ($vmnet in @('VMware Network Adapter VMnet1','VMware Network Adapter VMnet8')) {
            try { Disable-NetAdapter -Name $vmnet -Confirm:$false -ErrorAction Stop; Write-Bitacora "$vmnet disabled" 'CHANGE' } catch { }
        }
    }

    # --- Seal the VM -> host channels in each .vmx -----------------------------
    # Shared folders, clipboard and drag-and-drop are the paths out of a VM
    # into the host. They are closed one by one.
    # ethernet0.connectionType is THE line that matters:
    #   bridged  = the VM has its own IP on YOUR network, like another computer
    #              plugged into the router. It sees all your devices and they see it.
    #   nat      = it goes out to the internet through the host, and reaches your LAN.
    #   hostonly = a closed network between the VM and the host. It goes nowhere.
    # With deliberately vulnerable lab machines, hostonly is the
    # only defensible option.
    $ajustes = @(
        'ethernet0.connectionType = "hostonly"',
        'isolation.tools.hgfs.disable = "TRUE"',
        'isolation.tools.copy.disable = "TRUE"',
        'isolation.tools.paste.disable = "TRUE"',
        'isolation.tools.dnd.disable = "TRUE"',
        'isolation.tools.setGUIOptions.enable = "FALSE"',
        'isolation.tools.autoInstall.disable = "TRUE"',
        'isolation.tools.diskShrink.disable = "TRUE"',
        'isolation.tools.diskWiper.disable = "TRUE"',
        'isolation.tools.ghi.autologon.disable = "TRUE"',
        'isolation.tools.unity.disable = "TRUE"',
        'RemoteDisplay.vnc.enabled = "FALSE"',
        'logging = "TRUE"'
    )

    $vmx = @()
    foreach ($base in @("$env:USERPROFILE\Documents\Virtual Machines", "$env:USERPROFILE\vmware", 'D:\VMs', "$env:USERPROFILE\Documents\Maquinas virtuales")) {
        if (Test-Path $base) {
            $vmx += Get-ChildItem -Path $base -Filter '*.vmx' -Recurse -ErrorAction SilentlyContinue
        }
    }

    if (-not $vmx -or $vmx.Count -eq 0) {
        Write-Bitacora 'no .vmx files found in the usual paths' 'INFO'
        Write-Bitacora 'if you keep VMs in another folder, add it to the list in this layer' 'INFO'
    } else {
        foreach ($f in $vmx) {
            # Report the current network mode, which is what really matters.
            $modo = try { ((Get-Content $f.FullName -ErrorAction Stop | Select-String '^ethernet0\.connectionType') -split '"')[1] } catch { '?' }
            if ($modo -eq 'bridged') {
                Write-Bitacora "$($f.Name) is BRIDGED: it has its own IP on your network, like another computer plugged into the router." 'WARN'
            } elseif ($modo -eq 'nat') {
                Write-Bitacora "$($f.Name) is on NAT: it reaches the internet and your local network." 'WARN'
            }

            if ($Simular) { Write-Bitacora "DRY RUN -> $($f.Name): network $modo -> hostonly, with no shared folders, clipboard or drag-and-drop" 'DRYRUN'; continue }
            try {
                Copy-Item $f.FullName "$($f.FullName).sentinel-copy" -Force -ErrorAction Stop
                $txt = Get-Content $f.FullName -Raw
                foreach ($a in $ajustes) {
                    $clave = ($a -split '=')[0].Trim()
                    if ($txt -match [regex]::Escape($clave)) {
                        $txt = $txt -replace "(?m)^\s*$([regex]::Escape($clave))\s*=.*$", $a
                    } else {
                        $txt = $txt.TrimEnd() + "`r`n" + $a
                    }
                }
                Set-Content -Path $f.FullName -Value $txt -Encoding ASCII -ErrorAction Stop
                Write-Bitacora "sealed: $($f.Name)" 'CHANGE'
            } catch { Write-Bitacora "could not seal $($f.Name): $($_.Exception.Message)" 'WARN' }
        }
    }

    Write-Host ''
    Write-Bitacora 'TO USE A VM AGAIN: start the VMware NAT Service and VMnetDHCP' 'INFO'
    Write-Bitacora 'services, and re-enable the VMnet8 adapter. Even better: configure the VM' 'INFO'
    Write-Bitacora 'as host-only on VMnet1 and leave it without an exit.' 'INFO'
}

# ===========================================================================
# LAYER 7 -- VULNERABLE DRIVERS (anti-BYOVD)
# The most valuable part of the whole hardening, and it does not break VMware.
# ===========================================================================

function Invoke-CapaDrivers {
    Write-Titulo 'LAYER 7 -- VULNERABLE DRIVERS (anti-BYOVD)'

    Write-Bitacora 'BYOVD: the attacker brings THEIR OWN signed, vulnerable driver,' 'INFO'
    Write-Bitacora 'loads it legitimately, and kills the antivirus from the kernel. It is how' 'INFO'
    Write-Bitacora 'almost every serious ransomware family operates today.' 'INFO'
    Write-Bitacora 'The Microsoft blocklist stops that, works without HVCI and does NOT' 'INFO'
    Write-Bitacora 'touch your virtual machines.' 'INFO'
    Write-Host ''

    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' `
        -Nombre 'VulnerableDriverBlocklistEnable' -Valor 1 -Simular:$Simular `
        -Motivo 'Microsoft vulnerable driver blocklist' | Out-Null

    # User-mode code integrity: only signed binaries in processes that
    # support it. Breaks nothing you have.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
        -Nombre 'ConfigCIDisabled' -Valor 0 -Simular:$Simular | Out-Null

    # Prevent installing unsigned drivers.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Driver Signing' `
        -Nombre 'Policy' -Valor ([byte[]](0x01)) -Tipo Binary -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Driver Signing' `
        -Nombre 'BehaviorOnFailedVerify' -Valor 2 -Simular:$Simular `
        -Motivo 'reject drivers without a valid signature' | Out-Null

    # Hardware-enforced stack protection, if the computer supports it.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
        -Nombre 'FeatureSettingsOverride' -Valor 0 -Simular:$Simular | Out-Null

    # HVCI state, without touching it: report only.
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        $corriendo = if ($dg.SecurityServicesRunning -contains 2) { 'YES' } else { 'NO' }
        Write-Bitacora "Memory Integrity (HVCI) running: $corriendo" 'INFO'
        if ($corriendo -eq 'NO') {
            Write-Bitacora 'HVCI is NOT enabled here on purpose: with VMware Workstation installed' 'WARN'
            Write-Bitacora 'it would degrade or break your virtual machines. Your decision.' 'WARN'
        }
    } catch { }

    # Patch status: an unpatched Windows beats any configuration.
    if (-not $Simular) {
        try {
            $ult = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1)
            $dias = if ($ult.InstalledOn) { [int]((Get-Date) - $ult.InstalledOn).TotalDays } else { -1 }
            Write-Bitacora "latest installed patch: $($ult.HotFixID), $dias days ago" $(if ($dias -gt 45) { 'WARN' } else { 'OK' })
            if ($dias -gt 45) {
                Write-Bitacora 'MORE THAN 45 DAYS WITHOUT PATCHES. This outweighs everything else combined:' 'ERROR'
                Write-Bitacora 'most ransomware gets in through a flaw that already had a patch.' 'ERROR'
            }
        } catch { }
    }
}

# ===========================================================================
# LAYER 8 -- CREDENTIALS AND MEMORY
# ===========================================================================

function Invoke-CapaCredenciales {
    Write-Titulo 'LAYER 8 -- CREDENTIALS AND MEMORY'

    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

    # LSA protection, reinforced at boot.
    Set-ValorRegistro -Ruta $lsa -Nombre 'RunAsPPL' -Valor 2 -Simular:$Simular `
        -Motivo 'lsass protected: mimikatz cannot read it' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'LmCompatibilityLevel' -Valor 5 -Simular:$Simular `
        -Motivo 'NTLMv2 only: neither LM nor NTLMv1, which break in minutes' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'NoLMHash' -Valor 1 -Simular:$Simular `
        -Motivo 'do not store the LM hash, which is trivial to break' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'RestrictAnonymous' -Valor 1 -Simular:$Simular `
        -Motivo 'no anonymous enumeration' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'RestrictAnonymousSAM' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'EveryoneIncludesAnonymous' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'LimitBlankPasswordUse' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'DisableDomainCreds' -Valor 1 -Simular:$Simular `
        -Motivo 'do not store network credentials on the computer' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'SCENoApplyLegacyAuditPolicy' -Valor 1 -Simular:$Simular | Out-Null

    # WDigest: if it is active, your password lives IN CLEAR TEXT in lsass memory.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' `
        -Nombre 'UseLogonCredential' -Valor 0 -Simular:$Simular `
        -Motivo 'no clear-text passwords in memory' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' `
        -Nombre 'Negotiate' -Valor 0 -Simular:$Simular | Out-Null

    # NTLM: 128-bit signing and encryption required in both directions.
    Set-ValorRegistro -Ruta "$lsa\MSV1_0" -Nombre 'NTLMMinClientSec' -Valor 537395200 -Simular:$Simular `
        -Motivo 'NTLM with 128-bit signing and integrity required' | Out-Null
    Set-ValorRegistro -Ruta "$lsa\MSV1_0" -Nombre 'NTLMMinServerSec' -Valor 537395200 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta "$lsa\MSV1_0" -Nombre 'allownullsessionfallback' -Valor 0 -Simular:$Simular | Out-Null

    # No memory dumps: a full dump contains keys and credentials.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' `
        -Nombre 'CrashDumpEnabled' -Valor 0 -Simular:$Simular `
        -Motivo 'a full dump is a forensic gift to whoever steals the disk' | Out-Null

    # No leftover page file on shutdown.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
        -Nombre 'ClearPageFileAtShutdown' -Valor 1 -Simular:$Simular | Out-Null

    # Strong encryption and no broken protocols.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' `
        -Nombre 'SecureProtocols' -Valor 2688 -Simular:$Simular -Motivo 'TLS 1.2 and 1.3 only' | Out-Null
    foreach ($p in @('SSL 2.0','SSL 3.0','TLS 1.0','TLS 1.1')) {
        foreach ($rol in @('Client','Server')) {
            Set-ValorRegistro -Ruta "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$p\$rol" `
                -Nombre 'Enabled' -Valor 0 -Simular:$Simular | Out-Null
            Set-ValorRegistro -Ruta "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$p\$rol" `
                -Nombre 'DisabledByDefault' -Valor 1 -Simular:$Simular | Out-Null
        }
    }
    Write-Bitacora 'SSL 2.0, SSL 3.0, TLS 1.0 and TLS 1.1 disabled; TLS 1.2 and 1.3 only' $(if ($Simular) { 'DRYRUN' } else { 'CHANGE' })

    # Screen lock
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Nombre 'InactivityTimeoutSecs' -Valor 600 -Simular:$Simular -Motivo 'lock after 10 minutes' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Nombre 'DontDisplayLastUserName' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Nombre 'DisableLockWorkstation' -Valor 0 -Simular:$Simular | Out-Null

    # Codex sandbox accounts: warning only, not touched without permission.
    try {
        $sospechosas = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and $_.Name -match 'CodexSandbox' }
        foreach ($u in $sospechosas) {
            Write-Bitacora "enabled local account: $($u.Name) -- it belongs to OpenAI's Codex CLI." 'WARN'
            Write-Bitacora '  not touched without your permission. If you no longer use Codex, disable it.' 'WARN'
        }
    } catch { }
}

# ===========================================================================
# LAYER 9 -- DEEP ANTI-RANSOMWARE
# ===========================================================================

function Invoke-CapaRansomware {
    Write-Titulo 'LAYER 9 -- DEEP ANTI-RANSOMWARE'

    # --- Controlled Folder Access --------------------------------------------
    # It is the built-in defense that stops an unknown process from writing
    # into your folders. It goes first in AUDIT: for a few days it records
    # everything it would block without blocking it, so the allow list is
    # built from real data and not by breaking your work.
    $carpetas = @(
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Pictures",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Security"
    ) | Where-Object { Test-Path $_ }

    foreach ($extra in @()) {
        if (Test-Path $extra) { $carpetas += $extra }
    }

    $permitidas = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe",
        'C:\Program Files\nodejs\node.exe',
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:LOCALAPPDATA\Obsidian\Obsidian.exe",
        "$env:LOCALAPPDATA\Programs\obsidian\Obsidian.exe",
        'C:\Program Files\7-Zip\7zFM.exe',
        'C:\Program Files\LM Studio\LM Studio.exe',
        'C:\Program Files\Git\bin\git.exe',
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    ) | Where-Object { Test-Path $_ }

    if ($Simular) {
        Write-Bitacora "DRY RUN -> Controlled Folder Access in AUDIT" 'DRYRUN'
        $carpetas   | ForEach-Object { Write-Bitacora "DRY RUN ->   would protect: $_" 'DRYRUN' }
        $permitidas | ForEach-Object { Write-Bitacora "DRY RUN ->   would allow: $(Split-Path $_ -Leaf)" 'DRYRUN' }
    } else {
        Set-PreferenciaDefender -Nombre 'EnableControlledFolderAccess' -Valor 2 `
            -Motivo 'AUDIT MODE: records what it would block, without blocking yet' | Out-Null
        foreach ($c in $carpetas) {
            try { Add-MpPreference -ControlledFolderAccessProtectedFolders $c -ErrorAction Stop; Write-Bitacora "protected: $c" 'CHANGE' }
            catch { Write-Bitacora "could not protect $c : $($_.Exception.Message)" 'WARN' }
        }
        foreach ($a in $permitidas) {
            try { Add-MpPreference -ControlledFolderAccessAllowedApplications $a -ErrorAction Stop; Write-Bitacora "allowed: $(Split-Path $a -Leaf)" 'CHANGE' }
            catch { }
        }
        Write-Host ''
        Write-Bitacora 'CFA stays in AUDIT. Use the computer normally for a few days and then check' 'WARN'
        Write-Bitacora 'what would have been blocked with:  .\Audit.ps1 -Cfa' 'WARN'
        Write-Bitacora 'When the list is tuned, switch it to blocking with:' 'WARN'
        Write-Bitacora '  Set-MpPreference -EnableControlledFolderAccess Enabled' 'WARN'
    }

    # --- System Protection and restore points ---------------------------------
    if ($Simular) {
        Write-Bitacora 'DRY RUN -> System Protection active with 10% of the disk' 'DRYRUN'
    } else {
        $orden = "Enable-ComputerRestore -Drive 'C:\'; 'SR-OK'"
        $res = & powershell.exe -NoProfile -Command $orden 2>&1
        if ("$res" -match 'SR-OK') { Write-Bitacora 'System Protection enabled on C:' 'CHANGE' }
        else { Write-Bitacora "System Protection: $res" 'WARN' }
        & vssadmin.exe resize shadowstorage /for=C: /on=C: /maxsize=10% > $null 2>&1
        Write-Bitacora 'space for shadow copies: 10% of the disk' 'CHANGE'
    }

    # --- Watch the tools ransomware uses ---------------------------------------
    # vssadmin, wbadmin, bcdedit and wmic delete copies and disable
    # recovery. They are not blocked (Windows itself needs them), but every
    # run is logged, and that gives the early warning.
    if (-not $Simular) {
        foreach ($h in @('vssadmin.exe','wbadmin.exe','bcdedit.exe','wmic.exe','cipher.exe')) {
            $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$h"
            Set-ValorRegistro -Ruta $k -Nombre 'GlobalFlag' -Valor 512 -Simular:$false `
                -Motivo "audit every run of $h" | Out-Null
        }
        Write-Bitacora 'vssadmin, wbadmin, bcdedit, wmic and cipher are now audited in the event log' 'CHANGE'
    } else {
        Write-Bitacora 'DRY RUN -> audit vssadmin, wbadmin, bcdedit, wmic and cipher' 'DRYRUN'
    }

    Write-Host ''
    Write-Bitacora 'UNCOMFORTABLE TRUTH: the only defense that really works against' 'WARN'
    Write-Bitacora 'ransomware is a DISCONNECTED backup. Everything above reduces' 'WARN'
    Write-Bitacora 'the probability; a copy on a disk that is not plugged in is the only' 'WARN'
    Write-Bitacora 'thing that guarantees you get your files back. OneDrive does not count:' 'WARN'
    Write-Bitacora 'it syncs encrypted files just as fast as good ones.' 'WARN'
}

# ===========================================================================
# MAIN
# ===========================================================================

Show-Cabecera

if (-not $Simular) {
    if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos @(
        '-Apply'
        '-Layers'; ($Layers -join ',')
        '-RevertMinutes'; $RevertMinutes
        $(if ($NoPrompt)   { '-NoPrompt' })
        $(if ($RandomizeMAC) { '-RandomizeMAC' })
    ) )) { return }

    if (-not $Orchestrated) {
        Write-Host '  Type HARDEN to continue, or anything else to exit.' -ForegroundColor Yellow
        if ((Read-Host '  >') -ne 'HARDEN') { Write-Host '  Cancelled. Nothing was touched.' -ForegroundColor Green; return }
    }
}

Write-Bitacora "start -- mode: $(if ($Simular) { 'DRY RUN' } else { 'REAL' })" 'INFO'

# Starting state, to compare afterwards
Write-Titulo 'STARTING STATE'
$antes = Test-Conectividad
if (-not $antes.Sano -and -not $Simular) {
    Write-Bitacora 'THERE IS NO INTERNET BEFORE STARTING. Aborting: fix the network first.' 'ERROR'
    return
}

# Backup. If it fails, this is where it ends.
$carpetaResp = Backup-EstadoSistema -Simular:$Simular
$scriptEmerg = Join-Path $carpetaResp 'EMERGENCY-restore-network.ps1'

# Reverter armed before any layer that touches the network
$capasDeRed = @('ports','stealth','vm','privacy')
$tocaRed = ($Layers | Where-Object { $capasDeRed -contains $_ }).Count -gt 0

if ($tocaRed -and -not $Simular) {
    if (-not (Enable-Reversor -ScriptEmergencia $scriptEmerg -Minutos $RevertMinutes)) { return }
}

# Running the layers
$mapa = [ordered]@{
    'defender'     = { Invoke-CapaDefender }
    'ports'        = { Invoke-CapaPuertos }
    'locks'        = { Invoke-CapaCerrojos }
    'privacy'      = { Invoke-CapaPrivacidad }
    'stealth'      = { Invoke-CapaSigilo }
    'vm'           = { Invoke-CapaVM }
    'drivers'      = { Invoke-CapaDrivers }
    'credentials'  = { Invoke-CapaCredenciales }
    'ransomware'   = { Invoke-CapaRansomware }
}

foreach ($c in $mapa.Keys) {
    if ($Layers -notcontains $c) { continue }
    try { & $mapa[$c] } catch { Write-Bitacora "layer '$c' failed: $($_.Exception.Message)" 'ERROR' }

    # After each layer that touches the network, check that we are still alive.
    if (($capasDeRed -contains $c) -and -not $Simular) {
        Write-Host ''
        $chk = Test-Conectividad -Silencioso
        if (-not $chk.Sano) {
            Write-Bitacora "LAYER '$c' BROKE CONNECTIVITY. Reverting everything now." 'ERROR'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptEmerg -Auto
            Disable-Reversor
            return
        }
        Write-Bitacora "after layer '$c': connectivity still intact" 'OK'
    }
}

# Wrap-up
Write-Titulo 'FINAL CHECK'
if ($Simular) {
    Write-Host ''
    Write-Host '  This was a DRY RUN. Nothing was changed.' -ForegroundColor Green
    Write-Host '  Review the log and, if you are convinced, run:' -ForegroundColor Green
    Write-Host '     .\Harden.ps1 -Apply' -ForegroundColor White
    Write-Host ''
} else {
    if ($tocaRed) {
        $firme = Confirm-Supervivencia -ScriptEmergencia $scriptEmerg -NoPrompt:$NoPrompt
        if (-not $firme) { Write-Host '  It was reverted. The computer is as it was before.' -ForegroundColor Yellow; return }
    }
    Test-Conectividad | Out-Null
    Write-Host ''
    Write-Host '  Hardening applied.' -ForegroundColor Green
    Write-Host "  Backup:  $carpetaResp" -ForegroundColor DarkGray
    Write-Host "  Log:     $script:Log" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  To undo everything:              .\Restore.ps1' -ForegroundColor DarkGray
    Write-Host '  If something goes wrong with the network: double-click' -ForegroundColor DarkGray
    Write-Host "     $scriptEmerg" -ForegroundColor White
    Write-Host ''
    Write-Host '  RESTART when you can: several changes (UAC, drivers,' -ForegroundColor Yellow
    Write-Host '  auditing, PowerShell v2) do not fully take effect until the restart.' -ForegroundColor Yellow
    Write-Host ''
}
