<#
.SYNOPSIS
    Blindaje de Windows 11 Home. Por capas, con respaldo, verificacion de
    conectividad tras cada capa y reversor temporizado.

.DESCRIPTION
    SIN ARGUMENTOS NO CAMBIA NADA. Imprime lo que haria y sale.
    Para aplicar de verdad hay que escribir -Aplicar.

    Capas:
      1  defender     Defender al maximo, CFA, ASR completas, proteccion de red
      2  puertos      Firewall estricto, barrido de reglas, servicios expuestos
      3  cerrojos     UAC, WSH, PowerShell v2, autorun, macros, auditoria
      4  privacidad   Telemetria al minimo, ubicacion, publicidad, Recall, DNS
      5  sigilo       Silencio en la red local: sin descubrimiento, sin ping
      6  vm           Aislamiento de VMware: las VMs no tocan la red fisica
      7  drivers      Lista de bloqueo de controladores vulnerables (anti-BYOVD)
      8  credenciales NTLMv2 unicamente, sin WDigest, sin volcado de memoria
      9  ransomware   CFA en bloqueo, proteccion de instantaneas, restauracion

.EXAMPLE
    .\Blindar.ps1
    Simulacro. No toca nada. Es lo que debes correr primero.

.EXAMPLE
    .\Blindar.ps1 -Aplicar
    Aplica las nueve capas, con reversor de 10 minutos en las que tocan red.

.EXAMPLE
    .\Blindar.ps1 -Aplicar -Capas defender,ransomware
    Solo esas dos capas.
#>

