<#
    Atomic Mesh v7.5 - Multi-Project Grid Launcher
    Creates a 2x2 grid of Commander CLIs in Windows Terminal
    
    Usage:
        .\mesh-up.ps1 -Ids 1,2        # 2 projects side-by-side
        .\mesh-up.ps1 -Ids 1,2,3      # 3 projects (1 left, 2 right stacked)
        .\mesh-up.ps1 -Ids 1,2,3,4    # 4 projects in 2x2 grid
#>

param(
    [int[]]$Ids = @(1)
)

$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$ConfigPath = "$RepoRoot\config\projects.json"
$ControlPanel = "$RepoRoot\src\control_panel.ps1"

# Validate config exists
if (-not (Test-Path $ConfigPath)) { 
    Write-Error "❌ Config missing: $ConfigPath"
    exit 1
}

# Load and filter projects
$AllProjects = Get-Content $ConfigPath | ConvertFrom-Json
$Projects = $AllProjects | Where-Object { $Ids -contains $_.id }

if ($Projects.Count -eq 0) { 
    Write-Host "❌ No projects found for IDs: $($Ids -join ', ')" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available projects:" -ForegroundColor Cyan
    foreach ($p in $AllProjects) {
        Write-Host "  [$($p.id)] $($p.name)" -ForegroundColor Gray
    }
    exit 1
}

Write-Host "🚀 Launching Mission Control Grid..." -ForegroundColor Cyan
Write-Host "   Projects: $($Projects.Count)" -ForegroundColor Gray

# Function to build the PowerShell command for a pane
function Get-PaneCmd {
    param($Proj)
    
    # Escape paths for nested command
    $escapedPath = $Proj.path -replace "'", "''"
    $escapedPanel = $ControlPanel -replace "'", "''"
    $escapedName = $Proj.name -replace "'", "''"
    $escapedDb = $Proj.db -replace "'", "''"
    
    # Build command: CD to project, then run control panel with params
    $cmd = "powershell.exe -NoExit -Command `"Set-Location '$escapedPath'; & '$escapedPanel' -ProjectName '$escapedName' -ProjectPath '$escapedPath' -DbPath '$escapedDb'`""
    
    return $cmd
}

# Build Windows Terminal arguments
$WtArgs = New-Object System.Collections.ArrayList

# PANE 1 (Top-Left / Full Window)
$P1 = $Projects[0]
$Cmd1 = Get-PaneCmd $P1
[void]$WtArgs.Add("new-tab --title `"$($P1.name)`" $Cmd1")

Write-Host "   [1] $($P1.name)" -ForegroundColor Yellow

if ($Projects.Count -eq 2) {
    # ┌─────────┬─────────┐
    # │    P1   │    P2   │
    # │         │         │
    # └─────────┴─────────┘
    
    $P2 = $Projects[1]
    $Cmd2 = Get-PaneCmd $P2
    [void]$WtArgs.Add("; split-pane -V --title `"$($P2.name)`" $Cmd2")
    
    Write-Host "   [2] $($P2.name)" -ForegroundColor Yellow
}
elseif ($Projects.Count -eq 3) {
    # ┌─────────┬─────────┐
    # │         │    P2   │
    # │    P1   ├─────────┤
    # │         │    P3   │
    # └─────────┴─────────┘
    
    $P2 = $Projects[1]
    $P3 = $Projects[2]
    
    $Cmd2 = Get-PaneCmd $P2
    $Cmd3 = Get-PaneCmd $P3
    
    [void]$WtArgs.Add("; split-pane -V --title `"$($P2.name)`" $Cmd2")
    [void]$WtArgs.Add("; split-pane -H --title `"$($P3.name)`" $Cmd3")
    
    Write-Host "   [2] $($P2.name)" -ForegroundColor Yellow
    Write-Host "   [3] $($P3.name)" -ForegroundColor Yellow
}
elseif ($Projects.Count -ge 4) {
    # ┌─────────┬─────────┐
    # │    P1   │    P2   │
    # ├─────────┼─────────┤
    # │    P3   │    P4   │
    # └─────────┴─────────┘
    
    $P2 = $Projects[1]
    $P3 = $Projects[2]
    $P4 = $Projects[3]
    
    $Cmd2 = Get-PaneCmd $P2
    $Cmd3 = Get-PaneCmd $P3
    $Cmd4 = Get-PaneCmd $P4
    
    # Step 1: Split vertically (P1 | P2)
    [void]$WtArgs.Add("; split-pane -V --title `"$($P2.name)`" $Cmd2")
    
    # Step 2: Split P2 horizontally (P2 on top, P4 on bottom)
    [void]$WtArgs.Add("; split-pane -H --title `"$($P4.name)`" $Cmd4")
    
    # Step 3: Move focus to left pane (P1)
    [void]$WtArgs.Add("; move-focus left")
    
    # Step 4: Split P1 horizontally (P1 on top, P3 on bottom)
    [void]$WtArgs.Add("; split-pane -H --title `"$($P3.name)`" $Cmd3")
    
    Write-Host "   [2] $($P2.name)" -ForegroundColor Yellow
    Write-Host "   [3] $($P3.name)" -ForegroundColor Yellow
    Write-Host "   [4] $($P4.name)" -ForegroundColor Yellow
}

# Join all arguments
$FinalArgs = $WtArgs -join " "

Write-Host ""
Write-Host "   Launching Windows Terminal..." -ForegroundColor Gray

# Launch Windows Terminal
try {
    Start-Process "wt.exe" -ArgumentList $FinalArgs
    Write-Host "✅ Mission Control launched!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to launch Windows Terminal: $_" -ForegroundColor Red
    Write-Host "   Make sure Windows Terminal (wt.exe) is installed" -ForegroundColor Gray
}
