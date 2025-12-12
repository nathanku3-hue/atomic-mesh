# USAGE: Type 'mesh-up' in ANY project folder, or run directly from atomic-mesh folder
# LAYOUT: Single window (Control Panel CLI) + background workers

param()

# Dynamic path - use script location
$MeshRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $MeshRoot) { $MeshRoot = Get-Location }

Write-Host "🚀 Atomic Mesh v9.0.1 (Codex-Style CLI)" -ForegroundColor Cyan
Write-Host "   Path: $MeshRoot" -ForegroundColor DarkGray
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
Write-Host "  Launching Control Panel (Codex-style)..." -ForegroundColor Gray
Write-Host ""
Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  Workers running in background. Logs in ./logs/            │" -ForegroundColor Gray
Write-Host "│  Type '/' for instant command dropdown with arrow keys     │" -ForegroundColor Gray
Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 1

# Run control panel in foreground
& "$MeshRoot\control_panel.ps1"