[CmdletBinding()]
param(
    [switch]$Aplicar,

    [ValidateSet('defender','puertos','cerrojos','privacidad','sigilo','vm','drivers','credenciales','ransomware')]
    [string[]]$Capas = @('defender','puertos','cerrojos','privacidad','sigilo','vm','drivers','credenciales','ransomware'),

    [int]$MinutosReversor = 10,

    # Se salta la confirmacion humana. Solo para uso desatendido: si la
    # conectividad falla igual revierte sola, pero pierdes el ultimo filtro.
    [switch]$SinPreguntar,

    # Aleatoriza la MAC del Wi-Fi. Desconecta y reconecta el adaptador.
    [switch]$AleatorizarMAC,

    # Corta el sondeo de conectividad de Windows. Efecto secundario: el icono
    # de red dira "sin Internet" para siempre, aunque navegues bien.
    [switch]$CortarSondeoMicrosoft,

    # Corta el trafico de salida por defecto. NO usar sin lista de permitidos.
    [switch]$BloquearSalida,

    # Lo pasa Todo.ps1: ya venimos elevados y el usuario ya dijo que si, asi
    # que sobra pedirselo otra vez. NO afecta a la confirmacion de que sigue
    # habiendo Internet: esa se mantiene siempre, es la que de verdad protege.
    [switch]$Orquestado
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Nucleo.ps1')

$Simular = -not $Aplicar

# ---------------------------------------------------------------------------

function Show-Cabecera {
    if (-not $Orquestado) { Clear-Host }
    Write-Host ''
    Write-Host '   #############################################################' -ForegroundColor DarkCyan
    Write-Host '   #                    C E N T I N E L A                      #' -ForegroundColor White
    Write-Host '   #          Blindaje de Windows 11 Home                      #' -ForegroundColor DarkCyan
    Write-Host '   #############################################################' -ForegroundColor DarkCyan
    Write-Host ''
    if ($Simular) {
        Write-Host '   MODO SIMULACRO. No se va a cambiar absolutamente nada.' -ForegroundColor Green
        Write-Host '   Para aplicar de verdad:  .\Blindar.ps1 -Aplicar' -ForegroundColor DarkGray
    } else {
        Write-Host '   MODO REAL. Se van a aplicar cambios al sistema.' -ForegroundColor Yellow
    }
    Write-Host ("   Capas: " + ($Capas -join ', ')) -ForegroundColor DarkGray
    Write-Host ("   Bitacora: " + $script:Log) -ForegroundColor DarkGray
    Write-Host ''
}

# ===========================================================================
# CAPA 1 -- DEFENDER AL MAXIMO
# Riesgo para la conectividad: ninguno.
# ===========================================================================

function Invoke-CapaDefender {
    Write-Titulo 'CAPA 1 -- DEFENDER AL MAXIMO'

    Set-PreferenciaDefender -Nombre 'EnableNetworkProtection' -Valor 1 -Simular:$Simular `
        -Motivo 'corta conexiones a dominios de mando y control' | Out-Null
    Set-PreferenciaDefender -Nombre 'CloudBlockLevel' -Valor 2 -Simular:$Simular `
        -Motivo 'bloqueo en nube en nivel alto' | Out-Null
    Set-PreferenciaDefender -Nombre 'CloudExtendedTimeout' -Valor 50 -Simular:$Simular `
        -Motivo 'da tiempo a la nube a dictaminar antes de dejar correr un binario' | Out-Null
    Set-PreferenciaDefender -Nombre 'PUAProtection' -Valor 1 -Simular:$Simular `
        -Motivo 'bloquea software no deseado' | Out-Null
    Set-PreferenciaDefender -Nombre 'MAPSReporting' -Valor 2 -Simular:$Simular `
        -Motivo 'proteccion en nube avanzada' | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableRemovableDriveScanning' -Valor $false -Simular:$Simular `
        -Motivo 'analizar USB al conectarlos' | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableArchiveScanning' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableEmailScanning' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableBehaviorMonitoring' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'DisableScriptScanning' -Valor $false -Simular:$Simular | Out-Null
    Set-PreferenciaDefender -Nombre 'ScanScheduleDay' -Valor 0 -Simular:$Simular `
        -Motivo 'analisis completo semanal' | Out-Null
    Set-PreferenciaDefender -Nombre 'SignatureUpdateInterval' -Valor 2 -Simular:$Simular `
        -Motivo 'firmas cada 2 horas' | Out-Null

    # --- Reglas ASR ---------------------------------------------------------
    # Las 13 que ya tiene puestas mas las 6 que le faltan. La de ejecutables
    # poco frecuentes va en AUDITORIA, no en bloqueo: le romperia sus propios
    # ejecutables compilados, que por definicion no tienen prevalencia.
    Write-Host ''
    Write-Bitacora 'reglas de reduccion de superficie de ataque (ASR)' 'INFO'

    $asr = [ordered]@{
        '56A863A9-875E-4185-98A7-B882C64B5CE5' = @(1,'abuso de controladores firmados vulnerables')
        '7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C' = @(1,'Adobe Reader creando procesos hijo')
        'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' = @(1,'Office creando procesos hijo')
        '9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2' = @(1,'ROBO DE CREDENCIALES DE LSASS -- faltaba')
        'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550' = @(1,'ejecutables llegados por correo')
        '5BEB7EFE-FD9A-4556-801D-275E5FFC04CC' = @(1,'scripts ofuscados')
        'D3E037E1-3EB8-44C8-A917-57927947596D' = @(1,'JS/VBS lanzando ejecutables descargados')
        '3B576869-A4EC-4529-8536-B80A7769E899' = @(1,'Office creando contenido ejecutable')
        '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84' = @(1,'Office inyectando en otros procesos')
        '26190899-1602-49E8-8B27-EB1D0A1CE869' = @(1,'Outlook creando procesos hijo')
        'E6DB77E5-3DF2-4CF1-B95A-636979351E5B' = @(1,'persistencia por suscripcion de eventos WMI')
        'D1E49AAC-8F56-4280-B9BA-993A6D77406C' = @(1,'procesos nacidos de PsExec y WMI -- faltaba')
        '33DDEDF1-C6E0-47CB-833E-DE6133960387' = @(1,'REINICIO EN MODO SEGURO -- faltaba, es como el ransomware esquiva al antivirus')
        'B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4' = @(1,'procesos no firmados desde USB')
        'C0033C00-D16D-4114-A5A0-DC9B3A7D2CEB' = @(1,'herramientas del sistema copiadas o suplantadas -- faltaba')
        '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B' = @(1,'llamadas Win32 desde macros de Office')
        'C1DB55AB-C21A-4637-BB3F-A12568109D35' = @(1,'proteccion avanzada contra ransomware')
        'A8F5898E-1DC8-49A9-9878-85004B8A61E6' = @(1,'creacion de webshells')
        '01443614-CD74-433A-B99E-2ECDC07BFC25' = @(2,'ejecutables poco frecuentes -- EN AUDITORIA para no romper tus propios .exe')
    }

    foreach ($id in $asr.Keys) {
        $accion = $asr[$id][0]
        $texto  = $asr[$id][1]
        if ($Simular) {
            Write-Bitacora ("SIMULACRO -> ASR {0} = {1}  ({2})" -f $id.Substring(0,8), $accion, $texto) 'SIMULA'
            continue
        }
        try {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions $accion -ErrorAction Stop
            Write-Bitacora ("ASR {0} = {1}  ({2})" -f $id.Substring(0,8), $accion, $texto) 'CAMBIO'
        } catch {
            Write-Bitacora ("ASR {0} FALLO: {1}" -f $id.Substring(0,8), $_.Exception.Message) 'AVISO'
        }
    }

    # --- Comprobacion honesta ----------------------------------------------
    if (-not $Simular) {
        $p = Get-MpPreference
        $puestas = if ($p.AttackSurfaceReductionRules_Ids) { $p.AttackSurfaceReductionRules_Ids.Count } else { 0 }
        Write-Bitacora "reglas ASR activas ahora: $puestas de 19" $(if ($puestas -ge 19) { 'OK' } else { 'AVISO' })
    }
}

# ===========================================================================
# CAPA 2 -- CERRAR PUERTAS
# Riesgo: bajo. La salida queda intacta. Reversor armado igualmente.
# ===========================================================================

function Invoke-CapaPuertos {
    Write-Titulo 'CAPA 2 -- CERRAR PUERTAS'

    # --- Firewall explicito -------------------------------------------------
    # NotConfigured hereda el valor por defecto, pero un valor heredado es un
    # valor que alguien puede cambiar sin que se note. Lo hacemos explicito.
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> entrada BLOQUEADA por defecto en los tres perfiles; salida INTACTA' 'SIMULA'
        Write-Bitacora 'SIMULACRO -> registro del firewall activado (32 MB por perfil)' 'SIMULA'
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
            Write-Bitacora 'entrada bloqueada por defecto en los tres perfiles; salida intacta' 'CAMBIO'
            Write-Bitacora 'registro del firewall activado -- sin bitacora no hay forensia' 'CAMBIO'
        } catch {
            Write-Bitacora "FALLO configurando perfiles: $($_.Exception.Message)" 'ERROR'
        }
    }

    # --- Barrido de reglas de entrada --------------------------------------
    # Se DESACTIVAN, no se borran. Volver atras es poner Enabled True.
    Write-Host ''
    Write-Bitacora 'barrido de reglas de entrada' 'INFO'

    # a) Grupos de descubrimiento que no pintan nada en una red ajena
    $gruposFuera = @(
        # La comparacion es sin tildes y sin distinguir mayusculas, asi que
        # basta con un trozo del nombre. Los que llevan comentario son los
        # que de verdad estaban abiertos en este equipo.
        'Deteccion de redes','Network Discovery',              # 2 reglas
        'Wi-Fi Direct','WFD','Servicio WLAN',                  # 6 reglas
        'Proyeccion inalambrica','Projection',                 # 2 reglas
        'Optimizacion de distribucion','Delivery Optimization', # 2 reglas: P2P de Windows Update
        'Plataforma de dispositivos conectados','Connected Devices Platform', # 1 regla
        'MyASUS',                                              # 1 regla
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
    # Todas las consultas de abajo pasan por Get-ReglasEntrada, y no por
    # capricho: "Get-NetFirewallRule -DisplayName X -Direction Inbound" es un
    # ERROR de PowerShell -- esos parametros viven en conjuntos distintos y no
    # se pueden combinar. La primera version lo hacia asi, dentro de un catch
    # vacio, y el resultado fue que tres barridos enteros devolvieron cero sin
    # avisar de nada. Se consulta por un solo criterio y se filtra despues.
    $n = 0
    foreach ($g in $gruposFuera) {
        $reglas = Get-ReglasEntrada -Grupo $g -SoloHabilitadas
        foreach ($r in $reglas) {
            if ($Simular) { Write-Bitacora "SIMULACRO -> desactivar '$($r.DisplayName)'" 'SIMULA' }
            else { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
            $n++
        }
    }
    Write-Bitacora "reglas de descubrimiento desactivadas: $n" $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })

    # b) Servicios propios que SOLO escuchan en 127.0.0.1.
    #    El firewall de Windows no filtra el bucle local: estas reglas no
    #    aportan nada y solo suman superficie. Quitarlas no rompe nada.
    $soloLocal = @('python.exe','Node.js JavaScript Runtime','LM Studio','postman.exe',
                   'Packet Tracer Executable','podman desktop.exe','Microsoft Office Outlook',
                   'AsusSwitchNet','AsusSwitchNetMDNS','MyASUS')
    $n = 0
    foreach ($nombre in $soloLocal) {
        foreach ($r in (Get-ReglasEntrada -Nombre $nombre -SoloHabilitadas)) {
            if ($Simular) { Write-Bitacora "SIMULACRO -> desactivar entrada de '$($r.DisplayName)'" 'SIMULA' }
            else { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
            $n++
        }
    }
    Write-Bitacora "reglas de servicios que solo escuchan en local: $n desactivadas" $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })

    # c) Lo que no debe aceptar conexiones jamas.
    #    adb.exe es el caso grave: la regla apunta a la carpeta Temp de Claude.
    #    Un binario reemplazable en una ruta temporal con entrada permitida en
    #    red publica es una puerta trasera esperando a que alguien la use.
    $prohibidos = @('adb.exe','lolminer.exe','zephyrd.exe')
    $n = 0
    foreach ($nombre in $prohibidos) {
        foreach ($r in (Get-ReglasEntrada -Nombre $nombre)) {
            if ($Simular) { Write-Bitacora "SIMULACRO -> ELIMINAR regla de entrada '$($r.DisplayName)'" 'SIMULA' }
            else {
                try { Remove-NetFirewallRule -Name $r.Name -ErrorAction Stop }
                catch { Write-Bitacora "no se pudo eliminar '$($r.DisplayName)': $($_.Exception.Message)" 'AVISO'; continue }
            }
            $n++
        }
    }
    Write-Bitacora "reglas de entrada eliminadas (adb, mineros): $n" $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })

    # d) Juegos: se quedan en red privada, se van de la publica.
    $juegos = @('Steam','Steam Web Helper','Grand Theft Auto V Enhanced','God of War','Fallout 4','Game Bar')
    $n = 0
    foreach ($nombre in $juegos) {
        foreach ($r in (Get-ReglasEntrada -Nombre $nombre -SoloHabilitadas)) {
            if ($r.Profile -match 'Public' -or $r.Profile -eq 'Any') {
                if ($Simular) { Write-Bitacora "SIMULACRO -> '$($r.DisplayName)' fuera del perfil publico" 'SIMULA' }
                else {
                    try { Set-NetFirewallRule -Name $r.Name -Profile Domain,Private -ErrorAction Stop }
                    catch { Write-Bitacora "no se pudo mover '$($r.DisplayName)': $($_.Exception.Message)" 'AVISO'; continue }
                }
                $n++
            }
        }
    }
    Write-Bitacora "reglas de juegos retiradas del perfil publico: $n" $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })

    # e) Duplicados de mDNS de Edge acumulados por las actualizaciones
    try {
        $dup = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction Stop |
               Where-Object { $_.DisplayName -like '*mDNS*' }
        $n = ($dup | Measure-Object).Count
        if (-not $Simular) { $dup | ForEach-Object { Disable-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue } }
        Write-Bitacora "reglas de mDNS desactivadas: $n" $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })
    } catch { }

    # --- SMB: cifrado y sin acceso anonimo ----------------------------------
    # Esto va ANTES de parar LanmanServer: con el servicio detenido, algunos de
    # estos ajustes fallan. Primero se endurece, luego se apaga.
    Write-Host ''
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> SMB: cifrado obligatorio, firma obligatoria, sin SMB1' 'SIMULA'
    } else {
        # Ojo: -EnableInsecureGuestLogons NO existe en Set-SmbServerConfiguration
        # (es de la variante Client). Meterlo aqui hacia fallar el comando
        # ENTERO, asi que no se aplicaba nada del SMB de servidor. Y como cada
        # ajuste va por separado, si uno falla los demas siguen entrando.
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
            catch { Write-Bitacora "SMB servidor, $k : $($_.Exception.Message)" 'AVISO' }
        }
        Write-Bitacora "SMB servidor endurecido: $puestos de $($ajustesSmb.Count) ajustes" `
            $(if ($puestos -eq $ajustesSmb.Count) { 'CAMBIO' } else { 'AVISO' })
        try {
            Set-SmbClientConfiguration -RequireSecuritySignature $true -EnableInsecureGuestLogons $false `
                -Force -ErrorAction Stop
            Write-Bitacora 'cliente SMB: firma obligatoria, sin invitado inseguro' 'CAMBIO'
        } catch { Write-Bitacora "SMB cliente: $($_.Exception.Message)" 'AVISO' }
    }

    # --- Servicios expuestos ------------------------------------------------
    Write-Host ''
    Write-Bitacora 'servicios de acceso remoto y exposicion' 'INFO'

    Set-EstadoServicio -Nombre 'WinRM' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'estaba ESCUCHANDO en ::5985 y ::47001, administracion remota abierta en Wi-Fi ajena' | Out-Null
    Set-EstadoServicio -Nombre 'LanmanServer' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'publicaba ADMIN$, C$ e IPC$ con el puerto 445 en todas las interfaces' | Out-Null
    Set-EstadoServicio -Nombre 'SSDPSRV' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'descubrimiento UPnP, innecesario' | Out-Null
    Set-EstadoServicio -Nombre 'upnphost' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'RemoteRegistry' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'RemoteAccess' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'SessionEnv' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'TermService' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'escritorio remoto, ya estaba denegado por registro' | Out-Null
    Set-EstadoServicio -Nombre 'UmRdpService' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'WMPNetworkSvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'WerSvc' -Arranque Manual -Simular:$Simular | Out-Null

    # LanmanWorkstation se QUEDA: es el cliente. Sin el no podrias acceder a
    # recursos compartidos ajenos. Lo que se apaga es el servidor.

    # --- RDP y asistencia remota por registro -------------------------------
    Set-ValorRegistro -Ruta 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Nombre 'fDenyTSConnections' -Valor 1 -Simular:$Simular -Motivo 'escritorio remoto denegado' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Nombre 'fAllowToGetHelp' -Valor 0 -Simular:$Simular -Motivo 'asistencia remota denegada' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Nombre 'fAllowUnsolicited' -Valor 0 -Simular:$Simular | Out-Null
}

