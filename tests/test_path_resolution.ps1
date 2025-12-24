#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for path resolution in snapshot system
.DESCRIPTION
    Verifies that:
    - snapshot.py receives the correct project path
    - Counts come from the correct database
    - No-DB projects return 0 counts
.NOTES
    Run: pwsh tests/test_path_resolution.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Path Resolution Tests ===" -ForegroundColor Cyan
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
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-path-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Get-SnapshotCounts($dir) {
    $result = python tools/snapshot.py $dir 2>&1 | ConvertFrom-Json
    return @{
        Pending = [int]$result.DistinctLaneCounts.pending
        Active = [int]$result.DistinctLaneCounts.active
        ProjectRoot = $result.ProjectRoot
        DbPresent = $result.DbPresent
    }
}

# ============================================================================
# Test 1: Empty directory with no DB returns 0 counts
# ============================================================================
Write-Host "Test 1: Empty directory → 0 counts" -ForegroundColor Cyan

$dir1 = New-TestDir
try {
    $counts = Get-SnapshotCounts $dir1
    if ($counts.Pending -eq 0 -and $counts.Active -eq 0 -and $counts.DbPresent -eq $false) {
        Test-Pass "Empty directory returns 0 counts"
    } else {
        Test-Fail "Empty directory returns 0 counts" "Got: pending=$($counts.Pending), active=$($counts.Active), dbPresent=$($counts.DbPresent)"
    }
} finally {
    Remove-Item -Path $dir1 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 2: Directory with tasks.db returns counts from that DB
# ============================================================================
Write-Host ""
Write-Host "Test 2: Directory with tasks.db → counts from DB" -ForegroundColor Cyan

$dir2 = New-TestDir
try {
    # Create a tasks.db with known counts
    $dbPath = Join-Path $dir2 "tasks.db"
    python -c @"
import sqlite3
conn = sqlite3.connect('$($dbPath.Replace('\', '/'))')
conn.execute('CREATE TABLE tasks (id TEXT, lane TEXT, status TEXT)')
conn.execute('INSERT INTO tasks VALUES (\"t1\", \"CORE\", \"pending\")')
conn.execute('INSERT INTO tasks VALUES (\"t2\", \"CORE\", \"pending\")')
conn.execute('INSERT INTO tasks VALUES (\"t3\", \"UI\", \"in_progress\")')
conn.commit()
conn.close()
"@

    $counts = Get-SnapshotCounts $dir2
    # DistinctLaneCounts = count of DISTINCT LANES, not tasks
    # 2 pending tasks in same lane (CORE) = 1 distinct pending lane
    # 1 active task in UI lane = 1 distinct active lane
    if ($counts.Pending -eq 1 -and $counts.Active -eq 1 -and $counts.DbPresent -eq $true) {
        Test-Pass "tasks.db counts are correct (distinct lanes)"
    } else {
        Test-Fail "tasks.db counts are correct (distinct lanes)" "Expected: pending=1, active=1. Got: pending=$($counts.Pending), active=$($counts.Active)"
    }
} finally {
    Remove-Item -Path $dir2 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 3: ProjectRoot in snapshot matches passed path
# ============================================================================
Write-Host ""
Write-Host "Test 3: ProjectRoot matches passed path" -ForegroundColor Cyan

$dir3 = New-TestDir
try {
    $counts = Get-SnapshotCounts $dir3
    $resolvedDir = (Resolve-Path $dir3).Path
    if ($counts.ProjectRoot -eq $resolvedDir) {
        Test-Pass "ProjectRoot matches passed path"
    } else {
        Test-Fail "ProjectRoot matches passed path" "Expected: $resolvedDir, Got: $($counts.ProjectRoot)"
    }
} finally {
    Remove-Item -Path $dir3 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 4: Different directories return different counts
# ============================================================================
Write-Host ""
Write-Host "Test 4: Different directories return different counts" -ForegroundColor Cyan

$dirA = New-TestDir
$dirB = New-TestDir
try {
    # Create DB in dirA with 1 pending task
    $dbPathA = Join-Path $dirA "tasks.db"
    python -c @"
import sqlite3
conn = sqlite3.connect('$($dbPathA.Replace('\', '/'))')
conn.execute('CREATE TABLE tasks (id TEXT, lane TEXT, status TEXT)')
conn.execute('INSERT INTO tasks VALUES (\"t1\", \"LANE_A\", \"pending\")')
conn.commit()
conn.close()
"@

    # Create DB in dirB with 3 pending tasks in 2 lanes
    $dbPathB = Join-Path $dirB "tasks.db"
    python -c @"
import sqlite3
conn = sqlite3.connect('$($dbPathB.Replace('\', '/'))')
conn.execute('CREATE TABLE tasks (id TEXT, lane TEXT, status TEXT)')
conn.execute('INSERT INTO tasks VALUES (\"t1\", \"LANE_B1\", \"pending\")')
conn.execute('INSERT INTO tasks VALUES (\"t2\", \"LANE_B1\", \"pending\")')
conn.execute('INSERT INTO tasks VALUES (\"t3\", \"LANE_B2\", \"pending\")')
conn.commit()
conn.close()
"@

    $countsA = Get-SnapshotCounts $dirA
    $countsB = Get-SnapshotCounts $dirB

    if ($countsA.Pending -eq 1 -and $countsB.Pending -eq 2) {
        Test-Pass "Different directories return different counts"
    } else {
        Test-Fail "Different directories return different counts" "DirA: $($countsA.Pending), DirB: $($countsB.Pending)"
    }
} finally {
    Remove-Item -Path $dirA -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $dirB -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 5: Module directory warning check (control_panel.ps1)
# ============================================================================
Write-Host ""
Write-Host "Test 5: Module directory warning in control_panel.ps1" -ForegroundColor Cyan

$content = Get-Content "$PSScriptRoot/../control_panel.ps1" -Raw
if ($content -match "WARNING.*module directory") {
    Test-Pass "control_panel.ps1 has module directory warning"
} else {
    Test-Fail "control_panel.ps1 has module directory warning" "Warning message not found"
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
