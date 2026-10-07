<#
.SYNOPSIS
    With a single administrator prompt:
      1. Updates Git for Windows (its signing certificate had expired).
      2. Repeats the signature audit, this time ALSO seeing the protected
         system processes, which do not show their path without elevation.
    The report is saved to Security\Reports\signature-audit-<date>.txt
#>

. (Join-Path $PSScriptRoot 'lib\Core.ps1')
if (-not (Assert-Elevado -Script $PSCommandPath)) { return }

Write-Titulo 'UPDATING GIT'
$wg = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
if (-not (Test-Path $wg)) { $wg = 'winget.exe' }
& $wg upgrade --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
$sig = Get-AuthenticodeSignature -LiteralPath 'C:\Program Files\Git\usr\bin\bash.exe'
$ver = (Get-Item 'C:\Program Files\Git\cmd\git.exe').VersionInfo.ProductVersion
Write-Bitacora "Git $ver ; bash.exe signature: $($sig.Status)" $(if ($sig.Status -eq 'Valid') { 'OK' } else { 'WARN' })

Write-Titulo 'SIGNATURE AUDIT (FULL)'
$inf = Join-Path $script:DirInf ("signature-audit-" + $script:Sello + '.txt')
& (Join-Path $PSScriptRoot 'lib\audit-signatures.ps1') | Tee-Object -FilePath $inf | ForEach-Object { Write-Host $_ }
$sinRuta = @(Get-CimInstance Win32_Process | Where-Object { -not $_.ExecutablePath -and $_.ProcessId -gt 4 } | ForEach-Object Name | Sort-Object -Unique)
Add-Content $inf "`nprocesses with no visible path even as admin (normal kernel processes): $($sinRuta -join ', ')"
Write-Bitacora "full report: $inf" 'OK'