# ===========================================================================
# CAPA 3 -- CERROJOS DEL SISTEMA
# ===========================================================================

function Invoke-CapaCerrojos {
    Write-Titulo 'CAPA 3 -- CERROJOS DEL SISTEMA'

    $pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    # UAC al maximo. ConsentPromptBehaviorAdmin = 2 pide consentimiento SIEMPRE,
    # incluso para binarios de Windows. Eso inutiliza los bypass que abusan de
    # ejecutables con auto-elevacion: fodhelper, computerdefaults, sdclt, eventvwr.
    # Precio: mas avisos. Es el precio correcto.
    Set-ValorRegistro -Ruta $pol -Nombre 'EnableLUA' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'ConsentPromptBehaviorAdmin' -Valor 2 -Simular:$Simular `
        -Motivo 'consentimiento SIEMPRE: cierra los bypass de UAC por auto-elevacion' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'ConsentPromptBehaviorUser' -Valor 0 -Simular:$Simular `
        -Motivo 'usuarios estandar no pueden elevar' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'PromptOnSecureDesktop' -Valor 1 -Simular:$Simular `
        -Motivo 'escritorio seguro: ningun programa puede falsificar el aviso' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'FilterAdministratorToken' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'EnableInstallerDetection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'EnableSecureUIAPaths' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'ValidateAdminCodeSignatures' -Valor 1 -Simular:$Simular `
        -Motivo 'solo se eleva codigo firmado y valido' | Out-Null
    Set-ValorRegistro -Ruta $pol -Nombre 'LocalAccountTokenFilterPolicy' -Valor 0 -Simular:$Simular `
        -Motivo 'impide elevacion remota con cuenta local' | Out-Null

    # Windows Script Host: mata los .vbs y .js de doble clic, vector clasico
    # de ransomware por correo.
    #
    # PERO si el equipo tiene lanzadores propios que son .vbs, apagar WSH sin mas los
    # rompe. Asi que primero se migran a equivalentes que no lo necesitan, y
    # SOLO si la migracion sale bien se apaga.
    Write-Host ''
    Write-Bitacora 'antes de tocar Windows Script Host: migrando tus lanzadores .vbs' 'INFO'
    $migrador = Join-Path $PSScriptRoot 'Migrar-Lanzadores.ps1'
    $seguro = $false
    if (Test-Path $migrador) {
        try {
            $seguro = if ($Simular) { & $migrador } else { & $migrador -Aplicar }
            $seguro = [bool]($seguro | Select-Object -Last 1)
        } catch {
            Write-Bitacora "el migrador fallo: $($_.Exception.Message)" 'ERROR'
            $seguro = $false
        }
    } else {
        Write-Bitacora "no se encuentra $migrador" 'ERROR'
    }

    if ($seguro) {
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' `
            -Nombre 'Enabled' -Valor 0 -Simular:$Simular -Motivo 'sin .vbs ni .js de doble clic' | Out-Null
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows Script Host\Settings' `
            -Nombre 'Enabled' -Valor 0 -Simular:$Simular | Out-Null
    } else {
        Write-Bitacora 'WINDOWS SCRIPT HOST SE QUEDA ACTIVO.' 'AVISO'
        Write-Bitacora 'La migracion de tus lanzadores no salio limpia, y romperte Scriptorium' 'AVISO'
        Write-Bitacora 'o la granja de noticias es peor que dejar WSH encendido. Arregla la' 'AVISO'
        Write-Bitacora 'migracion y vuelve a lanzar:  .\Blindar.ps1 -Aplicar -Capas cerrojos' 'AVISO'
    }

    # Autorun / Autoplay: 255 = todas las unidades.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Nombre 'NoDriveTypeAutoRun' -Valor 255 -Simular:$Simular -Motivo 'USB hostil' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Nombre 'NoAutorun' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' `
        -Nombre 'NoAutoplayfornonVolume' -Valor 1 -Simular:$Simular | Out-Null

    # Extensiones visibles: para que factura.pdf.exe deje de disfrazarse.
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Nombre 'HideFileExt' -Valor 0 -Simular:$Simular -Motivo 'ver siempre la extension real' | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Nombre 'Hidden' -Valor 1 -Simular:$Simular | Out-Null

    # Macros de Office llegadas de Internet: bloqueadas.
    foreach ($app in 'Word','Excel','PowerPoint','Access','Publisher','Outlook','Visio') {
        Set-ValorRegistro -Ruta "HKCU:\SOFTWARE\Microsoft\Office\16.0\$app\Security" `
            -Nombre 'BlockContentExecutionFromInternet' -Valor 1 -Simular:$Simular | Out-Null
        Set-ValorRegistro -Ruta "HKCU:\SOFTWARE\Microsoft\Office\16.0\$app\Security" `
            -Nombre 'VBAWarnings' -Valor 4 -Simular:$Simular | Out-Null
    }
    Write-Bitacora 'macros de Office desde Internet: bloqueadas' $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })

    # Registro de bloques de script de PowerShell y linea de comandos en 4688.
    # Sin esto, un ataque en PowerShell no deja rastro reconstruible.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' `
        -Nombre 'EnableScriptBlockLogging' -Valor 1 -Simular:$Simular `
        -Motivo 'todo bloque de script queda registrado' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' `
        -Nombre 'EnableModuleLogging' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames' `
        -Nombre '*' -Valor '*' -Tipo String -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' `
        -Nombre 'ProcessCreationIncludeCmdLine_Enabled' -Valor 1 -Simular:$Simular `
        -Motivo 'el evento 4688 incluira la linea de comandos completa' | Out-Null

    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> auditoria de procesos, logon y politicas' 'SIMULA'
        Write-Bitacora 'SIMULACRO -> PowerShell v2 desinstalado' 'SIMULA'
    } else {
        foreach ($cat in @('Creacion de procesos','Process Creation')) {
            & auditpol.exe /set /subcategory:"$cat" /success:enable /failure:enable > $null 2>&1
        }
        foreach ($guid in @('{0CCE922B-69AE-11D9-BED3-505054503030}',  # Creacion de procesos
                            '{0CCE9215-69AE-11D9-BED3-505054503030}',  # Inicio de sesion
                            '{0CCE9217-69AE-11D9-BED3-505054503030}',  # Cierre de sesion
                            '{0CCE9228-69AE-11D9-BED3-505054503030}',  # Uso de privilegios sensibles
                            '{0CCE922F-69AE-11D9-BED3-505054503030}',  # Cambio de politica de auditoria
                            '{0CCE9235-69AE-11D9-BED3-505054503030}',  # Gestion de cuentas de usuario
                            '{0CCE9226-69AE-11D9-BED3-505054503030}')) { # Servicios del sistema
            & auditpol.exe /set /subcategory:"$guid" /success:enable /failure:enable > $null 2>&1
        }
        Write-Bitacora 'auditoria activada: procesos, inicios de sesion, privilegios, cambios de politica' 'CAMBIO'

        # PowerShell v2: cierra el ataque de degradacion que esquiva el registro.
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop
            if ($f.State -eq 'Enabled') {
                Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -ErrorAction Stop | Out-Null
                Write-Bitacora 'PowerShell v2 desinstalado: sin ataque de degradacion' 'CAMBIO'
            } else { Write-Bitacora 'PowerShell v2 ya estaba fuera' 'INFO' }
        } catch { Write-Bitacora "PowerShell v2: $($_.Exception.Message)" 'AVISO' }

        # Ampliar los registros de eventos: los de fabrica se sobrescriben en dias.
        foreach ($lg in @('Security','System','Application','Microsoft-Windows-PowerShell/Operational',
                          'Microsoft-Windows-Windows Defender/Operational')) {
            & wevtutil.exe sl "$lg" /ms:196608000 > $null 2>&1
        }
        Write-Bitacora 'registros de eventos ampliados a 192 MB: el historial sobrevive semanas' 'CAMBIO'
    }
}

# ===========================================================================
# CAPA 4 -- PRIVACIDAD Y TELEMETRIA
# ===========================================================================

function Invoke-CapaPrivacidad {
    Write-Titulo 'CAPA 4 -- PRIVACIDAD Y TELEMETRIA'

    Write-Bitacora 'AVISO HONESTO: esto es Windows 11 HOME. El valor 0 de telemetria' 'AVISO'
    Write-Bitacora 'solo lo respetan Enterprise y Education. Aqui el suelo real es 1' 'AVISO'
    Write-Bitacora '(Requerido). Se pone 0 igualmente por si acaso, pero no te fies.' 'AVISO'

    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'AllowTelemetry' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' `
        -Nombre 'AllowTelemetry' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'AllowDeviceNameInTelemetry' -Valor 0 -Simular:$Simular `
        -Motivo 'que el nombre del equipo no viaje' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'DoNotShowFeedbackNotifications' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'LimitDiagnosticLogCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'LimitDumpCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
        -Nombre 'DisableOneSettingsDownloads' -Valor 1 -Simular:$Simular | Out-Null

    # Publicidad e identificadores
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' `
        -Nombre 'DisabledByGroupPolicy' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' `
        -Nombre 'Enabled' -Valor 0 -Simular:$Simular | Out-Null

    # Historial de actividad y linea de tiempo
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'PublishUserActivities' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'UploadUserActivities' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'EnableActivityFeed' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Nombre 'AllowCrossDeviceClipboard' -Valor 0 -Simular:$Simular | Out-Null

    # Recall y Windows AI: que no se hagan capturas de todo lo que haces.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' `
        -Nombre 'DisableAIDataAnalysis' -Valor 1 -Simular:$Simular `
        -Motivo 'Recall apagado: sin capturas continuas de la pantalla' | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' `
        -Nombre 'DisableAIDataAnalysis' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' `
        -Nombre 'AllowRecallEnablement' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' `
        -Nombre 'TurnOffWindowsCopilot' -Valor 1 -Simular:$Simular | Out-Null

    # Contenido sugerido, publicidad en el sistema y Bing en el menu Inicio
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
        -Nombre 'DisableWebSearch' -Valor 1 -Simular:$Simular -Motivo 'lo que escribes en Inicio no sale a Internet' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
        -Nombre 'ConnectedSearchUseWeb' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
        -Nombre 'AllowCortana' -Valor 0 -Simular:$Simular | Out-Null

    # Optimizacion de distribucion. Por defecto tu equipo REPARTE trozos de las
    # actualizaciones a desconocidos por Internet, y por eso escucha en el 7680
    # en todas las interfaces. Con 0 se descarga solo por HTTP y ese puerto se
    # cierra. Windows Update sigue funcionando igual.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' `
        -Nombre 'DODownloadMode' -Valor 0 -Simular:$Simular `
        -Motivo 'sin P2P: cierra el puerto 7680 y dejas de repartir a desconocidos' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' `
        -Nombre 'DODownloadMode' -Valor 0 -Simular:$Simular | Out-Null

    # Escritura, voz y tinta
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' `
        -Nombre 'RestrictImplicitTextCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' `
        -Nombre 'RestrictImplicitInkCollection' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' `
        -Nombre 'AllowInputPersonalization' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' `
        -Nombre 'AllowSpeechModelUpdate' -Valor 0 -Simular:$Simular | Out-Null

    # UBICACION -- estaba en Permitir a nivel de maquina Y de usuario.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' `
        -Nombre 'Value' -Valor 'Deny' -Tipo String -Simular:$Simular -Motivo 'ubicacion cerrada para todo el equipo' | Out-Null
    Set-ValorRegistro -Ruta 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' `
        -Nombre 'Value' -Valor 'Deny' -Tipo String -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Nombre 'DisableLocation' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Nombre 'DisableLocationScripting' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' `
        -Nombre 'DisableWindowsLocationProvider' -Valor 1 -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'lfsvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'servicio de geolocalizacion, estaba corriendo' | Out-Null

    # Otros recolectores
    Set-EstadoServicio -Nombre 'DiagTrack' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'experiencias del usuario conectado y telemetria' | Out-Null
    Set-EstadoServicio -Nombre 'dmwappushservice' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'diagnosticshub.standardcollector.service' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'RetailDemo' -Arranque Disabled -Detener -Simular:$Simular | Out-Null

    # Tareas de sugerencias comerciales (las SoftLanding que aparecieron)
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
        Write-Bitacora "tareas de telemetria y sugerencias desactivadas: $n" 'CAMBIO'
    } else {
        Write-Bitacora 'SIMULACRO -> desactivar tareas de telemetria, CEIP y SoftLanding' 'SIMULA'
    }

    # --- DNS -----------------------------------------------------------------
    # Tu Wi-Fi apunta a 127.0.0.1 y ahi no escucha nadie: cada consulta espera
    # a un servidor muerto antes de caer al 1.1.1.1.
    # 1.1.1.2 / 1.0.0.2 son los de Cloudflare que ademas bloquean malware.
    $wifi = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'VMware|Npcap|Loopback|Virtual' } |
            Select-Object -First 1
    # Si Nivel-Pelicula dejo a Unbound resolviendo en local, el DNS ya esta
    # mejor que con cualquier tercero: no se toca.
    $unbound = Get-Service -Name 'unbound' -ErrorAction SilentlyContinue
    if ($unbound -and $unbound.Status -eq 'Running') {
        Write-Bitacora 'DNS: lo resuelve Unbound en este equipo (Nivel-Pelicula); no se toca' 'INFO'
        $wifi = $null
    }
    if ($wifi) {
        if ($Simular) {
            Write-Bitacora "SIMULACRO -> DNS de '$($wifi.Name)' = 1.1.1.2 y 1.0.0.2, con DNS sobre HTTPS" 'SIMULA'
        } else {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $wifi.InterfaceIndex `
                    -ServerAddresses ('1.1.1.2','1.0.0.2') -ErrorAction Stop
                Write-Bitacora "DNS de '$($wifi.Name)' -> 1.1.1.2 / 1.0.0.2 (bloquean malware); fuera el 127.0.0.1 muerto" 'CAMBIO'

                # DNS sobre HTTPS: tu proveedor deja de ver que dominios visitas.
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
                    -Nombre 'EnableAutoDoh' -Valor 2 -Simular:$false -Motivo 'DNS cifrado obligatorio' | Out-Null
                Write-Bitacora 'DNS sobre HTTPS activado: tu proveedor deja de ver los dominios que visitas' 'CAMBIO'
                & ipconfig.exe /flushdns > $null 2>&1
            } catch { Write-Bitacora "DNS: $($_.Exception.Message)" 'AVISO' }
        }
    }
}

# ===========================================================================
# CAPA 5 -- SIGILO EN LA RED LOCAL
# "Que en mi red no aparezca y aun asi este conectado."
# Riesgo: bajo, pero toca red. Reversor armado.
# ===========================================================================

function Invoke-CapaSigilo {
    Write-Titulo 'CAPA 5 -- SIGILO EN LA RED LOCAL'

    Write-Bitacora 'LIMITE HONESTO: esto te quita del mapa de red, de las respuestas' 'AVISO'
    Write-Bitacora 'a ping y de todo protocolo de descubrimiento. NO te vuelve invisible:' 'AVISO'
    Write-Bitacora 'quien controle el router te ve en la tabla ARP y en el DHCP, y quien' 'AVISO'
    Write-Bitacora 'este en tu red te encuentra con un barrido ARP. Eso es fisica de la' 'AVISO'
    Write-Bitacora 'capa 2 y ninguna configuracion de Windows lo cambia.' 'AVISO'
    Write-Host ''

    # --- Servicios de descubrimiento -----------------------------------------
    Set-EstadoServicio -Nombre 'FDResPub' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'publicacion de recursos: es lo que te anuncia a los demas' | Out-Null
    Set-EstadoServicio -Nombre 'fdPHost' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'lltdsvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'topologia de nivel de vinculo: es lo que te dibuja en el mapa de red' | Out-Null
    Set-EstadoServicio -Nombre 'LanmanServer' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'CDPSvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'plataforma de dispositivos conectados, escuchaba en 0.0.0.0:5040' | Out-Null
    Set-EstadoServicio -Nombre 'CDPUserSvc' -Arranque Manual -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'DevicePickerUserSvc' -Arranque Disabled -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'DevicesFlowUserSvc' -Arranque Disabled -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'PNRPsvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'p2psvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'p2pimsvc' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'PNRPAutoReg' -Arranque Disabled -Detener -Simular:$Simular | Out-Null
    Set-EstadoServicio -Nombre 'iphlpsvc' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'tuneles IPv6 (Teredo, 6to4, ISATAP): superficie que no usas' | Out-Null

    # --- Resolucion de nombres insegura --------------------------------------
    # LLMNR y NetBIOS son la base de los ataques con Responder: alguien en tu
    # red responde "yo soy ese equipo" y se lleva tu hash NTLM.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' `
        -Nombre 'EnableMulticast' -Valor 0 -Simular:$Simular `
        -Motivo 'LLMNR fuera: corta el envenenamiento de nombres' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' `
        -Nombre 'EnableMDNS' -Valor 0 -Simular:$Simular -Motivo 'mDNS fuera' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' `
        -Nombre 'NodeType' -Valor 2 -Simular:$Simular -Motivo 'NetBIOS solo punto a punto, sin difusion' | Out-Null

    # NetBIOS sobre TCP/IP por adaptador: 2 = deshabilitado.
    # Estaba en 0 (= "lo que diga el DHCP"), o sea a merced de la red ajena.
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> NetBIOS sobre TCP/IP deshabilitado en cada adaptador' 'SIMULA'
    } else {
        $n = 0
        try {
            Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop | ForEach-Object {
                $r = Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } -ErrorAction SilentlyContinue
                if ($r -and $r.ReturnValue -in @(0,1)) { $n++ }
            }
        } catch { }
        Write-Bitacora "NetBIOS sobre TCP/IP deshabilitado en $n adaptadores" 'CAMBIO'
    }

    # NoActiveProbe queda FUERA del blindaje por defecto, y no por descuido.
    #
    # Corta el sondeo de conectividad que Windows hace contra Microsoft, lo cual
    # suena bien. El problema es el efecto secundario: el icono de red pasa a
    # mostrar el aviso de "sin Internet" AUNQUE estes navegando perfectamente, y
    # varias aplicaciones que preguntan al Administrador de listas de red se lo
    # creen y se comportan como si estuvieran desconectadas.
    #
    # Ganancia de privacidad: minima. Coste: te vuelves loco pensando que el
    # blindaje te rompio la red cuando no fue asi. Con -CortarSondeoMicrosoft
    # se activa igualmente, sabiendo lo que implica.
    if ($CortarSondeoMicrosoft) {
        Write-Bitacora 'AVISO: vas a ver el icono de red como "sin Internet" aunque navegues bien.' 'AVISO'
        Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' `
            -Nombre 'NoActiveProbe' -Valor 1 -Simular:$Simular `
            -Motivo 'sin sondeo activo hacia Microsoft (a costa del indicador de red)' | Out-Null
    } else {
        Write-Bitacora 'sondeo de conectividad de Windows: se deja como esta.' 'INFO'
        Write-Bitacora '  Cortarlo haria que el icono de red dijese "sin Internet" siempre.' 'INFO'
        Write-Bitacora '  Si aun asi lo quieres:  .\Blindar.ps1 -Aplicar -CortarSondeoMicrosoft' 'INFO'
    }

    # WPAD: la deteccion automatica de proxy es un vector de intercepcion clasico.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' `
        -Nombre 'WpadOverride' -Valor 1 -Simular:$Simular -Motivo 'WPAD anulado' | Out-Null
    Set-EstadoServicio -Nombre 'WinHttpAutoProxySvc' -Arranque Manual -Simular:$Simular | Out-Null

    # --- No anunciarse por DNS ni por DHCP -----------------------------------
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
        -Nombre 'DisableDynamicUpdate' -Valor 1 -Simular:$Simular `
        -Motivo 'no registrar tu nombre en el DNS de la red ajena' | Out-Null
    if (-not $Simular) {
        try {
            Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
                Set-DnsClient -InterfaceIndex $_.InterfaceIndex -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue
                Set-DnsClient -InterfaceIndex $_.InterfaceIndex -UseSuffixWhenRegistering $false -ErrorAction SilentlyContinue
            }
            Write-Bitacora 'los adaptadores dejan de registrar su direccion en el DNS de la red' 'CAMBIO'
        } catch { }
    }

    # --- No responder a ping -------------------------------------------------
    # Se bloquea SOLO el eco (tipo 8). Los tipos 3 y 11 se dejan pasar: sin
    # ellos se rompe el descubrimiento de MTU y algunas webs dejan de cargar.
    # Este es el error que arruina la conectividad en la mayoria de guias.
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> sin respuesta a ping (solo eco; se preserva ICMP tipo 3 y 11)' 'SIMULA'
    } else {
        foreach ($sp in @(@('Centinela-Sin-Ping-IPv4','ICMPv4','8:*'),
                          @('Centinela-Sin-Ping-IPv6','ICMPv6','128:*'))) {
            try { Remove-NetFirewallRule -DisplayName $sp[0] -ErrorAction SilentlyContinue } catch { }
            try {
                New-NetFirewallRule -DisplayName $sp[0] -Direction Inbound -Action Block `
                    -Protocol $sp[1] -IcmpType $sp[2] -Profile Any -Enabled True `
                    -Description 'No responder al eco. Los tipos 3 y 11 siguen permitidos para no romper el descubrimiento de MTU.' `
                    -ErrorAction Stop | Out-Null
            } catch { Write-Bitacora "regla sin-ping: $($_.Exception.Message)" 'AVISO' }
        }
        Write-Bitacora 'el equipo deja de responder a ping; ICMP tipo 3 y 11 preservados' 'CAMBIO'
    }

    # --- Protegerse de la propia red -----------------------------------------
    # Bloqueo explicito de toda entrada procedente de la subred local. Las
    # reglas de bloqueo pesan mas que las de permiso, asi que esto anula
    # cualquier regla suelta que se haya colado.
    # NO afecta a la salida ni a las respuestas del trafico que tu inicias.
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> bloqueo explicito de toda entrada desde la subred local' 'SIMULA'
    } else {
        try { Remove-NetFirewallRule -DisplayName 'Centinela-Blindaje-Subred-Local' -ErrorAction SilentlyContinue } catch { }
        try {
            New-NetFirewallRule -DisplayName 'Centinela-Blindaje-Subred-Local' `
                -Direction Inbound -Action Block -RemoteAddress LocalSubnet `
                -Profile Public,Private -Enabled True `
                -Description 'Nadie de la red local puede iniciar conexiones hacia este equipo. El trafico que TU inicias sigue funcionando: sus respuestas son trafico con estado.' `
                -ErrorAction Stop | Out-Null
            Write-Bitacora 'nadie de tu red local puede iniciar conexiones hacia ti' 'CAMBIO'
        } catch { Write-Bitacora "regla de subred: $($_.Exception.Message)" 'AVISO' }
    }

    # --- Perfil de red siempre publico ---------------------------------------
    if (-not $Simular) {
        try {
            Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $_.NetworkCategory -ne 'Public' } | ForEach-Object {
                Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Public -ErrorAction SilentlyContinue
                Write-Bitacora "perfil de '$($_.Name)' pasado a Publico" 'CAMBIO'
            }
        } catch { }
    }

    # --- MAC aleatoria: solo si se pide expresamente -------------------------
    if ($AleatorizarMAC) {
        Write-Bitacora 'AVISO: cambiar la MAC desconecta y reconecta el Wi-Fi' 'AVISO'
        if ($Simular) {
            Write-Bitacora 'SIMULACRO -> MAC del Wi-Fi aleatorizada' 'SIMULA'
        } else {
            try {
                $ad = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN' } | Select-Object -First 1
                if ($ad) {
                    # Unicast, administrada localmente: segundo bit del primer octeto a 1.
                    $b = 1..5 | ForEach-Object { '{0:X2}' -f (Get-Random -Min 0 -Max 256) }
                    $mac = '02' + ($b -join '')
                    Set-NetAdapterAdvancedProperty -Name $ad.Name -RegistryKeyword 'NetworkAddress' -RegistryValue $mac -ErrorAction Stop
                    Restart-NetAdapter -Name $ad.Name -Confirm:$false -ErrorAction Stop
                    Write-Bitacora "MAC del Wi-Fi cambiada a $mac (administrada localmente)" 'CAMBIO'
                }
            } catch { Write-Bitacora "MAC: $($_.Exception.Message). Activala a mano en Configuracion > Red > Wi-Fi > Direcciones de hardware aleatorias." 'AVISO' }
        }
    } else {
        Write-Bitacora 'MAC sin tocar. Para aleatorizarla: -AleatorizarMAC (reconecta el Wi-Fi),' 'INFO'
        Write-Bitacora 'o a mano en Configuracion > Red e Internet > Wi-Fi > Direcciones de hardware aleatorias.' 'INFO'
    }
}

