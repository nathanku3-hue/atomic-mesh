param(
    [string]$ProjectName = "Standalone",
    [string]$ProjectPath = "",
    [string]$DbPath = "",
    [switch]$Dev  # Explicit flag to enable dev hints (F5/F6) - never auto-enabled
)

# GOLDEN NUANCE FIX: Capture launch directory ONCE at process start
# This is the path shown in header - where user launched from, NOT where module lives
# Must be captured before any cd operations that might change working directory
$LaunchPath = if ($ProjectPath) { $ProjectPath } else { (Get-Location).Path }

$modulePath = Join-Path $PSScriptRoot "src/AtomicMesh.UI/AtomicMesh.UI.psd1"
if (-not (Test-Path $modulePath)) {
    Write-Error "AtomicMesh.UI module not found at $modulePath"
    exit 1
}

Import-Module -Name $modulePath -Force

Start-ControlPanel -ProjectName $ProjectName -ProjectPath $LaunchPath -DbPath $DbPath -Dev:$Dev
