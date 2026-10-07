param([switch]$NoPause)
# Updates the Browser (LibreWolf) to the latest official release and puts back the kit's own files in
# its folder, because the installer may delete them: browser.js (without it the per-page routing of the
# hidden IP and the smiley stop working), policies.json (Mojeek, Dark Reader block) and the icons.
# The installer is downloaded from librewolf.net and only runs if its digital signature is valid and from OSSign.
# Requires administrator and the Browser closed. Keeping the browser up to date is the first defense:
# almost every known deanonymization exploited an outdated browser.
$ErrorActionPreference = 'Stop'
$L = 'C:\Program Files\LibreWolf'
$icoDir = "$L\browser\chrome\icons\default"
$resp = "$env:USERPROFILE\Security\Backups\librewolf-own"
function Fin($texto) {
    Write-Host $texto
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit
}
if (Get-Process librewolf -EA 0) { Fin 'Close the Browser and try again.' }
$antes = (Get-Item "$L\librewolf.exe").VersionInfo.ProductVersion
$pagina = (Invoke-WebRequest 'https://librewolf.net/installation/windows/' -UseBasicParsing).Content
$m = [regex]::Match($pagina, 'librewolf-([0-9][0-9.]*-[0-9]+)-windows-x86_64-setup\.exe')
if (-not $m.Success) { Fin 'Could not find the version on librewolf.net: nothing was changed.' }
$ver = $m.Groups[1].Value
if ([version]($ver.Split('-')[0]) -le [version]$antes) { Fin "The Browser is already up to date ($antes)." }
$exe = Join-Path $env:TEMP "librewolf-$ver-setup.exe"
Invoke-WebRequest "https://dl.librewolf.net/librewolf/$ver/librewolf-$ver-windows-x86_64-setup.exe" -OutFile $exe -UseBasicParsing
$firma = Get-AuthenticodeSignature $exe
if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'Scheibling|OSSign') {
    Remove-Item $exe -Force
    Fin "Invalid signature ($($firma.Status); $($firma.SignerCertificate.Subject)): nothing was installed."
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
Fin "Browser updated: $antes -> $despues. Valid OSSign signature; browser.js, policies.json and icons restored."
