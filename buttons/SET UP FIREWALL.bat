@echo off
rem Se abre solo como administrador.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Security\Setup-Firewall.ps1"
