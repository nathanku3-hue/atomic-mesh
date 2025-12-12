@echo off
REM Atomic Mesh - Windows Launcher
REM Quick launcher for the unified startup script

powershell.exe -ExecutionPolicy Bypass -File "%~dp0start_mesh.ps1" %*
