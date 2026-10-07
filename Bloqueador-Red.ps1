param([switch]$Revertir, [string]$Lista = '')
# Bloqueador de red: anuncios y malware cortados en el DNS local (Unbound) para todo el equipo.
# Sin dominios de Microsoft (riesgo de bloqueo de Windows) ni los sitios guardados del Buscador.
$U = 'C:\Program Files\Unbound'
$conf = "$U\service.conf"
$linea = 'include: "C:/Program Files/Unbound/bloqueo.conf"'
$resp = "$env:USERPROFILE\Seguridad\Respaldos\service.conf.antes-bloqueo"

if ($Revertir) {
    (Get-Content $conf) | Where-Object { $_ -ne $linea } | Set-Content $conf -Encoding ASCII
    Remove-Item "$U\bloqueo.conf" -Force -EA 0
    Restart-Service unbound
    Write-Host 'Bloqueador quitado.'
    exit
}
if (-not (Test-Path $resp)) { Copy-Item $conf $resp }
Copy-Item $Lista "$U\bloqueo.conf" -Force
if (-not (Select-String -Path $conf -SimpleMatch $linea -Quiet)) { Add-Content $conf $linea -Encoding ASCII }
& "$U\unbound-checkconf.exe" $conf
if ($LASTEXITCODE -ne 0) {
    Copy-Item $resp $conf -Force
    Remove-Item "$U\bloqueo.conf" -Force -EA 0
    Write-Host 'Configuracion invalida: se dejo como estaba.'
    exit 1
}
Restart-Service unbound
Write-Host 'Bloqueador activo.'
