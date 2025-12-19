#!/usr/bin/env pwsh
# Regression tests for dirty-driven rendering (prevents perma-dirty flicker)
$ErrorActionPreference = "Stop"

$modulePath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "src") "AtomicMesh.UI") "AtomicMesh.UI.psd1"
$module = Import-Module -Name $modulePath -Force -PassThru

$failures = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:failures++
}

# Test 1: Same snapshot returns same hash (perma-dirty guard)
$hashTest = & $module {
    $snap1 = [UiSnapshot]::new()
    $snap1.PlanState.Status = "DRAFT"
    $snap1.PlanState.HasDraft = $true

    $snap2 = [UiSnapshot]::new()
    $snap2.PlanState.Status = "DRAFT"
    $snap2.PlanState.HasDraft = $true

    $hash1 = Get-SnapshotHash -Snapshot $snap1
    $hash2 = Get-SnapshotHash -Snapshot $snap2
    return @{ Hash1 = $hash1; Hash2 = $hash2; Equal = ($hash1 -eq $hash2) }
}
if ($hashTest.Equal) {
    Pass "Same snapshot returns same hash"
}
else {
    Fail "Same snapshot returns same hash" "Hash1=$($hashTest.Hash1), Hash2=$($hashTest.Hash2)"
}

# Test 2: Different snapshot returns different hash
$diffHashTest = & $module {
    $snap1 = [UiSnapshot]::new()
    $snap1.PlanState.Status = "DRAFT"

    $snap2 = [UiSnapshot]::new()
    $snap2.PlanState.Status = "ACCEPTED"

    $hash1 = Get-SnapshotHash -Snapshot $snap1
    $hash2 = Get-SnapshotHash -Snapshot $snap2
    return @{ Equal = ($hash1 -eq $hash2) }
}
if (-not $diffHashTest.Equal) {
    Pass "Different snapshot returns different hash"
}
else {
    Fail "Different snapshot returns different hash" "Hashes should differ but were equal"
}

# Test 3: UiState dirty flag works correctly
$dirtyTest = & $module {
    $state = [UiState]::new()
    $initialDirty = $state.IsDirty
    $initialReason = $state.DirtyReason

    $state.ClearDirty()
    $clearedDirty = $state.IsDirty

    $state.MarkDirty("test")
    $markedDirty = $state.IsDirty
    $markedReason = $state.DirtyReason

    return @{
        InitialDirty = $initialDirty
        InitialReason = $initialReason
        ClearedDirty = $clearedDirty
        MarkedDirty = $markedDirty
        MarkedReason = $markedReason
    }
}
if ($dirtyTest.InitialDirty -and $dirtyTest.InitialReason -eq "init" -and
    -not $dirtyTest.ClearedDirty -and
    $dirtyTest.MarkedDirty -and $dirtyTest.MarkedReason -eq "test") {
    Pass "UiState dirty flag lifecycle works"
}
else {
    Fail "UiState dirty flag lifecycle works" "InitialDirty=$($dirtyTest.InitialDirty), Cleared=$($dirtyTest.ClearedDirty), Marked=$($dirtyTest.MarkedDirty)"
}

# Test 4: Invoke-DataRefreshTick only marks dirty on data change
$dataTickTest = & $module {
    $state = [UiState]::new()
    $state.ClearDirty()
    $state.AutoRefreshEnabled = $true

    # First tick - should mark dirty because snapshot is new
    $loader = { param($root)
        @{
            LaneCounts = @(
                @{ Lane = "BACKEND"; Status = "QUEUED"; Count = 1 }
            )
        }
    }

    $snap1 = Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader -RepoRoot "."
    $dirtyAfterFirst = $state.IsDirty
    $hashAfterFirst = $state.LastSnapshotHash

    $state.ClearDirty()

    # Second tick with same data - should NOT mark dirty
    $state.LastDataRefreshUtc = [datetime]::MinValue  # force refresh
    $snap2 = Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader -RepoRoot "."
    $dirtyAfterSecond = $state.IsDirty

    return @{
        DirtyAfterFirst = $dirtyAfterFirst
        DirtyAfterSecond = $dirtyAfterSecond
    }
}
if ($dataTickTest.DirtyAfterFirst -and -not $dataTickTest.DirtyAfterSecond) {
    Pass "Data tick only marks dirty on actual change"
}
else {
    Fail "Data tick only marks dirty on actual change" "First=$($dataTickTest.DirtyAfterFirst), Second=$($dataTickTest.DirtyAfterSecond)"
}

