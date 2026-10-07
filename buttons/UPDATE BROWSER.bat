@echo off
rem Updates the Browser (LibreWolf) with a verified signature and restores the smiley and the hidden IP.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%USERPROFILE%\Security\Update-LibreWolf.ps1'"
