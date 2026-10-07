param([switch]$Revertir)
# Disfraz del Buscador: icono de carita en la ventana, codigo de la carita habilitado,
# y la busqueda del menu Inicio sin enviar lo escrito a Bing. -Revertir lo quita.
$L = 'C:\Program Files\LibreWolf'
$pref = "$L\defaults\pref\buscador.js"
$icoDir = "$L\browser\chrome\icons\default"
$exp = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
if ($Revertir) {
    Remove-Item $pref, "$icoDir\main-window.ico" -Force -EA 0
    Remove-ItemProperty $exp -Name DisableSearchBoxSuggestions -EA 0
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 1 -Type DWord
    exit
}
Set-Content $pref 'pref("general.config.sandbox_enabled", false);' -Encoding ASCII
New-Item -ItemType Directory -Force $icoDir | Out-Null
Copy-Item "$env:USERPROFILE\Seguridad\Buscador\buscador.ico" "$icoDir\main-window.ico" -Force
Copy-Item "$env:USERPROFILE\Seguridad\Buscador\buscador.ico" "$icoDir\default.ico" -Force
if (-not (Test-Path $exp)) { New-Item $exp -Force | Out-Null }
Set-ItemProperty $exp DisableSearchBoxSuggestions 1 -Type DWord
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 0 -Type DWord
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' CortanaConsent 0 -Type DWord
