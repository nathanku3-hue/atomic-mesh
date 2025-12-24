#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for IsInitialized detection in snapshot.py
.DESCRIPTION
    Verifies the initialization contract:
    - marker-only → IsInitialized = true
    - docs 2/3 → IsInitialized = true
    - docs 1/3 → IsInitialized = false
    - empty dir → IsInitialized = false
.NOTES
    Run: pwsh tests/test_is_initialized.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== IsInitialized Detection Tests ===" -ForegroundColor Cyan
Write-Host ""

Set-Location $PSScriptRoot/..

$testsPassed = 0
$testsFailed = 0

function Test-Pass($name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
    $script:testsPassed++
}

function Test-Fail($name, $reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

function New-TestDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-init-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Get-IsInitialized($dir) {
    $result = python tools/snapshot.py $dir 2>&1 | ConvertFrom-Json
    return $result.IsInitialized
}

# ============================================================================
# Test 1: Empty directory → false
# ============================================================================
Write-Host "Test 1: Empty directory → IsInitialized = false" -ForegroundColor Cyan

$dir1 = New-TestDir
try {
    $result = Get-IsInitialized $dir1
    if ($result -eq $false) {
        Test-Pass "Empty directory → false"
    } else {
        Test-Fail "Empty directory → false" "Got: $result"
    }
} finally {
    Remove-Item -Path $dir1 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 2: Marker file only → true
# ============================================================================
Write-Host ""
Write-Host "Test 2: Marker file only → IsInitialized = true" -ForegroundColor Cyan

$dir2 = New-TestDir
try {
    # Create marker file
    $markerDir = Join-Path $dir2 "control\state"
    New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    "" | Set-Content -Path (Join-Path $markerDir ".mesh_initialized") -Encoding UTF8

    $result = Get-IsInitialized $dir2
    if ($result -eq $true) {
        Test-Pass "Marker file only → true"
    } else {
        Test-Fail "Marker file only → true" "Got: $result"
    }
} finally {
    Remove-Item -Path $dir2 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 3: 2 of 3 docs (no marker) → true
# ============================================================================
Write-Host ""
Write-Host "Test 3: 2 of 3 docs (no marker) → IsInitialized = true" -ForegroundColor Cyan

$dir3 = New-TestDir
try {
    # Create 2 docs
    $docsDir = Join-Path $dir3 "docs"
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
    "# PRD" | Set-Content -Path (Join-Path $docsDir "PRD.md") -Encoding UTF8
    "# SPEC" | Set-Content -Path (Join-Path $docsDir "SPEC.md") -Encoding UTF8

    $result = Get-IsInitialized $dir3
    if ($result -eq $true) {
        Test-Pass "2 of 3 docs → true"
    } else {
        Test-Fail "2 of 3 docs → true" "Got: $result"
    }
} finally {
    Remove-Item -Path $dir3 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 4: 1 of 3 docs (no marker) → false
# ============================================================================
Write-Host ""
Write-Host "Test 4: 1 of 3 docs (no marker) → IsInitialized = false" -ForegroundColor Cyan

$dir4 = New-TestDir
try {
    # Create only 1 doc
    $docsDir = Join-Path $dir4 "docs"
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
    "# PRD" | Set-Content -Path (Join-Path $docsDir "PRD.md") -Encoding UTF8

    $result = Get-IsInitialized $dir4
    if ($result -eq $false) {
        Test-Pass "1 of 3 docs → false"
    } else {
        Test-Fail "1 of 3 docs → false" "Got: $result"
    }
} finally {
    Remove-Item -Path $dir4 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 5: 3 of 3 docs (no marker) → true
# ============================================================================
Write-Host ""
Write-Host "Test 5: 3 of 3 docs (no marker) → IsInitialized = true" -ForegroundColor Cyan

$dir5 = New-TestDir
try {
    # Create all 3 docs
    $docsDir = Join-Path $dir5 "docs"
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
    "# PRD" | Set-Content -Path (Join-Path $docsDir "PRD.md") -Encoding UTF8
    "# SPEC" | Set-Content -Path (Join-Path $docsDir "SPEC.md") -Encoding UTF8
    "# DECISION_LOG" | Set-Content -Path (Join-Path $docsDir "DECISION_LOG.md") -Encoding UTF8

    $result = Get-IsInitialized $dir5
    if ($result -eq $true) {
        Test-Pass "3 of 3 docs → true"
    } else {
        Test-Fail "3 of 3 docs → true" "Got: $result"
    }
} finally {
    Remove-Item -Path $dir5 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 6: IsInitialized is independent of DB presence
# ============================================================================
Write-Host ""
Write-Host "Test 6: IsInitialized independent of DB" -ForegroundColor Cyan

$dir6 = New-TestDir
try {
    # Create marker (initialized) but no DB
    $markerDir = Join-Path $dir6 "control\state"
    New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    "" | Set-Content -Path (Join-Path $markerDir ".mesh_initialized") -Encoding UTF8

    $result = python tools/snapshot.py $dir6 2>&1 | ConvertFrom-Json

    $isInitialized = $result.IsInitialized
    $readinessMode = $result.ReadinessMode

    if ($isInitialized -eq $true -and $readinessMode -eq "no-db") {
        Test-Pass "IsInitialized=true with ReadinessMode=no-db"
    } else {
        Test-Fail "IsInitialized independent of DB" "IsInitialized=$isInitialized, ReadinessMode=$readinessMode"
    }
} finally {
    Remove-Item -Path $dir6 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Tests passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "============================================" -ForegroundColor Cyan

if ($testsFailed -gt 0) {
    exit 1
}
exit 0
