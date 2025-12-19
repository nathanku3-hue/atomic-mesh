#!/usr/bin/env pwsh
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

# Test: constructors avoid I/O (static scan on Models)
$forbiddenTokens = @("Get-Content", "Invoke-WebRequest", "python", "sqlite3", "git ")
$modelDir = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "src") "AtomicMesh.UI") "Private") "Models"
foreach ($file in Get-ChildItem -Path $modelDir -Filter "*.ps1") {
    $content = Get-Content -Path $file.FullName -Raw
    $hit = $false
    foreach ($token in $forbiddenTokens) {
        if ($content -match [regex]::Escape($token)) {
            $hit = $true
            break
        }
    }
    if ($hit) {
        Fail "Model constructors avoid I/O" "Forbidden token found in $($file.Name)"
    }
}
if ($failures -eq 0) { Pass "Model constructors avoid I/O" }

# Test: instantiation succeeds
$instantiationResult = $null
try {
    $instantiationResult = & $module {
        [UiState]::new() | Out-Null
        [UiSnapshot]::new() | Out-Null
        return $true
    }
}
catch {
    $instantiationResult = $false
}
if ($instantiationResult) {
    Pass "Model instantiation works"
}
else {
    Fail "Model instantiation works" "Unable to instantiate UiState/UiSnapshot"
}

# Test: TrySetPos returns false on out-of-range
$cursorResult = & $module {
    Begin-ConsoleFrame
    TrySetPos -Row 999999 -Col 0
}
if (-not $cursorResult) {
    Pass "TrySetPos returns false on out-of-range"
}
else {
    Fail "TrySetPos returns false on out-of-range" "Expected false for large row value"
}

# Test: data loop gate prevents refresh every render tick
$early = & $module {
    $t0 = [datetime]::UtcNow
    Get-IsDataRefreshDue -LastRefresh $t0 -IntervalMs 500 -NowUtc ($t0.AddMilliseconds(100))
}
$late = & $module {
    $t0 = [datetime]::UtcNow
    Get-IsDataRefreshDue -LastRefresh $t0 -IntervalMs 500 -NowUtc ($t0.AddMilliseconds(600))
}
if (-not $early) {
    Pass "Data tick gate blocks early refresh"
}
else {
    Fail "Data tick gate blocks early refresh" "Returned true before interval elapsed"
}
if ($late) {
    Pass "Data tick gate allows refresh after interval"
}
else {
    Fail "Data tick gate allows refresh after interval" "Returned false after interval elapsed"
}

# Test: adapter error banner path is nonfatal (frame may skip but no crash)
try {
    $adapterErrorFrameOk = & $module {
        Begin-ConsoleFrame
        $snap = [UiSnapshot]::new()
        $snap.AdapterError = "sample error"
        Render-Go -Snapshot $snap -State ([UiState]::new())
        End-ConsoleFrame
    }
    Pass "Adapter error banner renders without crashing"
}
catch {
    Fail "Adapter error banner renders without crashing" $_.Exception.Message
}

if ($failures -gt 0) {
    exit 1
}

Write-Host "All AtomicMesh.UI basic tests passed" -ForegroundColor Green
