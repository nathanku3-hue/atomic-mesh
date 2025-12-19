#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot ".." ".." "src" "AtomicMesh.UI" "AtomicMesh.UI.psd1"
$module = Import-Module -Name $modulePath -Force -PassThru
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".." "..")).Path

$failures = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:failures++
}

# Predefined loaders
$loaderOk = { param($root) return @{ ProjectName = "X"; LaneCounts = @(); Drift = @{ HasDrift = $false; Reason = "" } } }
$loaderErr = { param($root) throw "Boom" }

# 1) Happy path
$happy = & $module {
    param($loader, $root)
    $state = [UiState]::new()
    Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader -RepoRoot $root | Out-Null
    return @{
        HasSnapshot = [bool]$state.Cache.LastSnapshot
        AdapterError = $state.Cache.LastSnapshot.AdapterError
    }
} $loaderOk $repoRoot
if ($happy.HasSnapshot -and (-not $happy.AdapterError)) {
    Pass "Happy path snapshot refresh succeeds"
} else {
    Fail "Happy path snapshot refresh succeeds" "AdapterError present or snapshot missing"
}

# 2) Error path (nonfatal)
$errorResult = & $module {
    param($loader, $root)
    $state = [UiState]::new()
    $state.Cache.LastSnapshot = [UiSnapshot]::new()
    $before = $state.Cache.LastSnapshot
    Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader -RepoRoot $root | Out-Null
    return @{
        AdapterError = $state.Cache.LastSnapshot.AdapterError
        Preserved = [object]::ReferenceEquals($before, $state.Cache.LastSnapshot)
    }
} $loaderErr $repoRoot
if ($errorResult.AdapterError -and ($errorResult.AdapterError -match "Boom")) {
    Pass "Error path sets AdapterError"
} else {
    Fail "Error path sets AdapterError" "AdapterError missing or does not mention Boom"
}
if ($errorResult.Preserved) {
    Pass "Error path preserves last snapshot"
} else {
    Fail "Error path preserves last snapshot" "Snapshot reference changed on error"
}

# 3) Recovery clears error and replaces snapshot
$recovery = & $module {
    param($errorLoader, $okLoader, $root)
    $state = [UiState]::new()
    $state.Cache.LastSnapshot = [UiSnapshot]::new()
    Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $errorLoader -RepoRoot $root | Out-Null
    $errorSnapshot = $state.Cache.LastSnapshot
    Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $okLoader -RepoRoot $root | Out-Null
    return @{
        Cleared = -not [bool]$state.Cache.LastSnapshot.AdapterError
        Replaced = -not [object]::ReferenceEquals($errorSnapshot, $state.Cache.LastSnapshot)
    }
} $loaderErr $loaderOk $repoRoot
if ($recovery.Cleared) {
    Pass "Recovery clears AdapterError"
} else {
    Fail "Recovery clears AdapterError" "AdapterError still set"
}
if ($recovery.Replaced) {
    Pass "Recovery replaces snapshot"
} else {
    Fail "Recovery replaces snapshot" "Snapshot reference did not change after recovery"
}

# 4) Volatile fields do not cause dirty/replace
$volatile = & $module {
    param($root)
    $state = [UiState]::new()
    $loader1 = { param($r) return @{ ProjectName = "X"; GeneratedAtUtc = "t1"; LaneCounts = @(); Drift = @{ HasDrift = $false; Reason = "" } } }
    $loader2 = { param($r) return @{ ProjectName = "X"; GeneratedAtUtc = "t2"; LaneCounts = @(); Drift = @{ HasDrift = $false; Reason = "" } } }
    Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader1 -RepoRoot $root | Out-Null
    $first = $state.Cache.LastSnapshot
    $firstHash = $state.LastSnapshotHash
    Invoke-DataRefreshTick -State $state -DataIntervalMs 0 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $loader2 -RepoRoot $root | Out-Null
    return @{
        SameRef = [object]::ReferenceEquals($first, $state.Cache.LastSnapshot)
        SameHash = ($firstHash -eq $state.LastSnapshotHash)
    }
} $repoRoot
if ($volatile.SameRef -and $volatile.SameHash) {
    Pass "Volatile field changes do not replace snapshot"
} else {
    Fail "Volatile field changes do not replace snapshot" "Snapshot or hash changed on timestamp-only update"
}

if ($failures -gt 0) {
    exit 1
}

Write-Host "Integration data loop tests passed" -ForegroundColor Green
