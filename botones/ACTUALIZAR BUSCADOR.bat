@echo off
rem Actualiza el Buscador (LibreWolf) con firma verificada y repone la carita y la IP oculta.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%USERPROFILE%\Seguridad\Actualizar-LibreWolf.ps1'"
