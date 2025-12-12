# mesh-start.ps1
# Unified Atomic Mesh Startup Script
# Launches: MCP Server (background) + Commander CLI (foreground)

param(
    [switch]$ServerOnly,
    [switch]$CliOnly
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MeshServer = Join-Path $ScriptDir "mesh_server.py"
$CommanderCli = Join-Path $ScriptDir "commander.ps1"

# Banner
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     ATOMIC MESH v9.0.1 - COMPLIANCE ENGINE        ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if server is already running
$existingServer = Get-Process -Name "python" -ErrorAction SilentlyContinue | 
Where-Object { $_.CommandLine -like "*mesh_server*" }

if (-not $CliOnly) {
    if ($existingServer) {
        Write-Host "  ⚠️  MCP Server already running (PID: $($existingServer.Id))" -ForegroundColor Yellow
    }
    else {
        Write-Host "  🚀 Starting MCP Server..." -ForegroundColor Green
        
        # Start server in background
        $serverJob = Start-Process -FilePath "python" `
            -ArgumentList $MeshServer `
            -WorkingDirectory $ScriptDir `
            -WindowStyle Hidden `
            -PassThru
        
        Start-Sleep -Seconds 2
        
        if ($serverJob.HasExited) {
            Write-Host "  ❌ Server failed to start!" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "  ✅ MCP Server started (PID: $($serverJob.Id))" -ForegroundColor Green
        
        # Save PID for cleanup
        $serverJob.Id | Out-File -FilePath (Join-Path $ScriptDir ".mesh_server.pid") -Force
    }
}

if (-not $ServerOnly) {
    Write-Host ""
    Write-Host "  🎮 Launching Commander CLI..." -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    # Run commander in foreground
    & $CommanderCli
}

# Cleanup on exit (if we started the server)
if (-not $CliOnly -and -not $existingServer) {
    $pidFile = Join-Path $ScriptDir ".mesh_server.pid"
    if (Test-Path $pidFile) {
        $serverPid = Get-Content $pidFile
        Write-Host ""
        Write-Host "  🛑 Stopping MCP Server (PID: $serverPid)..." -ForegroundColor Yellow
        Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
        Remove-Item $pidFile -Force
    }
}
