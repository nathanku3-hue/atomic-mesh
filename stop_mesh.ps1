# Atomic Mesh - Clean Shutdown Script (v13.0.1)
# Gracefully stops mesh server using PID file tracking

param(
    [string]$ProjectPath = "",
    [switch]$Force
)

Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  🛑 ATOMIC MESH CLEAN SHUTDOWN" -ForegroundColor Cyan
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Set working directory
if ($ProjectPath -and (Test-Path $ProjectPath)) {
    Set-Location $ProjectPath
}
$CurrentDir = (Get-Location).Path

# Look for PID file
$pidFile = Join-Path $CurrentDir "control\state\_runtime\mesh_server.pid"

if (-not (Test-Path $pidFile)) {
    Write-Host "  ⚠️  No PID file found at: $pidFile" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Searching for running mesh processes..." -ForegroundColor Gray

    $meshProcesses = Get-Process python -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*mesh_server*" }

    if ($meshProcesses) {
        Write-Host "  Found $($meshProcesses.Count) mesh server process(es):" -ForegroundColor Yellow
        foreach ($proc in $meshProcesses) {
            Write-Host "    PID: $($proc.Id)" -ForegroundColor White
        }
        Write-Host ""

        if ($Force) {
            Write-Host "  🔥 Force flag set - killing all found processes..." -ForegroundColor Red
            $meshProcesses | Stop-Process -Force
            Write-Host "  ✅ Processes terminated" -ForegroundColor Green
        } else {
            Write-Host "  To force stop: .\stop_mesh.ps1 -Force" -ForegroundColor Gray
            Write-Host "  Or manually: Stop-Process -Id <PID>" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ✅ No mesh server processes found running" -ForegroundColor Green
    }

    Write-Host ""
    exit 0
}

# Read PID from file
$serverPid = Get-Content -Path $pidFile -Raw -ErrorAction SilentlyContinue
if (-not $serverPid) {
    Write-Host "  ❌ PID file is empty or corrupted" -ForegroundColor Red
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
    exit 1
}

$serverPid = $serverPid.Trim()
Write-Host "  Found server PID: $serverPid" -ForegroundColor Gray

# Check if process exists
$process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue

if (-not $process) {
    Write-Host "  ⚠️  Process $serverPid is not running (stale PID file)" -ForegroundColor Yellow
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
    Write-Host "  ✅ Cleaned up stale PID file" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# Verify it's actually the mesh server
if ($process.ProcessName -ne "python") {
    Write-Host "  ⚠️  PID $serverPid is not a Python process (PID file corrupted?)" -ForegroundColor Yellow
    Write-Host "  Actual process: $($process.ProcessName)" -ForegroundColor Gray
    Write-Host ""
    $response = Read-Host "  Remove corrupted PID file? [y/N]"
    if ($response -eq "y" -or $response -eq "Y") {
        Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
        Write-Host "  ✅ PID file removed" -ForegroundColor Green
    }
    Write-Host ""
    exit 1
}

# Stop the server
Write-Host "  🛑 Stopping mesh server (PID: $serverPid)..." -ForegroundColor Yellow

try {
    if ($Force) {
        Stop-Process -Id $serverPid -Force -ErrorAction Stop
        Write-Host "  ✅ Server force-killed" -ForegroundColor Green
    } else {
        # Graceful shutdown (SIGTERM equivalent on Windows)
        Stop-Process -Id $serverPid -ErrorAction Stop

        # Wait for process to exit (up to 5 seconds)
        $waited = 0
        while (-not $process.HasExited -and $waited -lt 5) {
            Start-Sleep -Milliseconds 500
            $waited += 0.5
            $process.Refresh()
        }

        if ($process.HasExited) {
            Write-Host "  ✅ Server stopped gracefully" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Server did not exit cleanly (may need -Force)" -ForegroundColor Yellow
        }
    }

    # Clean up PID file
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue

} catch {
    Write-Host "  ❌ Failed to stop server: $_" -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✅ SHUTDOWN COMPLETE" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Server PID $serverPid terminated" -ForegroundColor Gray
Write-Host ""
Write-Host "  Manual steps (if needed):" -ForegroundColor Yellow
Write-Host "    1. Close Control Panel window (Ctrl+C or /quit)" -ForegroundColor Gray
Write-Host "    2. Close Dashboard window (Ctrl+C or close)" -ForegroundColor Gray
Write-Host ""
