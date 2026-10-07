param([switch]$Revert, [string]$List = '')
# Network blocker: ads and malware cut off at the local DNS (Unbound) for the whole computer.
# No Microsoft domains (risk of Windows being locked) and none of the sites the Browser keeps signed in.
$U = 'C:\Program Files\Unbound'
$conf = "$U\service.conf"
$linea = 'include: "C:/Program Files/Unbound/block.conf"'
$resp = "$env:USERPROFILE\Security\Backups\service.conf.before-block"

if ($Revert) {
    (Get-Content $conf) | Where-Object { $_ -ne $linea } | Set-Content $conf -Encoding ASCII
    Remove-Item "$U\block.conf" -Force -EA 0
    Restart-Service unbound
    Write-Host 'Blocker removed.'
    exit
}
if (-not (Test-Path $resp)) { Copy-Item $conf $resp }
Copy-Item $List "$U\block.conf" -Force
if (-not (Select-String -Path $conf -SimpleMatch $linea -Quiet)) { Add-Content $conf $linea -Encoding ASCII }
& "$U\unbound-checkconf.exe" $conf
if ($LASTEXITCODE -ne 0) {
    Copy-Item $resp $conf -Force
    Remove-Item "$U\block.conf" -Force -EA 0
    Write-Host 'Invalid configuration: it was left as it was.'
    exit 1
}
Restart-Service unbound
Write-Host 'Blocker active.'
