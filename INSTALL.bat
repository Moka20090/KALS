@echo off
rem Installs or upgrades KAL/S v1.0 in your KSP folder; close KSP first. KAL/S was called SOCK until v0.22. UNINSTALL.bat removes it (and only it: Holo HUD, which comes with it, stays). INSTALL.bat installs Holo HUD 1.0.0 too (bundled).
cd /d "%~dp0"
title KAL/S v1.0 install
set "PY="
py -3 --version >nul 2>&1 && set "PY=py -3"
if not defined PY (python --version >nul 2>&1 && set "PY=python")
if not defined PY (
  echo Python 3 is not installed. Download it from https://www.python.org/downloads/, tick "Add python.exe to PATH" when you install it, then run INSTALL.bat again.
  pause
  exit /b 1
)
%PY% install_ops3q.py %*
pause
