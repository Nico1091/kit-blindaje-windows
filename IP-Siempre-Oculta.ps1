param([switch]$Revertir)
# Candado del cortafuegos: LibreWolf (el Buscador) no puede hablar con ninguna direccion de internet.
# Solo con este equipo (127.0.0.1, donde esta la entrada al tunel de Tor en el puerto 9050) y con la
# red de la casa. Asi la IP queda oculta siempre, aunque fallara un ajuste o el propio navegador
# intentara una salida directa: el tunel es la unica puerta. -Revertir lo quita. Exige administrador.
$nombre = 'Buscador: solo por Tor (IP siempre oculta)'
$programa = 'C:\Program Files\LibreWolf\librewolf.exe'
Get-NetFirewallRule -DisplayName $nombre -EA 0 | Remove-NetFirewallRule
if ($Revertir) { 'Candado quitado: LibreWolf vuelve a poder salir directo.'; exit }
# Todo internet: IPv4 salvo 10/8, 127/8, 169.254/16, 172.16/12 y 192.168/16; IPv6 global (2000::/3).
$internet = @(
    '0.0.0.0-9.255.255.255', '11.0.0.0-126.255.255.255', '128.0.0.0-169.253.255.255',
    '169.255.0.0-172.15.255.255', '172.32.0.0-192.167.255.255', '192.169.0.0-255.255.255.255',
    '2000::/3'
)
New-NetFirewallRule -DisplayName $nombre -Direction Outbound -Program $programa -Action Block `
    -RemoteAddress $internet -Profile Any -Description 'Seguridad\IP-Siempre-Oculta.ps1' | Out-Null
$r = Get-NetFirewallRule -DisplayName $nombre
"Candado puesto ($($r.Enabled), $($r.Action), $($r.Direction)): $programa solo habla con este equipo y la red de la casa."