# ===========================================================================
# CAPA 6 -- AISLAMIENTO DE LAS MAQUINAS VIRTUALES
# "Que jamas se conecten a mi red local."
# ===========================================================================

function Invoke-CapaVM {
    Write-Titulo 'CAPA 6 -- AISLAMIENTO DE LAS MAQUINAS VIRTUALES'

    $hayVMware = Get-Service -Name 'VMware*','VMnet*' -ErrorAction SilentlyContinue
    if (-not $hayVMware) {
        Write-Bitacora 'no se detecta VMware en este equipo; capa omitida' 'INFO'
        return
    }

    Write-Bitacora 'estrategia: las VMs pierden NAT y DHCP, quedan en red aislada de tipo' 'INFO'
    Write-Bitacora 'solo-anfitrion, y el firewall corta cualquier paso de las subredes' 'INFO'
    Write-Bitacora 'virtuales hacia tu red fisica. Una VM comprometida no llega a nada.' 'INFO'
    Write-Host ''

    # --- Cortar la salida de las VMs -----------------------------------------
    Set-EstadoServicio -Nombre 'VMware NAT Service' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'sin NAT las VMs no salen a Internet ni a tu LAN' | Out-Null
    Set-EstadoServicio -Nombre 'VMnetDHCP' -Arranque Disabled -Detener -Simular:$Simular `
        -Motivo 'sin DHCP virtual las VMs no reciben configuracion de red automatica' | Out-Null
    Set-EstadoServicio -Nombre 'VMUSBArbService' -Arranque Manual -Simular:$Simular `
        -Motivo 'arbitro USB: solo cuando de verdad uses una VM' | Out-Null

    # --- Muro entre las subredes virtuales y la red fisica --------------------
    $subredesVM = @('192.168.0.0/16','172.16.0.0/12','10.0.0.0/8')
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> reglas que bloquean el paso de las subredes VMnet a la red fisica' 'SIMULA'
    } else {
        try { Remove-NetFirewallRule -DisplayName 'Centinela-VM-Aislada-*' -ErrorAction SilentlyContinue } catch { }
        $idx = 0
        foreach ($vmnet in @('VMware Network Adapter VMnet1','VMware Network Adapter VMnet8')) {
            $ad = Get-NetAdapter -Name $vmnet -ErrorAction SilentlyContinue
            if (-not $ad) { continue }
            $idx++
            try {
                New-NetFirewallRule -DisplayName "Centinela-VM-Aislada-Entrada-$idx" `
                    -Direction Inbound -Action Block -InterfaceAlias $vmnet -Profile Any -Enabled True `
                    -Description 'Nada que venga de esta red virtual entra al anfitrion.' -ErrorAction Stop | Out-Null
                New-NetFirewallRule -DisplayName "Centinela-VM-Aislada-Salida-$idx" `
                    -Direction Outbound -Action Block -InterfaceAlias $vmnet -Profile Any -Enabled True `
                    -Description 'El anfitrion no inicia nada hacia esta red virtual.' -ErrorAction Stop | Out-Null
                Write-Bitacora "$vmnet aislado en ambos sentidos" 'CAMBIO'
            } catch { Write-Bitacora "aislamiento de $vmnet : $($_.Exception.Message)" 'AVISO' }
        }
        # Y los adaptadores virtuales, abajo mientras no se usen.
        foreach ($vmnet in @('VMware Network Adapter VMnet1','VMware Network Adapter VMnet8')) {
            try { Disable-NetAdapter -Name $vmnet -Confirm:$false -ErrorAction Stop; Write-Bitacora "$vmnet desactivado" 'CAMBIO' } catch { }
        }
    }

    # --- Sellar los canales VM -> anfitrion en cada .vmx ----------------------
    # Carpetas compartidas, portapapeles y arrastrar-soltar son los caminos por
    # los que se sale de una VM al anfitrion. Se cierran uno por uno.
    # ethernet0.connectionType es LA linea que importa:
    #   bridged  = la VM tiene IP propia en TU red, como otro equipo enchufado
    #              al router. Ve a todos tus dispositivos y ellos la ven a ella.
    #   nat      = sale a Internet a traves del anfitrion, y alcanza tu LAN.
    #   hostonly = red cerrada entre la VM y el anfitrion. No sale a ningun lado.
    # Con maquinas de laboratorio deliberadamente vulnerables, hostonly es la
    # unica opcion defendible.
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
        Write-Bitacora 'no se encontraron ficheros .vmx en las rutas habituales' 'INFO'
        Write-Bitacora 'si tienes VMs en otra carpeta, dimelo y aplico el sellado ahi' 'INFO'
    } else {
        foreach ($f in $vmx) {
            # Avisar del modo de red actual, que es lo que de verdad importa.
            $modo = try { ((Get-Content $f.FullName -ErrorAction Stop | Select-String '^ethernet0\.connectionType') -split '"')[1] } catch { '?' }
            if ($modo -eq 'bridged') {
                Write-Bitacora "$($f.Name) esta en PUENTE: tiene IP propia en tu red, como otro equipo enchufado al router." 'AVISO'
            } elseif ($modo -eq 'nat') {
                Write-Bitacora "$($f.Name) esta en NAT: sale a Internet y alcanza tu red local." 'AVISO'
            }

            if ($Simular) { Write-Bitacora "SIMULACRO -> $($f.Name): red $modo -> hostonly, y sin carpetas compartidas, portapapeles ni arrastrar-soltar" 'SIMULA'; continue }
            try {
                Copy-Item $f.FullName "$($f.FullName).centinela-copia" -Force -ErrorAction Stop
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
                Write-Bitacora "sellada: $($f.Name)" 'CAMBIO'
            } catch { Write-Bitacora "no se pudo sellar $($f.Name): $($_.Exception.Message)" 'AVISO' }
        }
    }

    Write-Host ''
    Write-Bitacora 'PARA VOLVER A USAR UNA VM: arranca los servicios VMware NAT Service y' 'INFO'
    Write-Bitacora 'VMnetDHCP, y reactiva el adaptador VMnet8. Mejor aun: configura la VM' 'INFO'
    Write-Bitacora 'como solo-anfitrion (host-only) sobre VMnet1 y dejala sin salida.' 'INFO'
}

