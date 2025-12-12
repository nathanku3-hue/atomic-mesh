# Atomic Mesh - Unified Startup Script (v13.1.0)
# Launches mesh server + unified control panel (CLI + integrated dashboard)

param(
    [string]$ProjectPath = "",
    [switch]$ServerOnly
)

Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  🚀 ATOMIC MESH UNIFIED STARTUP (v13.1.0)" -ForegroundColor Cyan
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Set working directory
if ($ProjectPath -and (Test-Path $ProjectPath)) {
    Set-Location $ProjectPath
}
$CurrentDir = (Get-Location).Path

Write-Host "  Working Directory: $CurrentDir" -ForegroundColor Gray
Write-Host ""

# Check if server is already running
$existingServer = Get-Process -Name "python" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*mesh_server.py*" }

if ($existingServer) {
    Write-Host "  ⚠️  Mesh server appears to be already running (PID: $($existingServer.Id))" -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "  Kill existing server and restart? [y/N]"
    if ($response -eq "y" -or $response -eq "Y") {
        Stop-Process -Id $existingServer.Id -Force
        Start-Sleep -Seconds 2
        Write-Host "  ✅ Existing server terminated" -ForegroundColor Green
    } else {
        Write-Host "  Keeping existing server. Exiting..." -ForegroundColor Gray
        exit
    }
}

# Phase 1: Start Mesh Server
Write-Host "  [1/3] Starting Mesh Server..." -ForegroundColor Yellow
$serverScriptPath = Join-Path $PSScriptRoot "mesh_server.py"

if (-not (Test-Path $serverScriptPath)) {
    Write-Host "  ❌ Error: mesh_server.py not found at $serverScriptPath" -ForegroundColor Red
    exit 1
}

# Ensure runtime directory exists for PID tracking
$runtimeDir = Join-Path $CurrentDir "control\state\_runtime"
if (-not (Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
}

# Start server in new window (minimized)
# NOTE: This is a single-shot launch. No auto-restart, no watchdog.
# Server must pass /health and /drift checks before production use.
$serverProcess = Start-Process -FilePath "python" `
    -ArgumentList "`"$serverScriptPath`"" `
    -WorkingDirectory $CurrentDir `
    -PassThru `
    -WindowStyle Minimized

Write-Host "  ✅ Server started (PID: $($serverProcess.Id))" -ForegroundColor Green

# Write PID file for clean shutdown
$pidFile = Join-Path $runtimeDir "mesh_server.pid"
$serverProcess.Id | Set-Content -Path $pidFile

# Wait for server to initialize
Write-Host "  ⏳ Waiting for server initialization..." -ForegroundColor Gray
Start-Sleep -Seconds 3

# Check if server is still running
if ($serverProcess.HasExited) {
    Write-Host "  ❌ Server failed to start. Check logs for errors." -ForegroundColor Red
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
    exit 1
}

if ($ServerOnly) {
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  ✅ Server-only mode: Mesh server running" -ForegroundColor Green
    Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server PID: $($serverProcess.Id)" -ForegroundColor White
    Write-Host "  To stop: Stop-Process -Id $($serverProcess.Id)" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# Phase 2: Launch Control Panel
Write-Host ""
Write-Host "  [2/3] Launching Control Panel..." -ForegroundColor Yellow
$controlPanelPath = Join-Path $PSScriptRoot "control_panel.ps1"

if (Test-Path $controlPanelPath) {
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoExit", "-Command", "& { `$Host.UI.RawUI.BackgroundColor = 'Black'; `$Host.UI.RawUI.ForegroundColor = 'White'; Clear-Host; & '$controlPanelPath' }" `
        -WorkingDirectory $CurrentDir
    Write-Host "  ✅ Control Panel launched" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Control Panel not found: $controlPanelPath" -ForegroundColor Yellow
}

# Phase 3: Dashboard Integration (v13.1)
Write-Host ""
Write-Host "  [3/3] Dashboard Integration..." -ForegroundColor Yellow
Write-Host "  ✅ Dashboard integrated into Control Panel (v13.1)" -ForegroundColor Green
Write-Host "     Use /dash for full view, /compact for status bar" -ForegroundColor Gray

# Summary
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✅ ATOMIC MESH STARTUP COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Components Running:" -ForegroundColor White
Write-Host "    • Mesh Server      (PID: $($serverProcess.Id))" -ForegroundColor Gray
Write-Host "    • Control Panel    (Unified CLI + Dashboard)" -ForegroundColor Gray
Write-Host ""
Write-Host "  📌 Next recommended step:" -ForegroundColor Cyan
Write-Host "    Run /ops in Control Panel to verify system health" -ForegroundColor White
Write-Host ""
Write-Host "  View Commands:" -ForegroundColor White
Write-Host "    /dash    - Full dashboard view" -ForegroundColor Gray
Write-Host "    /compact - Compact status bar" -ForegroundColor Gray
Write-Host ""
Write-Host "  To stop all:" -ForegroundColor Yellow
Write-Host "    .\stop_mesh.ps1" -ForegroundColor White
Write-Host "    OR: Stop-Process -Id $($serverProcess.Id)" -ForegroundColor Gray
Write-Host "        Then close Control Panel window" -ForegroundColor Gray
Write-Host ""
