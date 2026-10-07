param([switch]$Revert)
# Browser disguise: smiley icon on the window, smiley code enabled,
# and Start menu search without sending what you type to Bing. -Revert removes it.
$L = 'C:\Program Files\LibreWolf'
$pref = "$L\defaults\pref\browser.js"
$icoDir = "$L\browser\chrome\icons\default"
$exp = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
if ($Revert) {
    Remove-Item $pref, "$icoDir\main-window.ico" -Force -EA 0
    Remove-ItemProperty $exp -Name DisableSearchBoxSuggestions -EA 0
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 1 -Type DWord
    exit
}
Set-Content $pref 'pref("general.config.sandbox_enabled", false);' -Encoding ASCII
New-Item -ItemType Directory -Force $icoDir | Out-Null
Copy-Item "$env:USERPROFILE\Security\Browser\browser.ico" "$icoDir\main-window.ico" -Force
Copy-Item "$env:USERPROFILE\Security\Browser\browser.ico" "$icoDir\default.ico" -Force
if (-not (Test-Path $exp)) { New-Item $exp -Force | Out-Null }
Set-ItemProperty $exp DisableSearchBoxSuggestions 1 -Type DWord
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' BingSearchEnabled 0 -Type DWord
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' CortanaConsent 0 -Type DWord
