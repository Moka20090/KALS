@echo off
rem Installs Holo HUD 1.0.0 in your KSP folder; close KSP first. UNINSTALL.bat removes it.
cd /d "%~dp0"
title Holo HUD 1.0.0 install
set "PY="
py -3 --version >nul 2>&1 && set "PY=py -3"
if not defined PY (python --version >nul 2>&1 && set "PY=python")
if not defined PY (
  echo Python 3 is not installed. Download it from https://www.python.org/downloads/, tick "Add python.exe to PATH" when you install it, then run INSTALL.bat again.
  echo Or install by hand: copy the contents of the Install folder into your KSP folder ^(see INSTALL.txt^).
  pause
  exit /b 1
)
%PY% install_holohud.py %*
pause