# ===========================================================================
# CAPA 7 -- CONTROLADORES VULNERABLES (anti-BYOVD)
# Lo mas valioso de todo el blindaje, y no rompe VMware.
# ===========================================================================

function Invoke-CapaDrivers {
    Write-Titulo 'CAPA 7 -- CONTROLADORES VULNERABLES (anti-BYOVD)'

    Write-Bitacora 'BYOVD: el atacante trae SU PROPIO controlador firmado y vulnerable,' 'INFO'
    Write-Bitacora 'lo carga legitimamente, y desde el nucleo mata el antivirus. Es como' 'INFO'
    Write-Bitacora 'operan hoy casi todas las familias serias de ransomware.' 'INFO'
    Write-Bitacora 'La lista de bloqueo de Microsoft corta eso, funciona sin HVCI y NO' 'INFO'
    Write-Bitacora 'toca tus maquinas virtuales.' 'INFO'
    Write-Host ''

    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' `
        -Nombre 'VulnerableDriverBlocklistEnable' -Valor 1 -Simular:$Simular `
        -Motivo 'lista de bloqueo de controladores vulnerables de Microsoft' | Out-Null

    # Integridad de codigo en modo usuario: solo binarios firmados en procesos
    # que lo soporten. No rompe nada de lo que tienes.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
        -Nombre 'ConfigCIDisabled' -Valor 0 -Simular:$Simular | Out-Null

    # Impedir instalar controladores sin firmar.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Driver Signing' `
        -Nombre 'Policy' -Valor ([byte[]](0x01)) -Tipo Binary -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Driver Signing' `
        -Nombre 'BehaviorOnFailedVerify' -Valor 2 -Simular:$Simular `
        -Motivo 'rechazar controladores sin firma valida' | Out-Null

    # Proteccion de pila reforzada por hardware, si el equipo la soporta.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
        -Nombre 'FeatureSettingsOverride' -Valor 0 -Simular:$Simular | Out-Null

    # Estado de HVCI, sin tocarlo: solo informar.
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        $corriendo = if ($dg.SecurityServicesRunning -contains 2) { 'SI' } else { 'NO' }
        Write-Bitacora "Integridad de Memoria (HVCI) corriendo: $corriendo" 'INFO'
        if ($corriendo -eq 'NO') {
            Write-Bitacora 'HVCI NO se activa aqui a proposito: con VMware Workstation instalado' 'AVISO'
            Write-Bitacora 'degradaria o romperia tus maquinas virtuales. Decision tuya, no mia.' 'AVISO'
        }
    } catch { }

    # Estado de parches: un Windows sin parches vence a cualquier configuracion.
    if (-not $Simular) {
        try {
            $ult = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1)
            $dias = if ($ult.InstalledOn) { [int]((Get-Date) - $ult.InstalledOn).TotalDays } else { -1 }
            Write-Bitacora "ultimo parche instalado: $($ult.HotFixID) hace $dias dias" $(if ($dias -gt 45) { 'AVISO' } else { 'OK' })
            if ($dias -gt 45) {
                Write-Bitacora 'MAS DE 45 DIAS SIN PARCHES. Esto pesa mas que todo lo demas junto:' 'ERROR'
                Write-Bitacora 'la mayoria del ransomware entra por un fallo que ya tenia parche.' 'ERROR'
            }
        } catch { }
    }
}

# ===========================================================================
# CAPA 8 -- CREDENCIALES Y MEMORIA
# ===========================================================================

function Invoke-CapaCredenciales {
    Write-Titulo 'CAPA 8 -- CREDENCIALES Y MEMORIA'

    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

    # LSA Protection ya estaba en 2. Se refuerza y se anade el arranque.
    Set-ValorRegistro -Ruta $lsa -Nombre 'RunAsPPL' -Valor 2 -Simular:$Simular `
        -Motivo 'lsass protegido: mimikatz no puede leerlo' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'LmCompatibilityLevel' -Valor 5 -Simular:$Simular `
        -Motivo 'solo NTLMv2: ni LM ni NTLMv1, que se rompen en minutos' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'NoLMHash' -Valor 1 -Simular:$Simular `
        -Motivo 'no guardar el hash LM, que es trivial de romper' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'RestrictAnonymous' -Valor 1 -Simular:$Simular `
        -Motivo 'sin enumeracion anonima' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'RestrictAnonymousSAM' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'EveryoneIncludesAnonymous' -Valor 0 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'LimitBlankPasswordUse' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'DisableDomainCreds' -Valor 1 -Simular:$Simular `
        -Motivo 'no almacenar credenciales de red en el equipo' | Out-Null
    Set-ValorRegistro -Ruta $lsa -Nombre 'SCENoApplyLegacyAuditPolicy' -Valor 1 -Simular:$Simular | Out-Null

    # WDigest: si esta activo, tu contrasena vive EN CLARO en la memoria de lsass.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' `
        -Nombre 'UseLogonCredential' -Valor 0 -Simular:$Simular `
        -Motivo 'sin contrasenas en claro en memoria' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' `
        -Nombre 'Negotiate' -Valor 0 -Simular:$Simular | Out-Null

    # NTLM: firma y cifrado de 128 bits obligatorios en ambos sentidos.
    Set-ValorRegistro -Ruta "$lsa\MSV1_0" -Nombre 'NTLMMinClientSec' -Valor 537395200 -Simular:$Simular `
        -Motivo 'NTLM con firma e integridad de 128 bits obligatorias' | Out-Null
    Set-ValorRegistro -Ruta "$lsa\MSV1_0" -Nombre 'NTLMMinServerSec' -Valor 537395200 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta "$lsa\MSV1_0" -Nombre 'allownullsessionfallback' -Valor 0 -Simular:$Simular | Out-Null

    # Sin volcado de memoria: un volcado completo contiene claves y credenciales.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' `
        -Nombre 'CrashDumpEnabled' -Valor 0 -Simular:$Simular `
        -Motivo 'un volcado completo es un regalo forense para quien robe el disco' | Out-Null

    # Sin archivo de paginacion residual al apagar.
    Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
        -Nombre 'ClearPageFileAtShutdown' -Valor 1 -Simular:$Simular | Out-Null

    # Cifrado fuerte y nada de protocolos rotos.
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' `
        -Nombre 'SecureProtocols' -Valor 2688 -Simular:$Simular -Motivo 'solo TLS 1.2 y 1.3' | Out-Null
    foreach ($p in @('SSL 2.0','SSL 3.0','TLS 1.0','TLS 1.1')) {
        foreach ($rol in @('Client','Server')) {
            Set-ValorRegistro -Ruta "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$p\$rol" `
                -Nombre 'Enabled' -Valor 0 -Simular:$Simular | Out-Null
            Set-ValorRegistro -Ruta "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$p\$rol" `
                -Nombre 'DisabledByDefault' -Valor 1 -Simular:$Simular | Out-Null
        }
    }
    Write-Bitacora 'SSL 2.0, SSL 3.0, TLS 1.0 y TLS 1.1 desactivados; solo TLS 1.2 y 1.3' $(if ($Simular) { 'SIMULA' } else { 'CAMBIO' })

    # Bloqueo de pantalla
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Nombre 'InactivityTimeoutSecs' -Valor 600 -Simular:$Simular -Motivo 'bloqueo a los 10 minutos' | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Nombre 'DontDisplayLastUserName' -Valor 1 -Simular:$Simular | Out-Null
    Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Nombre 'DisableLockWorkstation' -Valor 0 -Simular:$Simular | Out-Null

    # Cuentas del sandbox de Codex: solo aviso, no se tocan sin permiso.
    try {
        $sospechosas = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and $_.Name -match 'CodexSandbox' }
        foreach ($u in $sospechosas) {
            Write-Bitacora "cuenta local habilitada: $($u.Name) -- es del Codex CLI de OpenAI." 'AVISO'
            Write-Bitacora '  no se toca sin tu permiso. Si ya no usas Codex, deshabilitala.' 'AVISO'
        }
    } catch { }
}

