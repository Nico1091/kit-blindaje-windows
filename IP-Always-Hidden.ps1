param([switch]$Revert)
# Firewall lock: LibreWolf (the Browser) cannot talk to any internet address.
# Only to this computer (127.0.0.1, where the Tor tunnel entry listens on port 9050) and to the
# home network. That keeps the IP hidden at all times, even if a setting failed or the browser
# itself tried a direct connection: the tunnel is the only way out. -Revert removes it. Requires administrator.
$nombre = 'Browser: Tor only (IP always hidden)'
$programa = 'C:\Program Files\LibreWolf\librewolf.exe'
Get-NetFirewallRule -DisplayName $nombre -EA 0 | Remove-NetFirewallRule
if ($Revert) { 'Lock removed: LibreWolf can connect directly again.'; exit }
# All of the internet: IPv4 except 10/8, 127/8, 169.254/16, 172.16/12 and 192.168/16; global IPv6 (2000::/3).
$internet = @(
    '0.0.0.0-9.255.255.255', '11.0.0.0-126.255.255.255', '128.0.0.0-169.253.255.255',
    '169.255.0.0-172.15.255.255', '172.32.0.0-192.167.255.255', '192.169.0.0-255.255.255.255',
    '2000::/3'
)
New-NetFirewallRule -DisplayName $nombre -Direction Outbound -Program $programa -Action Block `
    -RemoteAddress $internet -Profile Any -Description 'Security\IP-Always-Hidden.ps1' | Out-Null
$r = Get-NetFirewallRule -DisplayName $nombre
"Lock in place ($($r.Enabled), $($r.Action), $($r.Direction)): $programa only talks to this computer and the home network."
