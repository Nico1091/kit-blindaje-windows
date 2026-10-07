param([switch]$Revertir)
# Paranoia: lo que aun salia de este equipo hacia Microsoft, hacia otros equipos de internet
# o hacia la red local, cerrado. No toca la telemetria base ni dominios de Microsoft
# (riesgo de bloqueo de Windows). Respaldo unico del estado original; -Revertir lo devuelve.
$resp = "$env:USERPROFILE\Seguridad\Respaldos\paranoia-estado.json"

$cambios = @(
    # Historial de actividad y portapapeles en la nube
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableActivityFeed', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'PublishUserActivities', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'UploadUserActivities', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'AllowCrossDeviceClipboard', 0),
    # Optimizacion de distribucion: no subir actualizaciones a equipos desconocidos de internet
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization', 'DODownloadMode', 0),
    # Buscar mi dispositivo (envia la ubicacion a Microsoft)
    @('HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice', 'AllowFindMyDevice', 0),
    # Recall (capturas analizadas por IA) y Copilot
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1),
    @('HKCU:\Software\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1),
    @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
    # Reconocimiento de voz en linea y lista de idiomas expuesta a las paginas
    @('HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy', 'HasAccepted', 0),
    @('HKCU:\Control Panel\International\User Profile', 'HttpAcceptLanguageOptOut', 1),
    # Red local: el equipo deja de anunciar su nombre y de preguntar nombres a los vecinos
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient', 'EnableMulticast', 0),
    @('HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters', 'EnableMDNS', 0),
    # Sin autodescubrimiento de proxy (WPAD): un vecino no puede ofrecerse como proxy
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp', 'DisableWpad', 1)
)
# NetBIOS apagado en cada adaptador
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' | ForEach-Object {
    $cambios += , @($_.PSPath, 'NetbiosOptions', 2)
}

if ($Revertir) {
    if (-not (Test-Path $resp)) { Write-Host 'No hay respaldo.'; exit 1 }
    $estado = Get-Content $resp -Raw | ConvertFrom-Json
    foreach ($e in $estado.registro) {
        if ($e.existia) { Set-ItemProperty $e.ruta $e.nombre ([int]$e.valor) -Type DWord }
        else { Remove-ItemProperty $e.ruta -Name $e.nombre -EA 0 }
    }
    Set-MpPreference -SubmitSamplesConsent ([int]$estado.muestrasDefender)
    Write-Host 'Paranoia revertida (algunos cambios de red vuelven al reiniciar).'
    exit
}

# Respaldo: solo se anota lo que aun no estaba anotado, para no pisar el estado original
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
# Defender: no subir archivos suyos a Microsoft sin preguntar (sigue protegiendo igual)
Set-MpPreference -SubmitSamplesConsent 2
# IPv6 con direcciones temporales y aleatorias (no delatan el equipo entre redes)
netsh interface ipv6 set privacy state=enabled | Out-Null
netsh interface ipv6 set global randomizeidentifiers=enabled | Out-Null
ipconfig /flushdns | Out-Null
Write-Host ("Paranoia aplicada: {0} ajustes. LLMNR, mDNS y NetBIOS terminan de apagarse al reiniciar." -f ($cambios.Count + 3))
