# Launch Atomic Mesh Commander in a new visible window
# Run this from your project directory

$MeshRoot = "C:\Tools\atomic-mesh"

Write-Host "🚀 Launching Atomic Mesh Commander v5.0..." -ForegroundColor Cyan

# Kill any existing instances
Get-Process | Where-Object { $_.MainWindowTitle -match 'Atomic' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Start background server
Write-Host "  Starting MCP Server..." -ForegroundColor Gray
Start-Process python -ArgumentList "$MeshRoot\mesh_server.py" -WindowStyle Hidden

# Start background workers
Write-Host "  Starting Workers..." -ForegroundColor Gray
Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"& '$MeshRoot\worker.ps1' -Type backend -Tool codex`"" -WindowStyle Hidden
Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"& '$MeshRoot\worker.ps1' -Type frontend -Tool claude`"" -WindowStyle Hidden

Start-Sleep -Seconds 2

# Launch Control Panel in NEW VISIBLE WINDOW
Write-Host "  Launching Commander CLI..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit -Command `"& '$MeshRoot\control_panel.ps1'`""

Write-Host ""
Write-Host "✅ Commander window should appear!" -ForegroundColor Green
Write-Host "   If not visible, check taskbar for PowerShell window" -ForegroundColor Gray