# ===========================================================================
# CAPA 9 -- ANTI-RANSOMWARE PROFUNDO
# ===========================================================================

function Invoke-CapaRansomware {
    Write-Titulo 'CAPA 9 -- ANTI-RANSOMWARE PROFUNDO'

    # --- Acceso Controlado a Carpetas ----------------------------------------
    # Estaba APAGADO. Es la defensa nativa que impide que un proceso desconocido
    # escriba en tus carpetas. Va primero en AUDITORIA: durante unos dias apunta
    # todo lo que bloquearia sin bloquearlo, para que la lista de permitidos se
    # construya con datos reales y no rompiendote el trabajo.
    $carpetas = @(
        "$env:USERPROFILE\Desktop\obsidian\Vault",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Pictures",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Seguridad"
    ) | Where-Object { Test-Path $_ }

    foreach ($extra in @("$env:USERPROFILE\Scriptorium", "$env:USERPROFILE\scriptorium", "$env:USERPROFILE\Documents\Scriptorium")) {
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
        Write-Bitacora "SIMULACRO -> Acceso Controlado a Carpetas en AUDITORIA" 'SIMULA'
        $carpetas   | ForEach-Object { Write-Bitacora "SIMULACRO ->   protegeria: $_" 'SIMULA' }
        $permitidas | ForEach-Object { Write-Bitacora "SIMULACRO ->   permitiria: $(Split-Path $_ -Leaf)" 'SIMULA' }
    } else {
        Set-PreferenciaDefender -Nombre 'EnableControlledFolderAccess' -Valor 2 `
            -Motivo 'MODO AUDITORIA: apunta lo que bloquearia, sin bloquear todavia' | Out-Null
        foreach ($c in $carpetas) {
            try { Add-MpPreference -ControlledFolderAccessProtectedFolders $c -ErrorAction Stop; Write-Bitacora "protegida: $c" 'CAMBIO' }
            catch { Write-Bitacora "no se pudo proteger $c : $($_.Exception.Message)" 'AVISO' }
        }
        foreach ($a in $permitidas) {
            try { Add-MpPreference -ControlledFolderAccessAllowedApplications $a -ErrorAction Stop; Write-Bitacora "permitida: $(Split-Path $a -Leaf)" 'CAMBIO' }
            catch { }
        }
        Write-Host ''
        Write-Bitacora 'CFA queda en AUDITORIA. Usalo unos dias con normalidad y luego mira' 'AVISO'
        Write-Bitacora 'que se habria bloqueado con:  .\Auditar.ps1 -Cfa' 'AVISO'
        Write-Bitacora 'Cuando la lista este afinada, pasalo a bloqueo con:' 'AVISO'
        Write-Bitacora '  Set-MpPreference -EnableControlledFolderAccess Enabled' 'AVISO'
    }

    # --- Proteccion del Sistema y puntos de restauracion ----------------------
    if ($Simular) {
        Write-Bitacora 'SIMULACRO -> Proteccion del Sistema activa con 10% del disco' 'SIMULA'
    } else {
        $orden = "Enable-ComputerRestore -Drive 'C:\'; 'SR-OK'"
        $res = & powershell.exe -NoProfile -Command $orden 2>&1
        if ("$res" -match 'SR-OK') { Write-Bitacora 'Proteccion del Sistema activada en C:' 'CAMBIO' }
        else { Write-Bitacora "Proteccion del Sistema: $res" 'AVISO' }
        & vssadmin.exe resize shadowstorage /for=C: /on=C: /maxsize=10% > $null 2>&1
        Write-Bitacora 'espacio para instantaneas: 10% del disco' 'CAMBIO'
    }

    # --- Vigilar las herramientas que usa el ransomware ----------------------
    # vssadmin, wbadmin, bcdedit y wmic borran copias y desactivan la
    # recuperacion. No se bloquean (los necesita el propio Windows), pero cada
    # ejecucion queda registrada, y eso da la alerta temprana.
    if (-not $Simular) {
        foreach ($h in @('vssadmin.exe','wbadmin.exe','bcdedit.exe','wmic.exe','cipher.exe')) {
            $k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$h"
            Set-ValorRegistro -Ruta $k -Nombre 'GlobalFlag' -Valor 512 -Simular:$false `
                -Motivo "auditar cada ejecucion de $h" | Out-Null
        }
        Write-Bitacora 'vssadmin, wbadmin, bcdedit, wmic y cipher quedan auditados en el registro de eventos' 'CAMBIO'
    } else {
        Write-Bitacora 'SIMULACRO -> auditar vssadmin, wbadmin, bcdedit, wmic y cipher' 'SIMULA'
    }

    Write-Host ''
    Write-Bitacora 'VERDAD INCOMODA: la unica defensa que de verdad funciona contra el' 'AVISO'
    Write-Bitacora 'ransomware es una copia de seguridad DESCONECTADA. Todo lo anterior' 'AVISO'
    Write-Bitacora 'reduce la probabilidad; una copia en un disco que no esta enchufado' 'AVISO'
    Write-Bitacora 'es lo unico que garantiza que recuperas tus cosas. OneDrive no cuenta:' 'AVISO'
    Write-Bitacora 'sincroniza los archivos cifrados igual de rapido que los buenos.' 'AVISO'
}

