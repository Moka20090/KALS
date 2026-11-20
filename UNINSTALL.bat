@echo off
rem Uninstalls KAL/S v1.0 from your KSP folder; close KSP first. Only KAL/S: Holo HUD (the bundled HUD) stays; HoloHUD\UNINSTALL.bat removes that. UNINSTALL.bat --dry says what it would do, --yes asks nothing.
cd /d "%~dp0"
title KAL/S v1.0 uninstall
set "PY="
py -3 --version >nul 2>&1 && set "PY=py -3"
if not defined PY (python --version >nul 2>&1 && set "PY=python")
if not defined PY (
  echo Python 3 is not installed. Download it from https://www.python.org/downloads/, tick "Add python.exe to PATH" when you install it, then run UNINSTALL.bat again.
  pause
  exit /b 1
)
%PY% install_ops3q.py --uninstall %*
pause
