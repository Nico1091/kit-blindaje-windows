<#
.SYNOPSIS
    Informe de estado de seguridad. SOLO LECTURA: no cambia nada, nunca.

.DESCRIPTION
    Recorre todo lo que importa, puntua el estado y escribe un informe en
    Markdown dentro de Informes\.

.EXAMPLE
    .\Auditar.ps1
    Informe completo en pantalla y en fichero.

.EXAMPLE
    .\Auditar.ps1 -Cfa
    Solo los bloqueos del Acceso Controlado a Carpetas de los ultimos 7 dias.
    Es lo que hay que mirar antes de pasar CFA de auditoria a bloqueo.
#>

[CmdletBinding()]
param(
    [switch]$Cfa,
    [int]$Dias = 7
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\Nucleo.ps1')

$script:Hallazgos = New-Object System.Collections.ArrayList
$script:Puntos    = 0
$script:PuntosMax = 0

function Add-Hallazgo {
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Asunto,
        [Parameter(Mandatory)][ValidateSet('BIEN','AVISO','GRAVE','INFO')][string]$Estado,
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
        if ($Estado -eq 'BIEN') { $script:Puntos += $Peso }
    }
    $color = switch ($Estado) { 'BIEN' { 'Green' } 'AVISO' { 'Yellow' } 'GRAVE' { 'Red' } default { 'Gray' } }
    $marca = switch ($Estado) { 'BIEN' { '  OK   ' } 'AVISO' { ' AVISO ' } 'GRAVE' { ' GRAVE ' } default { ' info  ' } }
    Write-Host ("[{0}] {1,-46} {2}" -f $marca, $Asunto, $Detalle) -ForegroundColor $color
}

# ===========================================================================
# MODO CFA: que se habria bloqueado
# ===========================================================================

if ($Cfa) {
    Write-Titulo "ACCESO CONTROLADO A CARPETAS -- ULTIMOS $Dias DIAS"
    $desde = (Get-Date).AddDays(-$Dias)
    try {
        # 1123 = bloqueo real, 1124 = bloqueo que se habria producido (auditoria)
        $ev = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-Windows Defender/Operational'
            Id        = 1123, 1124
            StartTime = $desde
        } -ErrorAction Stop

        if (-not $ev) {
            Write-Host ''
            Write-Host '  Ninguna aplicacion habria sido bloqueada en este periodo.' -ForegroundColor Green
            Write-Host '  Puedes pasar CFA a bloqueo con tranquilidad:' -ForegroundColor Green
            Write-Host '     Set-MpPreference -EnableControlledFolderAccess Enabled' -ForegroundColor White
        } else {
            $ev | ForEach-Object {
                $x = [xml]$_.ToXml()
                $d = @{}
                $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
                [pscustomobject]@{
                    Cuando   = $_.TimeCreated
                    Tipo     = if ($_.Id -eq 1123) { 'BLOQUEADO' } else { 'se habria bloqueado' }
                    Programa = $d['Process']
                    Ruta     = $d['Path']
                }
            } | Sort-Object Programa -Unique | Format-Table -AutoSize

            Write-Host ''
            Write-Host '  Para permitir uno de estos programas:' -ForegroundColor Cyan
            Write-Host '     Add-MpPreference -ControlledFolderAccessAllowedApplications "<ruta>"' -ForegroundColor White
        }
    } catch {
        Write-Host "  No hay eventos, o CFA no esta activo todavia. ($($_.Exception.Message))" -ForegroundColor Yellow
    }
    Write-Host ''
    return
}

# ===========================================================================
# INFORME COMPLETO
# ===========================================================================

Write-Host ''
Write-Host '   #############################################################' -ForegroundColor DarkCyan
Write-Host '   #         C E N T I N E L A   --   A U D I T O R I A        #' -ForegroundColor White
Write-Host '   #     Solo lectura. Este script no cambia nada, nunca.      #' -ForegroundColor DarkCyan
Write-Host '   #############################################################' -ForegroundColor DarkCyan

$elevado = Test-Elevado
if (-not $elevado) {
    Write-Host ''
    Write-Host '  Sin permisos de administrador: no podras ver las exclusiones de' -ForegroundColor Yellow
    Write-Host '  Defender ni algunos registros. Para el informe completo, lanza' -ForegroundColor Yellow
    Write-Host '  esta consola como administrador.' -ForegroundColor Yellow
}

