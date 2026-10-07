param([switch]$Revert)
# Apaga Edge sin desinstalarlo: msedge.exe queda redirigido al Browser (LibreWolf).
# WebView2 NO se toca: lo usan otras aplicaciones. -Revert lo devuelve todo.
$ErrorActionPreference = 'Continue'
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe'
$pol  = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$resp = "$env:USERPROFILE\Security\Backups\edge-disabled"
$pyw  = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
$lanz = "$env:USERPROFILE\Security\Browser\from_edge.pyw"
$pins = "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$escr = @('C:\Users\Public\Desktop\Microsoft Edge.lnk', "$env:USERPROFILE\Desktop\Microsoft Edge.lnk", "$pins\Microsoft Edge.lnk")
New-Item -ItemType Directory -Force $resp | Out-Null

if ($Revert) {
    Remove-Item $ifeo -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty $pol -Name StartupBoostEnabled, BackgroundModeEnabled -ErrorAction SilentlyContinue
    foreach ($f in $escr) { $b = Join-Path $resp (($f -replace '[:\\ ]', '_')); if (Test-Path $b) { Copy-Item $b $f -Force } }
    Write-Host 'Edge devuelto a la normalidad.'
    exit
}

Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not (Test-Path $ifeo)) { New-Item $ifeo -Force | Out-Null }
if ($pyw) { $dest = "`"$pyw`" `"$lanz`"" } else { $dest = '"C:\Program Files\LibreWolf\librewolf.exe"' }
Set-ItemProperty $ifeo -Name Debugger -Value $dest
if (-not (Test-Path $pol)) { New-Item $pol -Force | Out-Null }
Set-ItemProperty $pol -Name StartupBoostEnabled -Value 0 -Type DWord
Set-ItemProperty $pol -Name BackgroundModeEnabled -Value 0 -Type DWord
foreach ($f in $escr) {
    if (Test-Path $f) { Copy-Item $f (Join-Path $resp (($f -replace '[:\\ ]', '_'))) -Force; Remove-Item $f -Force }
}
# Anclar el Browser (LibreWolf con la smiley) a la barra de tareas
Copy-Item "$env:USERPROFILE\Desktop\Browser.lnk" "$pins\Browser.lnk" -Force
$xml = "$env:USERPROFILE\Security\Backups\edge-disabled\barra.xml"
@"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout><taskbar:TaskbarPinList>
      <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\File Explorer.lnk"/>
      <taskbar:DesktopApp DesktopApplicationLinkPath="$pins\Browser.lnk"/>
    </taskbar:TaskbarPinList></defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@ | Set-Content $xml -Encoding UTF8
$exp = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
if (-not (Test-Path $exp)) { New-Item $exp -Force | Out-Null }
Set-ItemProperty $exp -Name StartLayoutFile -Value $xml
Set-ItemProperty $exp -Name LockedStartLayout -Value 1 -Type DWord
Stop-Process -Name explorer -Force; Start-Sleep 6
# Se suelta el candado para que él pueda seguir anclando a su gusto; el anclaje se queda
Remove-ItemProperty $exp -Name StartLayoutFile, LockedStartLayout -ErrorAction SilentlyContinue
Write-Host 'Listo: Edge apagado y redirigido al Browser; Browser anclado.'
