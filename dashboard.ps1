# Atomic Mesh Dashboard Shim (v13.1)
# Backwards-compatible wrapper that launches control_panel.ps1 in dashboard mode
#
# DEPRECATION NOTICE:
# As of v13.1, the dashboard is integrated into the control panel.
# This script is kept for backwards compatibility and will be removed in v13.2.
#
# Recommended: Use control_panel.ps1 directly with:
#   - Auto view switching (default)
#   - /dash to toggle full dashboard
#   - /compact for status bar only
#
# Or launch with: .\control_panel.ps1 -DashboardMode

param(
    [int]$RefreshRate = 5  # Ignored in v13.1 (kept for backwards compat)
)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$controlPanel = Join-Path $scriptDir "control_panel.ps1"

if (Test-Path $controlPanel) {
    Write-Host "  [v13.1] Dashboard is now integrated into Control Panel" -ForegroundColor Yellow
    Write-Host "  Launching in dashboard mode..." -ForegroundColor Gray
    Write-Host ""

    # Launch control panel in dashboard mode
    & $controlPanel -DashboardMode
}
else {
    Write-Host "  ERROR: control_panel.ps1 not found at $controlPanel" -ForegroundColor Red
    exit 1
}
