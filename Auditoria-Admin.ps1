<#
.SYNOPSIS
    Con un solo permiso de administrador:
      1. Actualiza Git para Windows (su certificado de firma habia caducado).
      2. Repite la auditoria de firmas viendo TAMBIEN los procesos protegidos
         del sistema, que sin permisos no muestran su ruta.
    El informe queda en Seguridad\Informes\auditoria-firmas-<fecha>.txt
#>

. (Join-Path $PSScriptRoot 'lib\Nucleo.ps1')
if (-not (Assert-Elevado -Script $PSCommandPath)) { return }

Write-Titulo 'ACTUALIZANDO GIT'
$wg = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
if (-not (Test-Path $wg)) { $wg = 'winget.exe' }
& $wg upgrade --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
$sig = Get-AuthenticodeSignature -LiteralPath 'C:\Program Files\Git\usr\bin\bash.exe'
$ver = (Get-Item 'C:\Program Files\Git\cmd\git.exe').VersionInfo.ProductVersion
Write-Bitacora "Git $ver ; firma de bash.exe: $($sig.Status)" $(if ($sig.Status -eq 'Valid') { 'OK' } else { 'AVISO' })

Write-Titulo 'AUDITORIA DE FIRMAS (COMPLETA)'
$inf = Join-Path $script:DirInf ("auditoria-firmas-" + $script:Sello + '.txt')
& (Join-Path $PSScriptRoot 'lib\auditar-firmas.ps1') | Tee-Object -FilePath $inf | ForEach-Object { Write-Host $_ }
$sinRuta = @(Get-CimInstance Win32_Process | Where-Object { -not $_.ExecutablePath -and $_.ProcessId -gt 4 } | ForEach-Object Name | Sort-Object -Unique)
Add-Content $inf "`nprocesos sin ruta visible ni como admin (normales del nucleo): $($sinRuta -join ', ')"
Write-Bitacora "informe completo: $inf" 'OK'
