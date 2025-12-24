# =============================================================================
# Module Structure Guard Test
# =============================================================================
# Prevents "nested function" bugs where PowerShell functions become unavailable
# at module scope due to structural errors (missing braces, etc.)
#
# This test catches the v20.0 bug where Invoke-PickTask was nested inside
# Invoke-AcceptPlan due to a missing closing brace.
# =============================================================================

$ErrorActionPreference = "Stop"
$script:TestsPassed = 0
$script:TestsFailed = 0

function Assert-FunctionExists {
    param(
        [string]$FunctionName,
        [string]$Context = "module scope"
    )

    $cmd = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "  [PASS] $FunctionName exists at $Context" -ForegroundColor Green
        $script:TestsPassed++
        return $true
    } else {
        Write-Host "  [FAIL] $FunctionName NOT FOUND at $Context" -ForegroundColor Red
        $script:TestsFailed++
        return $false
    }
}

Write-Host ""
Write-Host "=" * 60
Write-Host "Module Structure Guard Test"
Write-Host "=" * 60
Write-Host ""

# Find repo root from test location
$testRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $testRoot

# Load MeshServerAdapter directly (not via module, to catch nesting issues)
$adapterPath = Join-Path $repoRoot "src\AtomicMesh.UI\Private\Adapters\MeshServerAdapter.ps1"
Write-Host "Loading: $adapterPath"
Write-Host ""

try {
    . $adapterPath
} catch {
    Write-Host "[FAIL] Failed to load MeshServerAdapter.ps1: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Checking required functions at module scope..."
Write-Host ""

# These functions MUST be available at module scope
# If any become nested due to brace errors, this test will catch it
$requiredFunctions = @(
    "Get-MeshServerPath",
    "Get-LatestDraftPlan",
    "Invoke-DraftPlan",
    "Invoke-AcceptPlan",
    "Invoke-PickTask",
    "Invoke-CheckGoBlockers"
)

foreach ($fn in $requiredFunctions) {
    Assert-FunctionExists -FunctionName $fn
}

Write-Host ""
Write-Host "=" * 60

if ($script:TestsFailed -gt 0) {
    Write-Host "FAILED: $($script:TestsFailed) function(s) not at module scope" -ForegroundColor Red
    Write-Host ""
    Write-Host "This likely indicates a structural bug (missing brace) in MeshServerAdapter.ps1"
    Write-Host "causing functions to become nested inside other functions."
    Write-Host ""
    exit 1
} else {
    Write-Host "PASSED: All $($script:TestsPassed) functions available at module scope" -ForegroundColor Green
    exit 0
}
