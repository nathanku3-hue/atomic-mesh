param(
    [string]$ProjectName = "Standalone",
    [string]$ProjectPath = "",
    [string]$DbPath = "",
    [switch]$Dev  # Explicit flag to enable dev hints (F5/F6) - never auto-enabled
)

# GOLDEN NUANCE FIX: Capture launch directory ONCE at process start
# This is the path shown in header - where user launched from, NOT where module lives
# Must be captured before any cd operations that might change working directory
# FALLBACK: When -ProjectPath not provided, use current directory ($PWD)
$LaunchPath = if ($ProjectPath) { $ProjectPath } else { (Get-Location).Path }

# GUARD: Warn if running from module directory without explicit -ProjectPath
# This prevents user confusion when they see module's data instead of their project's
if (-not $ProjectPath) {
    $moduleMarker = Join-Path $LaunchPath "src\AtomicMesh.UI\AtomicMesh.UI.psd1"
    if (Test-Path $moduleMarker) {
        Write-Host ""
        Write-Host "  WARNING: Running from module directory without -ProjectPath" -ForegroundColor Yellow
        Write-Host "  You are viewing: $LaunchPath" -ForegroundColor DarkGray
        Write-Host "  Recommended: Use launcher\mesh-test.ps1 from your project directory" -ForegroundColor DarkGray
        Write-Host "  Or specify: .\control_panel.ps1 -ProjectPath 'C:\your\project'" -ForegroundColor DarkGray
        Write-Host ""
        Start-Sleep -Milliseconds 2000  # Brief pause to ensure user sees warning
    }
}

$modulePath = Join-Path $PSScriptRoot "src/AtomicMesh.UI/AtomicMesh.UI.psd1"
if (-not (Test-Path $modulePath)) {
    Write-Error "AtomicMesh.UI module not found at $modulePath"
    exit 1
}

Import-Module -Name $modulePath -Force

Start-ControlPanel -ProjectName $ProjectName -ProjectPath $LaunchPath -DbPath $DbPath -Dev:$Dev
