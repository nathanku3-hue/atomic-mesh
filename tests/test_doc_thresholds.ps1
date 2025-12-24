#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for doc readiness thresholds
.DESCRIPTION
    Verifies threshold behavior:
    - PRD/SPEC threshold = 90%
    - DECISION_LOG threshold = 60%
    - Hints reflect ready/not-ready correctly
.NOTES
    Run: pwsh tests/test_doc_thresholds.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Doc Threshold Tests ===" -ForegroundColor Cyan
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

function Get-ReadinessData($dir) {
    $result = python tools/readiness.py $dir 2>&1 | ConvertFrom-Json
    return $result
}

# ============================================================================
# Test 1: Verify thresholds are correct
# ============================================================================
Write-Host "Test 1: Thresholds are PRD=90, SPEC=90, DEC=60" -ForegroundColor Cyan

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-thresh-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $result = Get-ReadinessData $tempDir
    $prdThresh = $result.thresholds.PRD
    $specThresh = $result.thresholds.SPEC
    $decThresh = $result.thresholds.DECISION_LOG

    if ($prdThresh -eq 90 -and $specThresh -eq 90 -and $decThresh -eq 60) {
        Test-Pass "Thresholds are PRD=90, SPEC=90, DEC=60"
    } else {
        Test-Fail "Thresholds are PRD=90, SPEC=90, DEC=60" "Got: PRD=$prdThresh, SPEC=$specThresh, DEC=$decThresh"
    }
} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 2: DEC at 50% (below 60% threshold) shows not-ready hint
# ============================================================================
Write-Host ""
Write-Host "Test 2: DEC at 50% shows non-ready hint" -ForegroundColor Cyan

# Use E:\Code\new which has DEC at 50%
if (Test-Path "E:\Code\new") {
    $result = Get-ReadinessData "E:\Code\new"
    $decScore = $result.files.DECISION_LOG.score
    $decHint = $result.files.DECISION_LOG.hint

    if ($decScore -lt 60 -and $decHint -ne "ready") {
        Test-Pass "DEC at $decScore% (below 60%) hint='$decHint' (not ready)"
    } else {
        Test-Fail "DEC at 50% shows non-ready hint" "score=$decScore, hint=$decHint"
    }
} else {
    Write-Host "[SKIP] E:\Code\new not found" -ForegroundColor Gray
}

# ============================================================================
# Test 3: DEC at 60%+ shows ready hint
# ============================================================================
Write-Host ""
Write-Host "Test 3: DEC at 60%+ shows ready hint" -ForegroundColor Cyan

$tempDir3 = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-thresh-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir3 -Force | Out-Null
try {
    # Create docs dir with DECISION_LOG that scores 60%+
    $docsDir = Join-Path $tempDir3 "docs"
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null

    # Create DECISION_LOG with enough content to score 60%+
    # Must NOT have ATOMIC_MESH_TEMPLATE_STUB marker to avoid stub capping
    # Score: exists(10) + Records header(10) + words>150(20) + bullets>5(20) = 60%
    $decContent = @"
# Decision Log

This document tracks all architectural and design decisions for the project.
Each decision includes context, rationale, and approval status.

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2024-01-15 | ARCH | Use SQLite for local storage | Simple, no server needed, good for single-user apps | Core | T-001 | APPROVED |
| 002 | 2024-01-16 | API | REST endpoints for task management | Standard pattern that is easy to test and document | Core | T-002 | APPROVED |
| 003 | 2024-01-17 | DATA | JSON format for configuration files | Human readable format that is easy to edit manually | Config | T-003 | APPROVED |
| 004 | 2024-01-18 | SECURITY | Token-based authentication for API access | Industry standard approach that is stateless | Auth | T-004 | APPROVED |
| 005 | 2024-01-19 | UX | CLI-first interface design | Target audience strongly prefers terminal workflows | UI | T-005 | APPROVED |

## Guidelines

When adding new decisions, follow these steps:
- Document the context and problem being solved
- List alternatives that were considered
- Explain the rationale for the chosen approach
- Get approval from relevant stakeholders
- Update the status when implemented
- Include links to related documentation

## History

This log was created to ensure traceability and help new team members understand
the reasoning behind architectural choices. All major decisions should be recorded
here before implementation begins.
"@
    Set-Content -Path (Join-Path $docsDir "DECISION_LOG.md") -Value $decContent -Encoding UTF8

    $result = Get-ReadinessData $tempDir3
    $decScore = $result.files.DECISION_LOG.score
    $decHint = $result.files.DECISION_LOG.hint

    if ($decScore -ge 60 -and $decHint -eq "ready") {
        Test-Pass "DEC at $decScore% (>=60%) hint='ready'"
    } else {
        Test-Fail "DEC at 60%+ shows ready hint" "score=$decScore, hint=$decHint"
    }
} finally {
    Remove-Item -Path $tempDir3 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 4: SPEC at 89% (below 90% threshold) shows not-ready hint
# ============================================================================
Write-Host ""
Write-Host "Test 4: PRD/SPEC need 90% to be ready" -ForegroundColor Cyan

$tempDir4 = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-thresh-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir4 -Force | Out-Null
try {
    # Create docs dir with PRD that scores ~80% (below 90%)
    $docsDir = Join-Path $tempDir4 "docs"
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null

    # PRD with headers but limited content (exists=10 + 3 headers=30 + words>150=20 + bullets>5=20 = 80%)
    $prdContent = @"
# Product Requirements Document

## Goals

The primary goal of this project is to build a task management system.
We want to help users organize their work efficiently.
The system should be simple and fast.

## User Stories

- As a user, I want to create tasks so I can track my work
- As a user, I want to mark tasks complete so I know what's done
- As a user, I want to filter tasks by status
- As a user, I want to search tasks by name
- As a user, I want to set priorities
- As a user, I want to add notes

## Success Metrics

- User can create 100 tasks in under 1 minute
- Search returns results in under 100ms
- System handles 10,000 tasks without slowdown

This document defines the product requirements for the task management system.
"@
    Set-Content -Path (Join-Path $docsDir "PRD.md") -Value $prdContent -Encoding UTF8

    $result = Get-ReadinessData $tempDir4
    $prdScore = $result.files.PRD.score
    $prdHint = $result.files.PRD.hint

    # PRD should be below 90% and not show "ready"
    if ($prdScore -lt 90 -and $prdHint -ne "ready") {
        Test-Pass "PRD at $prdScore% (below 90%) hint='$prdHint' (not ready)"
    } elseif ($prdScore -ge 90 -and $prdHint -eq "ready") {
        Test-Pass "PRD at $prdScore% (>=90%) hint='ready'"
    } else {
        Test-Fail "PRD/SPEC need 90% to be ready" "score=$prdScore, hint=$prdHint"
    }
} finally {
    Remove-Item -Path $tempDir4 -Recurse -Force -ErrorAction SilentlyContinue
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
