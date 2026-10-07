@echo off
setlocal EnableExtensions
title Sentinel - Repair what was missed

REM ===========================================================================
REM  The first hardening pass left 78 firewall rules open because of a bug
REM  in the code, now fixed:
REM
REM    - "Get-NetFirewallRule -DisplayName X -Direction Inbound" is a PowerShell
REM      error (parameters from different sets). It sat inside an empty catch,
REM      so three sweeps returned zero WITHOUT warning.
REM    - Spanish Windows group names carry accents and the code searched
REM      for them without.
REM    - Set-SmbServerConfiguration does not accept -EnableInsecureGuestLogons,
REM      which made the whole SMB block fail.
REM
REM  This re-runs ONLY the ports layer, now fixed. Everything else that was
REM  already applied correctly (Defender, locks, privacy, stealth, VM,
REM  credentials) is left alone.
REM
REM  A prior backup and the 10-minute auto-revert still apply.
REM ===========================================================================

set "SECDIR=%USERPROFILE%\Security"
if not exist "%SECDIR%\Harden.ps1" set "SECDIR=%USERPROFILE%\Security"

if not exist "%SECDIR%\Harden.ps1" (
    echo.
    echo   Cannot find the Security folder.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto ALREADY_ADMIN

echo.
echo   ============================================================
echo           R E P A I R   W H A T   W A S   M I S S E D
echo   ============================================================
echo.
echo   Accept the administrator prompt.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:ALREADY_ADMIN
mode con: cols=100 lines=50 >nul 2>&1

echo.
echo   78 firewall rules that were left open will be closed:
echo.
echo     36  network discovery rules (Wi-Fi Direct, projection,
echo         network discovery, Windows Update P2P, MyASUS)
echo     21  for programs that only listen on your own PC and do not
echo         need to accept outside connections
echo      6  DELETED entirely: adb.exe (x2), lolminer.exe (x2),
echo         zephyrd.exe (x2)
echo     15  for games, which stay on private networks and leave public ones
echo.
echo   And SMB gets hardened, which failed entirely last time.
echo.
echo   Your games keep working at home. adb and the miners lose nothing:
echo   those rules were only for RECEIVING connections, not going out.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SECDIR%\Harden.ps1" -Apply -Layers ports

echo.
echo   ------------------------------------------------------------------
echo    Checking the result...
echo   ------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$e=@(Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow); $p=@($e ^| Where-Object { $_.Profile -match 'Public' -or $_.Profile -eq 'Any' }); Write-Host ''; Write-Host ('   Allowed inbound rules        : ' + $e.Count) -ForegroundColor Cyan; Write-Host ('   Of those, on public profile   : ' + $p.Count) -ForegroundColor Cyan; $bad=@($e ^| Where-Object { $_.DisplayName -match 'adb\.exe^|lolminer^|zephyrd' }); if ($bad.Count -eq 0) { Write-Host '   adb.exe and miners            : DELETED' -ForegroundColor Green } else { Write-Host ('   STILL OPEN: ' + $bad.Count) -ForegroundColor Red }"

echo.
echo   Remember to RESTART: port 445 keeps listening until you do, because
echo   the SMB driver stays loaded in memory even though the service is
echo   already stopped.
echo.
pause
endlocal
