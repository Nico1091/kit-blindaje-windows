@echo off
rem Relaunches itself as administrator.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Security\Setup-Browser.ps1"
