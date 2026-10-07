<#
.SYNOPSIS
    Turns off Windows AI, the remaining telemetry and the Office extras,
    leaving Word intact.

.DESCRIPTION
    NOT touched (Word depends on them): ClickToRunSvc, the
    "Office Automatic Updates 2.0" task (Word security patches) and
    "Office ClickToRun Service Monitor".

    What is turned off is backed up to Backups\microsoft-state.json and
    comes back with -Revert. What is uninstalled (new Outlook, Office Actions
    Server, Office Push Notification, Teams add-in) does not come back by
    itself: reinstall it from the Store if you ever need it.

.EXAMPLE
    .\Disable-Microsoft.ps1            Applies.
    .\Disable-Microsoft.ps1 -Revert    Restores what was turned off.
#>
param([switch]$Revert)

$resp = Join-Path $PSScriptRoot 'Backups\microsoft-state.json'

# Services that are disabled
$Servicios = @(
    'WSAIFabricSvc',   # Windows AI components host
    'whesvc',          # Health and optimized experiences (telemetry)
    'InventorySvc'     # Program inventory reported to Microsoft
)
# Office tasks that are turned off (the update tasks and the monitor stay)
$TareasOffice = @(
    'Office Actions Server',
    'Office Background Push Maintenance',
    'Office Feature Updates',
    'Office Feature Updates Logon',
    'Office Performance Monitor',
    'Office Serviceability Manager',
    'Office Startup Maintenance'
)
# Store apps that are uninstalled
$Apps = @(
    'Microsoft.OutlookForWindows',
    'Microsoft.Office.ActionsServer',
    'Microsoft.OfficePushNotificationUtility'
)
# Registry: path, name, value
$Claves = @(
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableClickToDo', 1),              # Click to Do (AI over the screen)
    @('HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableClickToDo', 1),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsResumeAllowed', 0),  # resume from the phone
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement', 'ScoobeSystemSettingEnabled', 0), # "finish setting up your PC"
    @('HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry', 'sendtelemetry', 3),     # Office: no diagnostic data
    @('HKCU:\Software\Policies\Microsoft\office\16.0\common\privacy', 'controllerconnectedservicesenabled', 2)   # Office: no optional connected experiences
)

# --- Self-elevate --------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',"`"$PSCommandPath`"")
    if ($Revert) { $a += '-Revert' }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    return
}

# --- Revert ------------------------------------------------------------
if ($Revert) {
    if (-not (Test-Path $resp)) { 'Nothing to revert: the script was never applied.'; return }
    $e = Get-Content $resp -Raw | ConvertFrom-Json
    foreach ($s in $e.servicios) {
        Set-Service $s.nombre -StartupType $s.inicio -EA 0
        if ($s.estado -eq 'Running') { Start-Service $s.nombre -EA 0 }
        "service $($s.nombre) -> $($s.inicio)"
    }
    foreach ($t in $e.tareas) {
        if ($t.estado -ne 'Disabled') { Enable-ScheduledTask -TaskPath $t.ruta -TaskName $t.nombre -EA 0 | Out-Null; "task $($t.nombre) enabled" }
    }
    foreach ($c in $e.claves) {
        if ($null -eq $c.antes) { Remove-ItemProperty $c.ruta -Name $c.nombre -EA 0 }
        else { Set-ItemProperty $c.ruta -Name $c.nombre -Value $c.antes }
        "registry $($c.nombre) restored"
    }
    Rename-Item $resp ("microsoft-state-reverted-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
    'Done: restored. What was uninstalled can be reinstalled from the Store.'
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
    "Backup saved to $resp"
}

# --- 1 Services ----------------------------------------------------------
foreach ($n in $Servicios) {
    if (-not (Get-Service $n -EA 0)) { "does not exist: $n"; continue }
    Stop-Service $n -Force -EA SilentlyContinue
    try { Set-Service $n -StartupType Disabled -EA Stop }
    catch { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$n" -Name Start -Value 4 -EA SilentlyContinue }
}

# --- 2 Office tasks ------------------------------------------------------
Get-ScheduledTask -TaskPath '\Microsoft\Office\' -EA 0 | ? TaskName -in $TareasOffice | Disable-ScheduledTask -EA 0 | Out-Null

# --- 3 Registry ----------------------------------------------------------
foreach ($c in $Claves) {
    if (-not (Test-Path $c[0])) { New-Item $c[0] -Force | Out-Null }
    New-ItemProperty $c[0] -Name $c[1] -Value $c[2] -PropertyType DWord -Force | Out-Null
}

# --- 4 Store apps --------------------------------------------------------
foreach ($a in $Apps) {
    Get-AppxPackage $a -EA 0 | Remove-AppxPackage -EA SilentlyContinue
    Get-AppxProvisionedPackage -Online -EA 0 | ? DisplayName -eq $a | Remove-AppxProvisionedPackage -Online -EA SilentlyContinue | Out-Null
}

# --- 5 Teams add-in for Office (only serves classic Outlook) -------------
Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA 0 |
    ? DisplayName -like 'Microsoft Teams Meeting Add-in*' | % {
        if ($_.PSChildName -match '^\{[0-9A-F-]+\}$') { Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait }
    }

# --- 6 Processes left running --------------------------------------------
Stop-Process -Name AppActions, CrossDeviceResume, UserOOBEBroker -Force -EA SilentlyContinue

# --- Check ---------------------------------------------------------------
Start-Sleep 3
''
'===== RESULT ====='
foreach ($n in $Servicios) { $s = Get-Service $n -EA 0; '{0,-16} {1,-9} {2}' -f $n, $s.StartType, $s.Status }
'Office tasks turned off: ' + @(Get-ScheduledTask -TaskPath '\Microsoft\Office\' -EA 0 | ? { $_.TaskName -in $TareasOffice -and $_.State -eq 'Disabled' }).Count + ' of ' + $TareasOffice.Count
foreach ($a in $Apps) { '{0,-42} {1}' -f $a, $(if (Get-AppxPackage $a -EA 0) { 'STILL THERE' } else { 'removed' }) }
'Teams add-in: ' + $(if (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA 0 | ? DisplayName -like 'Microsoft Teams Meeting Add-in*') { 'STILL THERE' } else { 'removed' })
''
'--- Word (everything must still work) ---'
'ClickToRunSvc: ' + (Get-Service ClickToRunSvc).Status
'WINWORD.EXE:   ' + (Test-Path 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE')
'Office updates: ' + (Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0' -EA 0).State
''
'Done. You can close this window.'