# --- Sistema ---------------------------------------------------------------
Write-Titulo 'SISTEMA'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$edicion = $cv.EditionID
Add-Hallazgo -Area 'Sistema' -Asunto 'Edicion de Windows' -Estado 'INFO' `
    -Detalle "$edicion, version $($cv.DisplayVersion), compilacion $($cv.CurrentBuild).$($cv.UBR)"
if ($edicion -eq 'Core') {
    Add-Hallazgo -Area 'Sistema' -Asunto 'Limites de la edicion Home' -Estado 'INFO' `
        -Detalle 'sin directiva de grupo, sin BitLocker administrable, sin AppLocker, telemetria con suelo en "Requerido"'
}

try {
    $ult = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    $dias = if ($ult.InstalledOn) { [int]((Get-Date) - $ult.InstalledOn).TotalDays } else { 999 }
    Add-Hallazgo -Area 'Sistema' -Asunto 'Antiguedad de los parches' -Peso 3 `
        -Estado $(if ($dias -le 45) { 'BIEN' } elseif ($dias -le 75) { 'AVISO' } else { 'GRAVE' }) `
        -Detalle "ultimo: $($ult.HotFixID), hace $dias dias" `
        -Arreglo 'Configuracion > Windows Update > Buscar actualizaciones'
} catch { }

# --- Defender --------------------------------------------------------------
Write-Titulo 'DEFENDER'
try {
    $st = Get-MpComputerStatus
    $pf = Get-MpPreference

    Add-Hallazgo -Area 'Defender' -Asunto 'Proteccion en tiempo real' -Peso 3 `
        -Estado $(if ($st.RealTimeProtectionEnabled) { 'BIEN' } else { 'GRAVE' }) `
        -Detalle $st.RealTimeProtectionEnabled
    Add-Hallazgo -Area 'Defender' -Asunto 'Proteccion contra manipulaciones' -Peso 3 `
        -Estado $(if ($st.IsTamperProtected) { 'BIEN' } else { 'GRAVE' }) `
        -Detalle $st.IsTamperProtected `
        -Arreglo 'Seguridad de Windows > Proteccion antivirus > Administrar la configuracion'
    Add-Hallazgo -Area 'Defender' -Asunto 'Supervision de comportamiento' -Peso 2 `
        -Estado $(if ($st.BehaviorMonitorEnabled) { 'BIEN' } else { 'GRAVE' }) -Detalle $st.BehaviorMonitorEnabled

    $edadFirmas = if ($st.AntivirusSignatureLastUpdated) { [int]((Get-Date) - $st.AntivirusSignatureLastUpdated).TotalDays } else { 99 }
    Add-Hallazgo -Area 'Defender' -Asunto 'Antiguedad de las firmas' -Peso 2 `
        -Estado $(if ($edadFirmas -le 3) { 'BIEN' } elseif ($edadFirmas -le 7) { 'AVISO' } else { 'GRAVE' }) `
        -Detalle "$edadFirmas dias"

    Add-Hallazgo -Area 'Defender' -Asunto 'Acceso Controlado a Carpetas' -Peso 3 `
        -Estado $(switch ($pf.EnableControlledFolderAccess) { 1 { 'BIEN' } 2 { 'AVISO' } default { 'GRAVE' } }) `
        -Detalle $(switch ($pf.EnableControlledFolderAccess) { 0 { 'APAGADO -- es la defensa anti-ransomware nativa' } 1 { 'bloqueando' } 2 { 'en auditoria (apunta pero no bloquea)' } default { '?' } }) `
        -Arreglo 'Blindar.ps1 -Aplicar -Capas ransomware'

    Add-Hallazgo -Area 'Defender' -Asunto 'Proteccion de red' -Peso 3 `
        -Estado $(switch ($pf.EnableNetworkProtection) { 1 { 'BIEN' } 2 { 'AVISO' } default { 'GRAVE' } }) `
        -Detalle $(if ($pf.EnableNetworkProtection -eq 0) { 'APAGADA -- no corta las conexiones a dominios de mando y control' } else { 'activa' }) `
        -Arreglo 'Blindar.ps1 -Aplicar -Capas defender'

    Add-Hallazgo -Area 'Defender' -Asunto 'Nivel de bloqueo en la nube' -Peso 2 `
        -Estado $(if ($pf.CloudBlockLevel -ge 2) { 'BIEN' } else { 'AVISO' }) `
        -Detalle $(switch ($pf.CloudBlockLevel) { 0 { 'predeterminado (bajo)' } 2 { 'alto' } 4 { 'alto plus' } 6 { 'tolerancia cero' } default { $pf.CloudBlockLevel } })

    $nAsr = if ($pf.AttackSurfaceReductionRules_Ids) { $pf.AttackSurfaceReductionRules_Ids.Count } else { 0 }
    $bloqueando = 0
    if ($pf.AttackSurfaceReductionRules_Actions) {
        $bloqueando = ($pf.AttackSurfaceReductionRules_Actions | Where-Object { $_ -eq 1 } | Measure-Object).Count
    }
    Add-Hallazgo -Area 'Defender' -Asunto 'Reglas ASR configuradas' -Peso 3 `
        -Estado $(if ($nAsr -ge 18) { 'BIEN' } elseif ($nAsr -ge 10) { 'AVISO' } else { 'GRAVE' }) `
        -Detalle "$nAsr de 19 ($bloqueando en modo bloqueo)" `
        -Arreglo 'Blindar.ps1 -Aplicar -Capas defender'

    # Las exclusiones son lo primero que toca un atacante.
    if ($elevado) {
        $ex = @()
        if ($pf.ExclusionPath)      { $ex += $pf.ExclusionPath }
        if ($pf.ExclusionProcess)   { $ex += $pf.ExclusionProcess }
        if ($pf.ExclusionExtension) { $ex += $pf.ExclusionExtension }
        Add-Hallazgo -Area 'Defender' -Asunto 'Exclusiones' -Peso 3 `
            -Estado $(if ($ex.Count -eq 0) { 'BIEN' } else { 'AVISO' }) `
            -Detalle $(if ($ex.Count -eq 0) { 'ninguna -- asi debe ser' } else { "$($ex.Count): $($ex -join ' | ')" }) `
            -Arreglo 'Revisa una por una. Un atacante SIEMPRE anade una exclusion antes de nada.'
    } else {
        Add-Hallazgo -Area 'Defender' -Asunto 'Exclusiones' -Estado 'INFO' -Detalle 'requiere administrador'
    }
} catch { Add-Hallazgo -Area 'Defender' -Asunto 'Consulta de Defender' -Estado 'GRAVE' -Detalle $_.Exception.Message -Peso 3 }

# --- Firewall --------------------------------------------------------------
Write-Titulo 'FIREWALL Y RED'
try {
    foreach ($p in Get-NetFirewallProfile) {
        Add-Hallazgo -Area 'Firewall' -Asunto "Perfil $($p.Name): activo" -Peso 2 `
            -Estado $(if ($p.Enabled) { 'BIEN' } else { 'GRAVE' }) -Detalle $p.Enabled
        Add-Hallazgo -Area 'Firewall' -Asunto "Perfil $($p.Name): entrada" -Peso 1 `
            -Estado $(if ($p.DefaultInboundAction -eq 'Block') { 'BIEN' } else { 'AVISO' }) `
            -Detalle $p.DefaultInboundAction `
            -Arreglo $(if ($p.DefaultInboundAction -ne 'Block') { 'NotConfigured hereda Block, pero un valor heredado puede cambiar sin que lo notes' } else { '' })
    }
    $reg = (Get-NetFirewallProfile | Where-Object { $_.LogBlocked -eq $true } | Measure-Object).Count
    Add-Hallazgo -Area 'Firewall' -Asunto 'Registro de bloqueos' -Peso 2 `
        -Estado $(if ($reg -eq 3) { 'BIEN' } else { 'AVISO' }) `
        -Detalle "$reg de 3 perfiles" -Arreglo 'Sin bitacora no hay forensia posible'

    $entrada = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction SilentlyContinue
    $nEnt = ($entrada | Measure-Object).Count
    $nPub = ($entrada | Where-Object { $_.Profile -match 'Public' -or $_.Profile -eq 'Any' } | Measure-Object).Count
    Add-Hallazgo -Area 'Firewall' -Asunto 'Reglas de entrada permitidas' -Peso 2 `
        -Estado $(if ($nEnt -le 60) { 'BIEN' } elseif ($nEnt -le 130) { 'AVISO' } else { 'GRAVE' }) `
        -Detalle "$nEnt en total, $nPub alcanzan el perfil publico" `
        -Arreglo 'Blindar.ps1 -Aplicar -Capas puertos'
} catch { }

# --- Puertos expuestos -----------------------------------------------------
try {
    $exp = Get-NetTCPConnection -State Listen -ErrorAction Stop |
           Where-Object { $_.LocalAddress -in '0.0.0.0','::' }
    $criticos = $exp | Where-Object { $_.LocalPort -in 135,139,445,3389,5985,5986,47001 }
    Add-Hallazgo -Area 'Exposicion' -Asunto 'Puertos criticos escuchando en todas las interfaces' -Peso 3 `
        -Estado $(if (-not $criticos) { 'BIEN' } else { 'GRAVE' }) `
        -Detalle $(if ($criticos) { ($criticos.LocalPort | Sort-Object -Unique) -join ', ' } else { 'ninguno' }) `
        -Arreglo 'SMB (445/139), RPC (135) y WinRM (5985/47001) no pintan nada en un portatil personal'

    $todos = ($exp | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique)
    Add-Hallazgo -Area 'Exposicion' -Asunto 'Total de puertos en 0.0.0.0 o ::' -Estado 'INFO' -Detalle ($todos -join ', ')
} catch { }

# --- Servicios de riesgo ---------------------------------------------------
$riesgo = @{
    'WinRM'          = 'administracion remota'
    'TermService'    = 'escritorio remoto'
    'RemoteRegistry' = 'registro remoto'
    'LanmanServer'   = 'servidor SMB con ADMIN$, C$ e IPC$'
    'SSDPSRV'        = 'descubrimiento UPnP'
    'upnphost'       = 'anfitrion UPnP'
    'FDResPub'       = 'te anuncia en la red'
    'lltdsvc'        = 'te dibuja en el mapa de red'
    'lfsvc'          = 'geolocalizacion'
    'DiagTrack'      = 'telemetria'
    # Apagados el 26/09/2026 con Servicios-Windows.ps1; avisar si una
    # actualizacion de Windows los vuelve a encender.
    'WSearch'        = 'indexador de busqueda (catalogo de tus archivos)'
    'MapsBroker'     = 'mapas sin conexion'
    'TrkWks'         = 'rastreo de enlaces en red'
    'PcaSvc'         = 'asistente de compatibilidad'
}
foreach ($s in $riesgo.Keys) {
    try {
        $o = Get-Service -Name $s -ErrorAction Stop
        $malo = ($o.Status -eq 'Running' -or $o.StartType -eq 'Automatic')
        Add-Hallazgo -Area 'Servicios' -Asunto "$s ($($riesgo[$s]))" -Peso 2 `
            -Estado $(if ($malo) { 'AVISO' } else { 'BIEN' }) `
            -Detalle "$($o.Status) / $($o.StartType)" `
            -Arreglo $(if ($malo) { 'Blindar.ps1 -Aplicar -Capas puertos,sigilo,privacidad' } else { '' })
    } catch { }
}

