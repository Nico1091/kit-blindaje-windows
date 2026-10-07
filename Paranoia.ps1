param([switch]$Revert)
# Paranoia: closes what was still leaving this computer toward Microsoft, toward other computers on
# the internet or toward the local network. Does not touch base telemetry or Microsoft domains
# (risk of Windows being locked). Single backup of the original state; -Revert restores it.
$resp = "$env:USERPROFILE\Security\Backups\paranoia-state.json"

$cambios = @(
    # Activity history and cloud clipboard
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableActivityFeed', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'PublishUserActivities', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'UploadUserActivities', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'AllowCrossDeviceClipboard', 0),
    # Delivery Optimization: do not upload updates to unknown computers on the internet
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization', 'DODownloadMode', 0),
    # Find my device (sends the location to Microsoft)
    @('HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice', 'AllowFindMyDevice', 0),
    # Recall (screenshots analyzed by AI) and Copilot
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1),
    @('HKCU:\Software\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1),
    @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
    # Online speech recognition and language list exposed to web pages
    @('HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy', 'HasAccepted', 0),
    @('HKCU:\Control Panel\International\User Profile', 'HttpAcceptLanguageOptOut', 1),
    # Local network: the computer stops announcing its name and asking neighbors for names
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient', 'EnableMulticast', 0),
    @('HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters', 'EnableMDNS', 0),
    # No proxy auto-discovery (WPAD): a neighbor cannot offer itself as a proxy
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp', 'DisableWpad', 1)
)
# NetBIOS off on every adapter
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' | ForEach-Object {
    $cambios += , @($_.PSPath, 'NetbiosOptions', 2)
}

if ($Revert) {
    if (-not (Test-Path $resp)) { Write-Host 'There is no backup.'; exit 1 }
    $estado = Get-Content $resp -Raw | ConvertFrom-Json
    foreach ($e in $estado.registro) {
        if ($e.existia) { Set-ItemProperty $e.ruta $e.nombre ([int]$e.valor) -Type DWord }
        else { Remove-ItemProperty $e.ruta -Name $e.nombre -EA 0 }
    }
    Set-MpPreference -SubmitSamplesConsent ([int]$estado.muestrasDefender)
    Write-Host 'Paranoia reverted (some network changes come back after a restart).'
    exit
}

# Backup: only what was not recorded yet is recorded, so the original state is never overwritten
$estado = if (Test-Path $resp) { Get-Content $resp -Raw | ConvertFrom-Json } else { $null }
$registro = @(if ($estado) { $estado.registro })
foreach ($c in $cambios) {
    if ($registro | Where-Object { $_.ruta -eq $c[0] -and $_.nombre -eq $c[1] }) { continue }
    $v = (Get-ItemProperty $c[0] -Name $c[1] -EA 0).($c[1])
    $registro += [pscustomobject]@{ ruta = $c[0]; nombre = $c[1]; existia = ($null -ne $v); valor = $v }
}
$muestras = if ($estado) { $estado.muestrasDefender } else { (Get-MpPreference).SubmitSamplesConsent }
[pscustomobject]@{ registro = $registro; muestrasDefender = $muestras } |
    ConvertTo-Json -Depth 4 | Set-Content $resp -Encoding UTF8

foreach ($c in $cambios) {
    if (-not (Test-Path $c[0])) { New-Item $c[0] -Force | Out-Null }
    Set-ItemProperty $c[0] $c[1] $c[2] -Type DWord
}
# Defender: do not upload the user's files to Microsoft without asking (protection stays the same)
Set-MpPreference -SubmitSamplesConsent 2
# IPv6 with temporary, random addresses (they do not identify the computer across networks)
netsh interface ipv6 set privacy state=enabled | Out-Null
netsh interface ipv6 set global randomizeidentifiers=enabled | Out-Null
ipconfig /flushdns | Out-Null
Write-Host ("Paranoia applied: {0} settings. LLMNR, mDNS and NetBIOS finish turning off after a restart." -f ($cambios.Count + 3))
