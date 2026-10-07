param([switch]$NoPause)
# Actualiza el Browser (LibreWolf) a la ultima version oficial y vuelve a poner lo propio que vive en
# su carpeta, porque el instalador puede borrarlo: browser.js (sin el dejan de funcionar la ruta por
# pagina de la IP oculta y la smiley), policies.json (Mojeek, bloqueo de Dark Reader) y los iconos.
# El instalador se baja de librewolf.net y solo se ejecuta si su firma digital es valida y de OSSign.
# Exige administrador y el Browser cerrado. Mantener el navegador al dia es la primera defensa: casi
# todas las desanonimizaciones conocidas explotaron navegadores sin actualizar.
$ErrorActionPreference = 'Stop'
$L = 'C:\Program Files\LibreWolf'
$icoDir = "$L\browser\chrome\icons\default"
$resp = "$env:USERPROFILE\Security\Backups\librewolf-propio"
function Fin($texto) {
    Write-Host $texto
    if (-not $NoPause) { Read-Host 'Pulsa Enter para cerrar' | Out-Null }
    exit
}
if (Get-Process librewolf -EA 0) { Fin 'Cierra el Browser y vuelve a intentarlo.' }
$antes = (Get-Item "$L\librewolf.exe").VersionInfo.ProductVersion
$pagina = (Invoke-WebRequest 'https://librewolf.net/installation/windows/' -UseBasicParsing).Content
$m = [regex]::Match($pagina, 'librewolf-([0-9][0-9.]*-[0-9]+)-windows-x86_64-setup\.exe')
if (-not $m.Success) { Fin 'No encontre la version en librewolf.net: no cambio nada.' }
$ver = $m.Groups[1].Value
if ([version]($ver.Split('-')[0]) -le [version]$antes) { Fin "El Browser ya esta al dia ($antes)." }
$exe = Join-Path $env:TEMP "librewolf-$ver-setup.exe"
Invoke-WebRequest "https://dl.librewolf.net/librewolf/$ver/librewolf-$ver-windows-x86_64-setup.exe" -OutFile $exe -UseBasicParsing
$firma = Get-AuthenticodeSignature $exe
if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'Scheibling|OSSign') {
    Remove-Item $exe -Force
    Fin "Firma no valida ($($firma.Status); $($firma.SignerCertificate.Subject)): no instalo nada."
}
New-Item -ItemType Directory -Force $resp | Out-Null
Copy-Item "$L\distribution\policies.json" "$resp\policies.json" -Force
Start-Process $exe -ArgumentList '/S' -Wait
Remove-Item $exe -Force
New-Item -ItemType Directory -Force "$L\defaults\pref", "$L\distribution", $icoDir | Out-Null
Set-Content "$L\defaults\pref\browser.js" 'pref("general.config.sandbox_enabled", false);' -Encoding ASCII
Copy-Item "$resp\policies.json" "$L\distribution\policies.json" -Force
Copy-Item "$env:USERPROFILE\Security\Browser\browser.ico" "$icoDir\main-window.ico" -Force
Copy-Item "$env:USERPROFILE\Security\Browser\browser.ico" "$icoDir\default.ico" -Force
$despues = (Get-Item "$L\librewolf.exe").VersionInfo.ProductVersion
Fin "Browser actualizado: $antes -> $despues. Firma de OSSign valida; browser.js, policies.json e iconos repuestos."
