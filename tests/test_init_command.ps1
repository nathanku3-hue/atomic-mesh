#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for /init command and initialization detection
.DESCRIPTION
    Verifies:
    - Test-RepoInitialized 4-tier detection (marker, registry, docs, legacy)
    - Invoke-ProjectInit creates templates and marker
    - Safety guard blocks re-init without --force
    - Partial init scenarios (marker exists but docs missing)
#>

$ErrorActionPreference = "Stop"

# Load the helpers directly
$helpersPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Helpers" "InitHelpers.ps1"
. $helpersPath

$testsFailed = 0
$testsPassed = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
    $script:testsPassed++
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

# Create temp directory for tests
$testRoot = Join-Path $env:TEMP "mesh_init_test_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

try {
    # =============================================================================
    # Test-RepoInitialized Tests
    # =============================================================================
    Write-Host "`n=== Test-RepoInitialized ===" -ForegroundColor Cyan

    # Test 1: Empty directory returns not initialized
    $emptyDir = Join-Path $testRoot "empty"
    New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
    $result = Test-RepoInitialized -Path $emptyDir -RepoRoot $testRoot
    if (-not $result.initialized -and $result.reason -eq "none") {
        Pass "Empty directory: not initialized"
    } else {
        Fail "Empty directory" "Expected initialized=false, reason=none"
    }

    # Test 2: Marker file detection (Tier A)
    $markerDir = Join-Path $testRoot "with_marker"
    $stateDir = Join-Path $markerDir "control\state"
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    "" | Set-Content -Path (Join-Path $stateDir ".mesh_initialized")
    $result = Test-RepoInitialized -Path $markerDir -RepoRoot $testRoot
    if ($result.initialized -and $result.reason -eq "marker") {
        Pass "Marker file: detected as initialized (Tier A)"
    } else {
        Fail "Marker file" "Expected initialized=true, reason=marker, got reason=$($result.reason)"
    }

    # Test 3: Golden docs detection (Tier C) - 2 of 3 required
    $docsDir = Join-Path $testRoot "with_docs"
    $docsSubDir = Join-Path $docsDir "docs"
    New-Item -ItemType Directory -Force -Path $docsSubDir | Out-Null
    "# PRD" | Set-Content -Path (Join-Path $docsSubDir "PRD.md")
    "# SPEC" | Set-Content -Path (Join-Path $docsSubDir "SPEC.md")
    $result = Test-RepoInitialized -Path $docsDir -RepoRoot $testRoot
    if ($result.initialized -and $result.reason -eq "docs") {
        Pass "Golden docs (2 of 3): detected as initialized (Tier C)"
    } else {
        Fail "Golden docs" "Expected initialized=true, reason=docs, got reason=$($result.reason)"
    }

    # Test 4: Only 1 of 3 docs - NOT initialized
    $oneDocDir = Join-Path $testRoot "one_doc"
    $oneDocSubDir = Join-Path $oneDocDir "docs"
    New-Item -ItemType Directory -Force -Path $oneDocSubDir | Out-Null
    "# PRD" | Set-Content -Path (Join-Path $oneDocSubDir "PRD.md")
    $result = Test-RepoInitialized -Path $oneDocDir -RepoRoot $testRoot
    if (-not $result.initialized) {
        Pass "Only 1 of 3 docs: not initialized (needs 2)"
    } else {
        Fail "Only 1 doc" "Expected initialized=false"
    }

    # Test 5: Legacy layout detection (Tier D)
    $legacyDir = Join-Path $testRoot "legacy"
    $legacyMeshDir = Join-Path $legacyDir "docs\_mesh"
    New-Item -ItemType Directory -Force -Path $legacyMeshDir | Out-Null
    "# Active Spec" | Set-Content -Path (Join-Path $legacyMeshDir "ACTIVE_SPEC.md")
    $result = Test-RepoInitialized -Path $legacyDir -RepoRoot $testRoot
    if ($result.initialized -and $result.reason -eq "legacy") {
        Pass "Legacy layout: detected as initialized (Tier D)"
    } else {
        Fail "Legacy layout" "Expected initialized=true, reason=legacy, got reason=$($result.reason)"
    }

    # Test 6: Partial init - marker exists but docs missing
    $partialDir = Join-Path $testRoot "partial"
    $partialStateDir = Join-Path $partialDir "control\state"
    New-Item -ItemType Directory -Force -Path $partialStateDir | Out-Null
    "" | Set-Content -Path (Join-Path $partialStateDir ".mesh_initialized")
    # No docs created
    $result = Test-RepoInitialized -Path $partialDir -RepoRoot $testRoot
    if ($result.initialized -and $result.reason -eq "marker") {
        Pass "Partial init (marker only): initialized=true (marker wins)"
    } else {
        Fail "Partial init" "Expected initialized=true, reason=marker"
    }

    # =============================================================================
    # Invoke-ProjectInit Tests
    # =============================================================================
    Write-Host "`n=== Invoke-ProjectInit ===" -ForegroundColor Cyan

    # TemplateRoot = where library/templates/ lives (the mesh repo)
    $templateRoot = Split-Path -Parent $PSScriptRoot

    # Test 7: Fresh init creates templates and marker
    $freshDir = Join-Path $testRoot "fresh_init"
    New-Item -ItemType Directory -Force -Path $freshDir | Out-Null
    $result = Invoke-ProjectInit -Path $freshDir -TemplateRoot $templateRoot
    if ($result.Success -and $result.Created.Count -gt 0) {
        Pass "Fresh init: Success with $($result.Created.Count) files created"
    } else {
        Fail "Fresh init" "Expected Success=true, got Success=$($result.Success), Error=$($result.Error)"
    }

    # Test 8: Verify marker was created
    $markerPath = Join-Path $freshDir "control\state\.mesh_initialized"
    if (Test-Path $markerPath) {
        Pass "Fresh init: Marker file created"
    } else {
        Fail "Fresh init marker" "Marker file not found at $markerPath"
    }

    # Test 9: Re-init without force skips existing files
    $result2 = Invoke-ProjectInit -Path $freshDir -TemplateRoot $templateRoot
    if ($result2.Success -and $result2.Skipped.Count -gt 0) {
        Pass "Re-init: Skipped $($result2.Skipped.Count) existing files"
    } else {
        Fail "Re-init skip" "Expected skipped files, got Skipped=$($result2.Skipped.Count)"
    }

    # Test 10: Re-init with force recreates files
    $result3 = Invoke-ProjectInit -Path $freshDir -TemplateRoot $templateRoot -Force
    if ($result3.Success -and $result3.Created.Count -gt 0) {
        Pass "Re-init with --force: Recreated $($result3.Created.Count) files"
    } else {
        Fail "Re-init force" "Expected created files with Force, got Created=$($result3.Created.Count)"
    }

    # =============================================================================
    # Edge Cases
    # =============================================================================
    Write-Host "`n=== Edge Cases ===" -ForegroundColor Cyan

    # Test 11: Null path uses current directory
    $result = Test-RepoInitialized -Path $null -RepoRoot $testRoot
    if ($result.reason) {
        Pass "Null path: Falls back to current directory"
    } else {
        Fail "Null path" "Expected valid result"
    }

    # Test 12: Init result structure
    $structDir = Join-Path $testRoot "struct_test"
    New-Item -ItemType Directory -Force -Path $structDir | Out-Null
    $result = Invoke-ProjectInit -Path $structDir -TemplateRoot $templateRoot
    if ($result.ContainsKey("Success") -and $result.ContainsKey("Created") -and
        $result.ContainsKey("Skipped") -and $result.ContainsKey("Error")) {
        Pass "Init result: Has required keys (Success, Created, Skipped, Error)"
    } else {
        Fail "Init result structure" "Missing required keys"
    }

    # =============================================================================
    # REGRESSION TESTS: Partial Init + Missing Templates
    # =============================================================================
    Write-Host "`n=== Regression Tests ===" -ForegroundColor Cyan

    # Test 13: REGRESSION - Marker exists but docs missing → docs SHOULD be created
    # This was the bug: marker created but docs/ was empty
    $partialInitDir = Join-Path $testRoot "partial_init_regression"
    $partialStateDir = Join-Path $partialInitDir "control\state"
    New-Item -ItemType Directory -Force -Path $partialStateDir | Out-Null
    "" | Set-Content -Path (Join-Path $partialStateDir ".mesh_initialized")
    # No docs exist yet - init should create them
    $result = Invoke-ProjectInit -Path $partialInitDir -TemplateRoot $templateRoot
    $prdPath = Join-Path $partialInitDir "docs\PRD.md"
    $specPath = Join-Path $partialInitDir "docs\SPEC.md"
    if ($result.Success -and (Test-Path $prdPath) -and (Test-Path $specPath)) {
        Pass "REGRESSION: Marker exists but docs missing → docs created"
    } else {
        Fail "REGRESSION partial init" "Docs not created despite marker existing. Success=$($result.Success), Error=$($result.Error)"
    }

    # Test 14: REGRESSION - Missing templates directory fails LOUDLY
    $badTemplateRoot = Join-Path $testRoot "nonexistent_templates"
    $noTemplateDir = Join-Path $testRoot "no_template_test"
    New-Item -ItemType Directory -Force -Path $noTemplateDir | Out-Null
    $result = Invoke-ProjectInit -Path $noTemplateDir -TemplateRoot $badTemplateRoot
    if (-not $result.Success -and $result.Error -match "Templates directory not found") {
        Pass "REGRESSION: Missing templates directory fails loudly"
    } else {
        Fail "REGRESSION missing templates" "Expected loud failure, got Success=$($result.Success), Error=$($result.Error)"
    }

    # Test 15: Verify all 6 template files are created
    $allDocsDir = Join-Path $testRoot "all_docs_test"
    New-Item -ItemType Directory -Force -Path $allDocsDir | Out-Null
    $result = Invoke-ProjectInit -Path $allDocsDir -TemplateRoot $templateRoot
    $expectedDocs = @("PRD.md", "SPEC.md", "DECISION_LOG.md", "TECH_STACK.md", "ACTIVE_SPEC.md", "INBOX.md")
    $allExist = $true
    foreach ($doc in $expectedDocs) {
        $docPath = Join-Path $allDocsDir "docs\$doc"
        if (-not (Test-Path $docPath)) {
            $allExist = $false
            break
        }
    }
    if ($result.Success -and $allExist) {
        Pass "All 6 template files created: $($expectedDocs -join ', ')"
    } else {
        $missing = $expectedDocs | Where-Object { -not (Test-Path (Join-Path $allDocsDir "docs\$_")) }
        Fail "Template files" "Missing: $($missing -join ', ')"
    }

}
finally {
    # Cleanup
    if (Test-Path $testRoot) {
        Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing, $testsPassed passing)" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS ($testsPassed tests)" -ForegroundColor Green
exit 0