# --- Cerrojos --------------------------------------------------------------
Write-Titulo 'CERROJOS DEL SISTEMA'
function Get-Reg { param($r,$n) try { return (Get-ItemProperty -Path $r -Name $n -ErrorAction Stop).$n } catch { return $null } }

$pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$uac = Get-Reg $pol 'ConsentPromptBehaviorAdmin'
Add-Hallazgo -Area 'Cerrojos' -Asunto 'UAC: comportamiento del aviso' -Peso 3 `
    -Estado $(if ($uac -in 1,2) { 'BIEN' } elseif ($uac -eq 5) { 'AVISO' } else { 'GRAVE' }) `
    -Detalle $(switch ($uac) { 0 { 'elevar sin preguntar -- muy grave' } 2 { 'consentimiento siempre' } 5 { 'solo para binarios ajenos (por defecto)' } default { "$uac" } }) `
    -Arreglo 'Con 5, los bypass de UAC por auto-elevacion (fodhelper, sdclt) funcionan. Con 2, no.'

Add-Hallazgo -Area 'Cerrojos' -Asunto 'UAC: escritorio seguro' -Peso 2 `
    -Estado $(if ((Get-Reg $pol 'PromptOnSecureDesktop') -eq 1) { 'BIEN' } else { 'AVISO' }) `
    -Detalle $(if ((Get-Reg $pol 'PromptOnSecureDesktop') -eq 1) { 'activo: ningun programa puede falsificar el aviso' } else { 'inactivo' })
Add-Hallazgo -Area 'Cerrojos' -Asunto 'Windows Script Host' -Peso 2 `
    -Estado $(if ((Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled') -eq 0) { 'BIEN' } else { 'AVISO' }) `
    -Detalle $(if ((Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled') -eq 0) { 'desactivado' } else { 'ACTIVO -- los .vbs y .js corren con doble clic' })
$autorun = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun'
Add-Hallazgo -Area 'Cerrojos' -Asunto 'Autorun de unidades' -Peso 2 `
    -Estado $(if ($autorun -eq 255) { 'BIEN' } else { 'AVISO' }) `
    -Detalle $(if ($autorun -eq 255) { 'desactivado en todas las unidades' } elseif ($null -eq $autorun) { 'sin definir: un USB hostil se ejecuta solo' } else { "valor $autorun (255 = todas las unidades)" })
Add-Hallazgo -Area 'Cerrojos' -Asunto 'Extensiones de archivo visibles' -Peso 1 `
    -Estado $(if ((Get-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt') -eq 0) { 'BIEN' } else { 'AVISO' }) `
    -Detalle 'sin esto, factura.pdf.exe se ve como factura.pdf'
$sbl = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging'
Add-Hallazgo -Area 'Cerrojos' -Asunto 'Registro de bloques de script de PowerShell' -Peso 2 `
    -Estado $(if ($sbl -eq 1) { 'BIEN' } else { 'AVISO' }) `
    -Detalle $(if ($sbl -eq 1) { 'activo' } else { 'sin definir: un ataque en PowerShell no dejaria rastro reconstruible' })

# Optimizacion de distribucion: por defecto tu equipo comparte trozos de las
# actualizaciones con desconocidos por Internet, y para eso escucha en 7680.
$dod = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode'
if ($null -eq $dod) { $dod = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' }
Add-Hallazgo -Area 'Exposicion' -Asunto 'Optimizacion de distribucion (P2P de Windows Update)' -Peso 2 `
    -Estado $(if ($dod -in 0,99) { 'BIEN' } else { 'AVISO' }) `
    -Detalle $(switch ($dod) { 0 { 'solo HTTP, sin P2P' } 1 { 'P2P en red local' } 2 { 'P2P en dominio' } 3 { 'P2P CON INTERNET -- comparte con desconocidos' } 99 { 'modo simple' } default { 'sin definir: por defecto reparte por P2P y escucha en el puerto 7680' } }) `
    -Arreglo 'Blindar.ps1 -Aplicar -Capas privacidad'

# --- Credenciales ----------------------------------------------------------
Write-Titulo 'CREDENCIALES Y NUCLEO'
$lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
Add-Hallazgo -Area 'Credenciales' -Asunto 'Proteccion de LSA (RunAsPPL)' -Peso 3 `
    -Estado $(if ((Get-Reg $lsa 'RunAsPPL') -in 1,2) { 'BIEN' } else { 'GRAVE' }) `
    -Detalle "RunAsPPL = $(Get-Reg $lsa 'RunAsPPL')" -Arreglo 'Sin esto, mimikatz lee lsass sin esfuerzo'
Add-Hallazgo -Area 'Credenciales' -Asunto 'Nivel de compatibilidad NTLM' -Peso 2 `
    -Estado $(if ((Get-Reg $lsa 'LmCompatibilityLevel') -ge 5) { 'BIEN' } else { 'AVISO' }) `
    -Detalle "nivel $(Get-Reg $lsa 'LmCompatibilityLevel') (5 = solo NTLMv2)"
Add-Hallazgo -Area 'Credenciales' -Asunto 'WDigest (contrasenas en claro en memoria)' -Peso 3 `
    -Estado $(if ((Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential') -eq 0) { 'BIEN' } else { 'AVISO' })
Add-Hallazgo -Area 'Nucleo' -Asunto 'Lista de controladores vulnerables (anti-BYOVD)' -Peso 3 `
    -Estado $(if ((Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable') -eq 1) { 'BIEN' } else { 'GRAVE' }) `
    -Arreglo 'Es como el ransomware moderno mata al antivirus. Se activa sin HVCI y no toca VMware.'

try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    Add-Hallazgo -Area 'Nucleo' -Asunto 'Integridad de memoria (HVCI)' -Estado 'INFO' `
        -Detalle $(if ($dg.SecurityServicesRunning -contains 2) { 'activa' } else { 'inactiva -- decision consciente: rompe VMware' })
} catch { }

# --- Cuentas ---------------------------------------------------------------
Write-Titulo 'CUENTAS'
try {
    $admins = Get-LocalGroupMember -Group (Get-LocalGroup | Where-Object { $_.SID.Value -eq 'S-1-5-32-544' }).Name -ErrorAction Stop
    Add-Hallazgo -Area 'Cuentas' -Asunto 'Administradores locales' -Peso 2 `
        -Estado $(if ($admins.Count -le 2) { 'BIEN' } else { 'AVISO' }) `
        -Detalle ($admins.Name -join ', ')
    $hab = Get-LocalUser | Where-Object { $_.Enabled }
    Add-Hallazgo -Area 'Cuentas' -Asunto 'Cuentas locales habilitadas' -Estado 'INFO' -Detalle ($hab.Name -join ', ')
    $admLocal = Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' }
    Add-Hallazgo -Area 'Cuentas' -Asunto 'Cuenta Administrador integrada' -Peso 2 `
        -Estado $(if (-not $admLocal.Enabled) { 'BIEN' } else { 'GRAVE' }) `
        -Detalle $(if ($admLocal.Enabled) { 'HABILITADA' } else { 'deshabilitada' })
} catch { }

# --- Persistencia ----------------------------------------------------------
Write-Titulo 'PERSISTENCIA'
try {
    $wmi = Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction Stop
    Add-Hallazgo -Area 'Persistencia' -Asunto 'Suscripciones de eventos WMI' -Peso 3 `
        -Estado $(if (-not $wmi) { 'BIEN' } else { 'AVISO' }) `
        -Detalle $(if ($wmi) { "$($wmi.Count): $($wmi.Name -join ', ')" } else { 'ninguna' }) `
        -Arreglo 'Es persistencia sin fichero, casi invisible. Investiga cada una.'
} catch { Add-Hallazgo -Area 'Persistencia' -Asunto 'Suscripciones WMI' -Estado 'INFO' -Detalle 'requiere administrador' }

foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows',
                 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows')) {
    $v = Get-Reg $k 'AppInit_DLLs'
    if ($v) { Add-Hallazgo -Area 'Persistencia' -Asunto 'AppInit_DLLs' -Estado 'GRAVE' -Peso 3 -Detalle $v `
        -Arreglo 'Se inyecta en todo proceso que cargue user32.dll. No deberia tener nada.' }
}
$wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
foreach ($n in @('Userinit','Shell')) {
    $v = Get-Reg $wl $n
    $esperado = if ($n -eq 'Userinit') { 'userinit.exe' } else { 'explorer.exe' }
    Add-Hallazgo -Area 'Persistencia' -Asunto "Winlogon\$n" -Peso 3 `
        -Estado $(if ($v -and ($v -replace '[\s,]','') -match "(?i)$([regex]::Escape($esperado))$") { 'BIEN' } else { 'AVISO' }) -Detalle $v
}
try {
    $ifeo = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction Stop |
            Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).Debugger }
    Add-Hallazgo -Area 'Persistencia' -Asunto 'Secuestro por depurador (IFEO)' -Peso 3 `
        -Estado $(if (-not $ifeo) { 'BIEN' } else { 'GRAVE' }) `
        -Detalle $(if ($ifeo) { ($ifeo.PSChildName -join ', ') } else { 'ninguno' })
} catch { }
try {
    $t = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }
    Add-Hallazgo -Area 'Persistencia' -Asunto 'Tareas programadas ajenas a Microsoft' -Estado 'INFO' `
        -Detalle "$($t.Count): $(($t.TaskName | Select-Object -First 8) -join ', ')"
} catch { }

# --- Copias de seguridad ---------------------------------------------------
Write-Titulo 'RECUPERACION'
try {
    $sc = Get-CimInstance Win32_ShadowCopy -ErrorAction Stop
    Add-Hallazgo -Area 'Recuperacion' -Asunto 'Instantaneas de volumen' -Peso 3 `
        -Estado $(if ($sc) { 'BIEN' } else { 'GRAVE' }) `
        -Detalle $(if ($sc) { "$($sc.Count) instantaneas" } else { 'NINGUNA -- sin red de seguridad ante ransomware' }) `
        -Arreglo 'Blindar.ps1 -Aplicar -Capas ransomware'
} catch { Add-Hallazgo -Area 'Recuperacion' -Asunto 'Instantaneas de volumen' -Estado 'INFO' -Detalle 'requiere administrador' }

# ===========================================================================
# RESUMEN Y FICHERO
# ===========================================================================

$nota = if ($script:PuntosMax -gt 0) { [math]::Round(100 * $script:Puntos / $script:PuntosMax) } else { 0 }
$graves  = @($script:Hallazgos | Where-Object { $_.Estado -eq 'GRAVE' })
$avisos  = @($script:Hallazgos | Where-Object { $_.Estado -eq 'AVISO' })

Write-Titulo 'RESUMEN'
Write-Host ''
Write-Host ("   Puntuacion: {0} / 100" -f $nota) -ForegroundColor $(if ($nota -ge 85) { 'Green' } elseif ($nota -ge 60) { 'Yellow' } else { 'Red' })
Write-Host ("   Graves: {0}   Avisos: {1}" -f $graves.Count, $avisos.Count) -ForegroundColor Gray
Write-Host ''
if ($graves) {
    Write-Host '   LO GRAVE:' -ForegroundColor Red
    $graves | ForEach-Object { Write-Host ("     - {0}: {1}" -f $_.Asunto, $_.Detalle) -ForegroundColor Red }
    Write-Host ''
}

# Informe en Markdown
$fichero = Join-Path $script:DirInf ("auditoria-$script:Sello.md")
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Auditoria de seguridad")
[void]$md.AppendLine("")
[void]$md.AppendLine("**Equipo:** $env:COMPUTERNAME  ")
[void]$md.AppendLine("**Fecha:** $(Get-Date -Format 'dd/MM/yyyy HH:mm')  ")
[void]$md.AppendLine("**Sistema:** $($cv.ProductName) ($edicion) $($cv.DisplayVersion), compilacion $($cv.CurrentBuild).$($cv.UBR)  ")
[void]$md.AppendLine("**Puntuacion:** $nota / 100 -- $($graves.Count) graves, $($avisos.Count) avisos")
[void]$md.AppendLine("")
foreach ($area in ($script:Hallazgos | Select-Object -ExpandProperty Area -Unique)) {
    [void]$md.AppendLine("## $area")
    [void]$md.AppendLine("")
    foreach ($h in ($script:Hallazgos | Where-Object { $_.Area -eq $area })) {
        $marca = switch ($h.Estado) { 'BIEN' { 'OK' } 'AVISO' { 'AVISO' } 'GRAVE' { 'GRAVE' } default { 'info' } }
        [void]$md.AppendLine("- **[$marca] $($h.Asunto)** -- $($h.Detalle)")
        if ($h.Arreglo) { [void]$md.AppendLine("  - *$($h.Arreglo)*") }
    }
    [void]$md.AppendLine("")
}
Set-Content -Path $fichero -Value $md.ToString() -Encoding UTF8
Write-Host "   Informe: $fichero" -ForegroundColor Cyan

# La puntuacion queda en un fichero suelto para que Todo.ps1 pueda comparar
# el antes y el despues sin tener que analizar el informe.
try {
    @{
        puntuacion = $nota
        graves     = $graves.Count
        avisos     = $avisos.Count
        cuando     = (Get-Date).ToString('o')
        elevado    = $elevado
        informe    = $fichero
    } | ConvertTo-Json | Set-Content -Path (Join-Path $script:DirBase 'ultima-puntuacion.json') -Encoding UTF8
} catch { }

Write-Host ''
