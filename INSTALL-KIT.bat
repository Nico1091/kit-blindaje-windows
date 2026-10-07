@echo off
setlocal EnableExtensions
title Hardening kit - Install

REM ===========================================================================
REM  Copies the kit to %USERPROFILE%\Security and the buttons to the Desktop.
REM  Changes no Windows settings and does not ask for administrator.
REM  Deletes nothing: if the folder exists, it only updates the kit files.
REM ===========================================================================

set "SOURCE=%~dp0"
set "TARGET=%USERPROFILE%\Security"
for /f "usebackq tokens=*" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP=%%D"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
set "BUTTONS=%DESKTOP%\Hardening kit"

echo.
echo   The kit will be copied to:   %TARGET%
echo   and the buttons to:          %BUTTONS%
echo.
echo   No settings are changed. By continuing you accept the terms in
echo   TERMS.md and the license in LICENSE (no warranty, no liability).
echo   Press any key to continue, or close this window to cancel.
pause >nul

robocopy "%SOURCE%." "%TARGET%" /E /XD .git buttons __pycache__ /XF INSTALL-KIT.bat .gitignore /NFL /NDL /NJH /NJS /NP
if %ERRORLEVEL% GEQ 8 (
    echo.
    echo   Copying the kit failed. Nothing else was changed.
    pause
    exit /b 1
)

robocopy "%SOURCE%buttons" "%BUTTONS%" *.bat /NFL /NDL /NJH /NJS /NP
if %ERRORLEVEL% GEQ 8 (
    echo.
    echo   The kit was copied, but copying the buttons failed.
    pause
    exit /b 1
)

echo.
echo   Done.
echo   1. Open the "Hardening kit" folder on the Desktop.
echo   2. Run HOW IS MY PC first: it changes nothing.
echo   3. Read MANUAL.md before applying any change.
echo.
pause
