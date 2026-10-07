<#
.SYNOPSIS
    Apaga la IA de Windows, la telemetria restante y los extras de Office,
    dejando Word intacto.

.DESCRIPTION
    NO se toca (Word depende de ello): ClickToRunSvc, la tarea
    "Office Automatic Updates 2.0" (parches de seguridad de Word) y
    "Office ClickToRun Service Monitor".

    Lo que se apaga queda respaldado en Backups\microsoft-state.json y
    vuelve con -Revert. Lo desinstalado (Outlook nuevo, Office Actions
    Server, Office Push Notification, complemento de Teams) no vuelve solo:
    se reinstala desde la Tienda si algun dia hace falta.

.EXAMPLE
    .\Disable-Microsoft.ps1            Aplica.
    .\Disable-Microsoft.ps1 -Revert  Devuelve lo apagado.
#>
param([switch]$Revert)

$resp = Join-Path $PSScriptRoot 'Backups\microsoft-state.json'

# Servicios que se deshabilitan
$Servicios = @(
    'WSAIFabricSvc',   # Host de componentes de IA de Windows
    'whesvc',          # Estado y experiencias optimizadas (telemetria)
    'InventorySvc'     # Inventario de programas que se reporta a Microsoft
)
# Tareas de Office que se apagan (las de actualizacion y el monitor se quedan)
$TareasOffice = @(
    'Office Actions Server',
    'Office Background Push Maintenance',
    'Office Feature Updates',
    'Office Feature Updates Logon',
    'Office Performance Monitor',
    'Office Serviceability Manager',
    'Office Startup Maintenance'
)
# Apps de la Tienda que se desinstalan
$Apps = @(
    'Microsoft.OutlookForWindows',
    'Microsoft.Office.ActionsServer',
    'Microsoft.OfficePushNotificationUtility'
)
# Registro: ruta, nombre, valor
$Claves = @(
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableClickToDo', 1),              # Click to Do (IA sobre la pantalla)
    @('HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableClickToDo', 1),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsResumeAllowed', 0),  # continuar desde el telefono
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement', 'ScoobeSystemSettingEnabled', 0), # "termina de configurar tu PC"
    @('HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry', 'sendtelemetry', 3),     # Office: sin datos de diagnostico
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common\privacy', 'controllerconnectedservicesenabled', 2)   # Office: sin experiencias conectadas opcionales
)

# --- Elevarse solo -------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',"`"$PSCommandPath`"")
    if ($Revert) { $a += '-Revert' }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    return
}