# ===========================================================================
# PRINCIPAL
# ===========================================================================

Show-Cabecera

if (-not $Simular) {
    if (-not (Assert-Elevado -Script $PSCommandPath -Argumentos @(
        '-Aplicar'
        '-Capas'; ($Capas -join ',')
        '-MinutosReversor'; $MinutosReversor
        $(if ($SinPreguntar)   { '-SinPreguntar' })
        $(if ($AleatorizarMAC) { '-AleatorizarMAC' })
    ) )) { return }

    if (-not $Orquestado) {
        Write-Host '  Escribe BLINDAR para continuar, o cualquier otra cosa para salir.' -ForegroundColor Yellow
        if ((Read-Host '  >') -ne 'BLINDAR') { Write-Host '  Cancelado. No se ha tocado nada.' -ForegroundColor Green; return }
    }
}

Write-Bitacora "inicio -- modo: $(if ($Simular) { 'SIMULACRO' } else { 'REAL' })" 'INFO'

# Estado de partida, para poder contrastar despues
Write-Titulo 'ESTADO DE PARTIDA'
$antes = Test-Conectividad
if (-not $antes.Sano -and -not $Simular) {
    Write-Bitacora 'YA NO HAY INTERNET ANTES DE EMPEZAR. Se aborta: primero arregla la red.' 'ERROR'
    return
}