# Test 5: AutoRefreshEnabled gate works
$autoRefreshTest = & $module {
    $state = [UiState]::new()
    $state.ClearDirty()
    $state.AutoRefreshEnabled = $false

    $loader = { param($root)
        @{
            LaneCounts = @(
                @{ Lane = "CHANGED"; Status = "QUEUED"; Count = 99 }
            )
        }
    }

    $snap = Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader -RepoRoot "."
    return @{
        IsDirty = $state.IsDirty
        DataRefreshes = $state.DataRefreshes
    }
}
if (-not $autoRefreshTest.IsDirty -and $autoRefreshTest.DataRefreshes -eq 0) {
    Pass "AutoRefreshEnabled=false blocks data refresh"
}
else {
    Fail "AutoRefreshEnabled=false blocks data refresh" "IsDirty=$($autoRefreshTest.IsDirty), Refreshes=$($autoRefreshTest.DataRefreshes)"
}

# Test 6: Volatile fields (GeneratedAtUtc) are excluded from signature
$volatileTest = & $module {
    $raw1 = @{
        GeneratedAtUtc = "2024-01-01T00:00:00Z"
        LaneCounts = @(@{ Lane = "BACKEND"; Status = "QUEUED"; Count = 1 })
    }
    $raw2 = @{
        GeneratedAtUtc = "2024-12-31T23:59:59Z"
        LaneCounts = @(@{ Lane = "BACKEND"; Status = "QUEUED"; Count = 1 })
    }
    $sig1 = Get-SnapshotSignature -RawSnapshot $raw1
    $sig2 = Get-SnapshotSignature -RawSnapshot $raw2
    return @{ Equal = ($sig1 -eq $sig2) }
}
if ($volatileTest.Equal) {
    Pass "Volatile field GeneratedAtUtc excluded from signature"
}
else {
    Fail "Volatile field GeneratedAtUtc excluded from signature" "Signatures differ despite only timestamp change"
}

# Test 7: Resize marks dirty
$resizeTest = & $module {
    $state = [UiState]::new()
    $state.ClearDirty()
    $state.LastWidth = 80
    $state.LastHeight = 24

    # Simulate resize by checking if width/height changed
    $newWidth = 100
    $newHeight = 30
    if ($newWidth -ne $state.LastWidth -or $newHeight -ne $state.LastHeight) {
        $state.LastWidth = $newWidth
        $state.LastHeight = $newHeight
        $state.MarkDirty("resize")
    }

    return @{
        IsDirty = $state.IsDirty
        DirtyReason = $state.DirtyReason
    }
}
if ($resizeTest.IsDirty -and $resizeTest.DirtyReason -eq "resize") {
    Pass "Resize marks dirty"
}
else {
    Fail "Resize marks dirty" "IsDirty=$($resizeTest.IsDirty), Reason=$($resizeTest.DirtyReason)"
}

# Test 8: Error normalization prevents perma-dirty on identical errors
$errorNormTest = & $module {
    $err1 = Normalize-AdapterError -Message "Error: connection failed`r`nDetails: timeout"
    $err2 = Normalize-AdapterError -Message "Error: connection failed`r`nDetails: timeout"
    return @{ Equal = ($err1 -eq $err2); Normalized = $err1 }
}
if ($errorNormTest.Equal -and $errorNormTest.Normalized -notmatch "`r`n") {
    Pass "Error normalization produces consistent single-line output"
}
else {
    Fail "Error normalization produces consistent single-line output" "Normalized=$($errorNormTest.Normalized)"
}

if ($failures -gt 0) {
    exit 1
}

Write-Host "All dirty-rendering regression tests passed" -ForegroundColor Green
