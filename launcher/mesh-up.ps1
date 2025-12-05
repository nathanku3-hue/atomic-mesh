# USAGE: Type 'mesh-up' in ANY project folder.
# LOCATION: C:\Tools\atomic-mesh\mesh-up.ps1
# LAYOUT: Single window (Commander CLI) + background workers

param()

$MeshRoot = "C:\Tools\atomic-mesh"

Write-Host "🚀 Atomic Mesh v5.0 (Single CLI Mode)" -ForegroundColor Cyan
Write-Host ""

# --- 1. START BACKGROUND SERVER ---
Write-Host "  Starting Brain (MCP Server)..." -ForegroundColor Gray
Start-Process python -ArgumentList "$MeshRoot\mesh_server.py" -WindowStyle Hidden

# --- 2. START BACKGROUND WORKERS ---
Write-Host "  Starting Workers (background)..." -ForegroundColor Gray

# Workers run in hidden windows, logging to files
$workerScript = @"
`$host.UI.RawUI.WindowTitle = 'AtomicWorker'
& '$MeshRoot\worker.ps1' -Type '{TYPE}' -Tool '{TOOL}'
"@

# Backend worker (hidden)
$beScript = $workerScript -replace '{TYPE}', 'backend' -replace '{TOOL}', 'codex'
Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"$beScript`"" -WindowStyle Hidden

# Frontend worker (hidden)  
$feScript = $workerScript -replace '{TYPE}', 'frontend' -replace '{TOOL}', 'claude'
Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"$feScript`"" -WindowStyle Hidden

Start-Sleep -Seconds 2

# --- 3. LAUNCH CONTROL PANEL (foreground) ---
Write-Host "  Launching Commander CLI..." -ForegroundColor Gray
Write-Host ""
Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  Workers running in background. Logs in ./logs/            │" -ForegroundColor Gray
Write-Host "│  Press [1] for Backend stream, [2] for Frontend stream     │" -ForegroundColor Gray
Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 1

# Run control panel in foreground
& "$MeshRoot\control_panel.ps1"