# --- Revert ------------------------------------------------------------
if ($Revert) {
    if (-not (Test-Path $resp)) { 'No hay nada que revertir: el script nunca se aplico.'; return }
    $e = Get-Content $resp -Raw | ConvertFrom-Json
    foreach ($s in $e.servicios) {
        Set-Service $s.nombre -StartupType $s.inicio -EA 0
        if ($s.estado -eq 'Running') { Start-Service $s.nombre -EA 0 }
        "servicio $($s.nombre) -> $($s.inicio)"
    }
    foreach ($t in $e.tareas) {
        if ($t.estado -ne 'Disabled') { Enable-ScheduledTask -TaskPath $t.ruta -TaskName $t.nombre -EA 0 | Out-Null; "tarea $($t.nombre) activa" }
    }
    foreach ($c in $e.claves) {
        if ($null -eq $c.antes) { Remove-ItemProperty $c.ruta -Name $c.nombre -EA 0 }
        else { Set-ItemProperty $c.ruta -Name $c.nombre -Value $c.antes }
        "registro $($c.nombre) devuelto"
    }
    Rename-Item $resp ("microsoft-state-reverted-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
    'Listo: devuelto. Lo desinstalado se reinstala desde la Tienda.'
    return
}

# --- Backup ------------------------------------------------------------
if (-not (Test-Path $resp)) {
    [ordered]@{
        fecha     = (Get-Date).ToString('s')
        servicios = @($Servicios | % { $s = Get-Service $_ -EA 0; if ($s) { [ordered]@{ nombre = $_; inicio = [string]$s.StartType; estado = [string]$s.Status } } })
        tareas    = @(Get-ScheduledTask -TaskPath '\Microsoft\Office\' -EA 0 | ? TaskName -in $TareasOffice | % { [ordered]@{ ruta = $_.TaskPath; nombre = $_.TaskName; estado = [string]$_.State } })
        claves    = @($Claves | % { $v = $null; try { $v = (Get-ItemProperty $_[0] -Name $_[1] -EA Stop).($_[1]) } catch {}; [ordered]@{ ruta = $_[0]; nombre = $_[1]; antes = $v } })
    } | ConvertTo-Json -Depth 4 | Set-Content $resp -Encoding UTF8
    "Backup guardado en $resp"
}

# --- 1 Servicios ---------------------------------------------------------
foreach ($n in $Servicios) {
    if (-not (Get-Service $n -EA 0)) { "no existe: $n"; continue }
    Stop-Service $n -Force -EA SilentlyContinue
    try { Set-Service $n -StartupType Disabled -EA Stop }
    catch { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$n" -Name Start -Value 4 -EA SilentlyContinue }
}

# --- 2 Tareas de Office --------------------------------------------------
Get-ScheduledTask -TaskPath '\Microsoft\Office\' -EA 0 | ? TaskName -in $TareasOffice | Disable-ScheduledTask -EA 0 | Out-Null

# --- 3 Registro ----------------------------------------------------------
foreach ($c in $Claves) {
    if (-not (Test-Path $c[0])) { New-Item $c[0] -Force | Out-Null }
    New-ItemProperty $c[0] -Name $c[1] -Value $c[2] -PropertyType DWord -Force | Out-Null
}

# --- 4 Apps de la Tienda -------------------------------------------------
foreach ($a in $Apps) {
    Get-AppxPackage $a -EA 0 | Remove-AppxPackage -EA SilentlyContinue
    Get-AppxProvisionedPackage -Online -EA 0 | ? DisplayName -eq $a | Remove-AppxProvisionedPackage -Online -EA SilentlyContinue | Out-Null
}

# --- 5 Complemento de Teams para Office (solo sirve al Outlook clasico) ---
Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA 0 |
    ? DisplayName -like 'Microsoft Teams Meeting Add-in*' | % {
        if ($_.PSChildName -match '^\{[0-9A-F-]+\}$') { Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait }
    }

# --- 6 Procesos que quedaron vivos --------------------------------------
Stop-Process -Name AppActions, CrossDeviceResume, UserOOBEBroker -Force -EA SilentlyContinue

# --- Comprobacion --------------------------------------------------------
Start-Sleep 3
''
'===== RESULTADO ====='
foreach ($n in $Servicios) { $s = Get-Service $n -EA 0; '{0,-16} {1,-9} {2}' -f $n, $s.StartType, $s.Status }
'Tareas de Office apagadas: ' + @(Get-ScheduledTask -TaskPath '\Microsoft\Office\' -EA 0 | ? { $_.TaskName -in $TareasOffice -and $_.State -eq 'Disabled' }).Count + ' de ' + $TareasOffice.Count
foreach ($a in $Apps) { '{0,-42} {1}' -f $a, $(if (Get-AppxPackage $a -EA 0) { 'SIGUE' } else { 'quitada' }) }
'Complemento de Teams: ' + $(if (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA 0 | ? DisplayName -like 'Microsoft Teams Meeting Add-in*') { 'SIGUE' } else { 'quitado' })
''
'--- Word (debe seguir todo bien) ---'
'ClickToRunSvc: ' + (Get-Service ClickToRunSvc).Status
'WINWORD.EXE:   ' + (Test-Path 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE')
'Actualizaciones de Office: ' + (Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0' -EA 0).State
''
'Listo. Puede cerrar esta ventana.'
