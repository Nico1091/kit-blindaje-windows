@echo off
rem Actualiza el Browser (LibreWolf) con firma verificada y repone la smiley y la IP oculta.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%USERPROFILE%\Security\Update-LibreWolf.ps1'"
