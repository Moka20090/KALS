@echo off
rem SOCK ops3q setup: double-click before each play session, with KSP closed. It checks the Python packages, raises
rem kOS's instruction limit to 10000, writes display.txt for the screen, then runs the ENTRY TRAJ watcher.
cd /d "%~dp0"
title SOCK ops3q setup
set "PY="
py -3 --version >nul 2>&1 && set "PY=py -3"
if not defined PY (python --version >nul 2>&1 && set "PY=python")
if not defined PY (
  echo Python 3 is not installed: get it from https://www.python.org/downloads/ and tick "Add python.exe to PATH".
  pause
  exit /b 1
)
%PY% sock_setup.py %*
pause
