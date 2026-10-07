$rutas = @{}
function Add-Ruta([string]$p, [string]$origen) {
  if (-not $p) { return }
  $p = $p.Trim()
  if ($p -match '^"([^"]+)"') { $p = $matches[1] } elseif ($p -match '^(.+?\.(exe|sys|dll))\b') { $p = $matches[1] }
  if ($p.StartsWith('\??\')) { $p = $p.Substring(4) }
  if ($p -like '\SystemRoot\*') { $p = $env:windir + $p.Substring(11) }
  if ($p -like 'System32\*') { $p = Join-Path $env:windir $p }
  $p = [Environment]::ExpandEnvironmentVariables($p)
  if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { if (-not $rutas.ContainsKey($p)) { $rutas[$p] = $origen } }
}
Get-CimInstance Win32_Process | ForEach-Object { Add-Ruta $_.ExecutablePath ('proceso ' + $_.Name) }
Get-CimInstance Win32_Service | ForEach-Object { Add-Ruta $_.PathName ('servicio ' + $_.Name + ' (' + $_.State + ')') }
Get-CimInstance Win32_SystemDriver | Where-Object State -eq 'Running' | ForEach-Object { Add-Ruta $_.PathName ('driver ' + $_.Name) }
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
  $i = Get-ItemProperty $k -EA SilentlyContinue
  if ($i) { $i.PSObject.Properties | Where-Object Name -notlike 'PS*' | ForEach-Object { Add-Ruta ([string]$_.Value) ('arranque ' + $_.Name) } }
}
"archivos revisados: $($rutas.Count)"
$sistema = 'svchost','lsass','csrss','winlogon','services','smss','wininit','explorer','spoolsv','dwm','taskhostw','conhost','rundll32','dllhost','lsaiso','fontdrvhost','sihost','ctfmon','searchindexer','msmpeng'
$win = $env:windir
$raros = foreach ($p in $rutas.Keys) {
  $s = Get-AuthenticodeSignature -LiteralPath $p -EA SilentlyContinue
  $firmante = if ($s.SignerCertificate) { (($s.SignerCertificate.Subject -split ',')[0]) -replace 'CN=','' } else { '' }
  $nombre = [IO.Path]::GetFileNameWithoutExtension($p).ToLower()
  $motivo = @()
  if ($s.Status -ne 'Valid') { $motivo += "firma: $($s.Status)" }
  if ($p -like '*\AppData\Local\Temp\*' -or $p -like '*\Downloads\*' -or $p -like 'C:\Users\Public\*' -or $p -like '*\Windows\Temp\*') { $motivo += 'corre desde carpeta temporal o publica' }
  if ($sistema -contains $nombre -and -not $p.StartsWith($win, 'OrdinalIgnoreCase')) { $motivo += 'SE HACE PASAR POR WINDOWS' }
  if ($nombre -match '^(scvhost|svhost|svch0st|lsas|lssas|csrs|explorer32|winlog0n|rundl32)$') { $motivo += 'NOMBRE IMITADOR' }
  if ($s.Status -eq 'Valid' -and $p.StartsWith("$win\System32\", 'OrdinalIgnoreCase') -and $p -notlike '*\DriverStore\*' -and $p -notlike '*\drivers\*' -and $firmante -and $firmante -notmatch 'Microsoft') { $motivo += "tercero dentro de System32: $firmante" }
  if ($motivo) { [pscustomobject]@{ Ruta = $p; Origen = $rutas[$p]; Firmante = $firmante; Motivo = ($motivo -join '; ') } }
}
"hallazgos: $(@($raros).Count)"
$raros | Sort-Object Motivo, Ruta | ForEach-Object { "- [{0}] {1}`n    origen: {2} | firmante: {3}" -f $_.Motivo, $_.Ruta, $_.Origen, $(if ($_.Firmante) { $_.Firmante } else { '(ninguno)' }) }
