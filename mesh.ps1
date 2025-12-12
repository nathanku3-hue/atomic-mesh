# mesh.ps1 - Quick launcher for Atomic Mesh Control Panel
# Usage: .\mesh.ps1  OR  mesh  (if added to PATH/profile)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir\control_panel.ps1"
