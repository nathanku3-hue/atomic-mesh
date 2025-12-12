@echo off
title Atomic Mesh Commander
echo Starting Atomic Mesh Commander v6.0...
echo.

REM Kill existing instances
taskkill /F /FI "WINDOWTITLE eq AtomicCommander*" >nul 2>&1
timeout /t 1 /nobreak >nul

REM Start background services
start /min python "C:\Tools\atomic-mesh\mesh_server.py"
start /min powershell -WindowStyle Hidden -Command "& 'C:\Tools\atomic-mesh\worker.ps1' -Type backend -Tool codex"
start /min powershell -WindowStyle Hidden -Command "& 'C:\Tools\atomic-mesh\worker.ps1' -Type frontend -Tool claude"

timeout /t 2 /nobreak >nul

REM Launch Commander in THIS window
powershell -NoExit -Command "& 'C:\Tools\atomic-mesh\control_panel.ps1'"