# Respaldo. Si falla, aqui se acaba.
$carpetaResp = Backup-EstadoSistema -Simular:$Simular
$scriptEmerg = Join-Path $carpetaResp 'EMERGENCIA-restaurar-red.ps1'

# Reversor armado antes de cualquier capa que toque la red
$capasDeRed = @('puertos','sigilo','vm','privacidad')
$tocaRed = ($Capas | Where-Object { $capasDeRed -contains $_ }).Count -gt 0

if ($tocaRed -and -not $Simular) {
    if (-not (Enable-Reversor -ScriptEmergencia $scriptEmerg -Minutos $MinutosReversor)) { return }
}

# Ejecucion de las capas
$mapa = [ordered]@{
    'defender'     = { Invoke-CapaDefender }
    'puertos'      = { Invoke-CapaPuertos }
    'cerrojos'     = { Invoke-CapaCerrojos }
    'privacidad'   = { Invoke-CapaPrivacidad }
    'sigilo'       = { Invoke-CapaSigilo }
    'vm'           = { Invoke-CapaVM }
    'drivers'      = { Invoke-CapaDrivers }
    'credenciales' = { Invoke-CapaCredenciales }
    'ransomware'   = { Invoke-CapaRansomware }
}

foreach ($c in $mapa.Keys) {
    if ($Capas -notcontains $c) { continue }
    try { & $mapa[$c] } catch { Write-Bitacora "capa '$c' fallo: $($_.Exception.Message)" 'ERROR' }

    # Tras cada capa que toca red, comprobar que seguimos vivos.
    if (($capasDeRed -contains $c) -and -not $Simular) {
        Write-Host ''
        $chk = Test-Conectividad -Silencioso
        if (-not $chk.Sano) {
            Write-Bitacora "LA CAPA '$c' ROMPIO LA CONECTIVIDAD. Revirtiendo todo ahora." 'ERROR'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptEmerg -Auto
            Disable-Reversor
            return
        }
        Write-Bitacora "tras la capa '$c': la conectividad sigue intacta" 'OK'
    }
}

# Cierre
Write-Titulo 'COMPROBACION FINAL'
if ($Simular) {
    Write-Host ''
    Write-Host '  Esto ha sido un SIMULACRO. No se ha cambiado nada.' -ForegroundColor Green
    Write-Host '  Revisa la bitacora y, si te convence, ejecuta:' -ForegroundColor Green
    Write-Host '     .\Blindar.ps1 -Aplicar' -ForegroundColor White
    Write-Host ''
} else {
    if ($tocaRed) {
        $firme = Confirm-Supervivencia -ScriptEmergencia $scriptEmerg -SinPreguntar:$SinPreguntar
        if (-not $firme) { Write-Host '  Se revirtio. El equipo esta como antes.' -ForegroundColor Yellow; return }
    }
    Test-Conectividad | Out-Null
    Write-Host ''
    Write-Host '  Blindaje aplicado.' -ForegroundColor Green
    Write-Host "  Respaldo:  $carpetaResp" -ForegroundColor DarkGray
    Write-Host "  Bitacora:  $script:Log" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Para deshacerlo todo:      .\Restaurar.ps1' -ForegroundColor DarkGray
    Write-Host '  Si algo va mal con la red: doble clic en' -ForegroundColor DarkGray
    Write-Host "     $scriptEmerg" -ForegroundColor White
    Write-Host ''
    Write-Host '  REINICIA cuando puedas: varios cambios (UAC, controladores,' -ForegroundColor Yellow
    Write-Host '  auditoria, PowerShell v2) no entran del todo hasta el reinicio.' -ForegroundColor Yellow
    Write-Host ''
}
