#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Table-driven tests for command guards (Test-CanDraftPlan, Test-CanAcceptPlan, Test-CanGo)
.DESCRIPTION
    Verifies the guard matrix using snapshot readiness fields only (IsInitialized,
    BlockingFiles, ReadinessMode, DocsAllPassed).
#>

$ErrorActionPreference = "Stop"

# Load the guards directly (they're private, so not exported from module)
$guardsPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Guards" "CommandGuards.ps1"
. $guardsPath

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

function New-TestSnapshot {
    param(
        [string]$Status = "",
        [bool]$HasDraft = $false,
        [bool]$Accepted = $false,
        [bool]$IsInitialized = $false,
        [string[]]$BlockingFiles = @(),
        [string]$ReadinessMode = "live",
        [bool]$DocsAllPassed = $false
    )
    # Use PSCustomObject to avoid class scope issues in tests
    $planState = [PSCustomObject]@{
        Status = $Status
        HasDraft = $HasDraft
        Accepted = $Accepted
        PlanId = ""
        Summary = ""
        NextHint = ""
    }
    $snapshot = [PSCustomObject]@{
        PlanState = $planState
        IsInitialized = $IsInitialized
        BlockingFiles = $BlockingFiles
        ReadinessMode = $ReadinessMode
        DocsAllPassed = $DocsAllPassed
    }
    return $snapshot
}

function New-TestState {
    param()
    # Minimal state; guards only rely on snapshot now
    $metadata = @{}
    $metadata | Add-Member -MemberType ScriptMethod -Name "ContainsKey" -Value {
        param($key)
        return $this.Keys -contains $key
    } -Force
    $cache = [PSCustomObject]@{ Metadata = $metadata }
    return [PSCustomObject]@{ Cache = $cache }
}

# =============================================================================
# Test Matrix for Test-CanDraftPlan
# =============================================================================
Write-Host "`n=== Test-CanDraftPlan ===" -ForegroundColor Cyan

$draftPlanTests = @(
    # Not initialized
    @{ Status = "DRAFT"; IsInit = $false; BlockFiles=@(); Readiness="live"; DocsPass=$false; Expected = $false; Message = "Run /init first" },
    # Blocking files present
    @{ Status = "DRAFT"; IsInit = $true;  BlockFiles=@("PRD","README"); Readiness="live"; DocsPass=$false; Expected = $false; Message = "BLOCKED: Complete these docs first: PRD" },
    # fail-open without docs passed
    @{ Status = "DRAFT"; IsInit = $true;  BlockFiles=@(); Readiness="fail-open"; DocsPass=$false; Expected = $false; Message = "BLOCKED: Complete docs first" },
    # All clear
    @{ Status = "DRAFT"; IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $true; Message = "" }
)

foreach ($test in $draftPlanTests) {
    $snapshot = New-TestSnapshot -Status $test.Status -IsInitialized $test.IsInit -BlockingFiles $test.BlockFiles -ReadinessMode $test.Readiness -DocsAllPassed $test.DocsPass
    $state = New-TestState
    $result = Test-CanDraftPlan -Snapshot $snapshot -State $state
    $testName = "DraftPlan: IsInit=$($test.IsInit) BlockFiles=$($test.BlockFiles -join ',') Mode=$($test.Readiness) DocsPass=$($test.DocsPass)"

    if ($result.Ok -eq $test.Expected) {
        if (-not $test.Expected -and $test.Message -and $result.Message -notlike "$($test.Message)*") {
            Fail $testName "Expected message containing '$($test.Message)', got '$($result.Message)'"
        } else {
            Pass $testName
        }
    } else {
        Fail $testName "Expected Ok=$($test.Expected), got Ok=$($result.Ok)"
    }
}

# =============================================================================
# Test Matrix for Test-CanAcceptPlan
# =============================================================================
Write-Host "`n=== Test-CanAcceptPlan ===" -ForegroundColor Cyan

$acceptPlanTests = @(
    # Readiness blocked
    @{ Status = "DRAFT";     HasDraft = $true;  IsInit = $false; BlockFiles=@(); Readiness="live"; DocsPass=$false; Expected = $false; Message = "Run /init first" },
    @{ Status = "DRAFT";     HasDraft = $true;  IsInit = $true;  BlockFiles=@("SPEC"); Readiness="live"; DocsPass=$false; Expected = $false; Message = "BLOCKED: Complete these docs first: SPEC" },
    @{ Status = "DRAFT";     HasDraft = $true;  IsInit = $true;  BlockFiles=@(); Readiness="fail-open"; DocsPass=$false; Expected = $false; Message = "BLOCKED: Complete docs first" },
    # No draft
    @{ Status = "DRAFT";     HasDraft = $false; IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $false; Message = "Run /draft-plan first" },
    # Already accepted
    @{ Status = "ACCEPTED";  HasDraft = $true;  IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $false; Message = "Plan already accepted" },
    # OK
    @{ Status = "DRAFT";     HasDraft = $true;  IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $true;  Message = "" }
)

foreach ($test in $acceptPlanTests) {
    $snapshot = New-TestSnapshot -Status $test.Status -HasDraft $test.HasDraft -IsInitialized $test.IsInit -BlockingFiles $test.BlockFiles -ReadinessMode $test.Readiness -DocsAllPassed $test.DocsPass
    $state = New-TestState
    $result = Test-CanAcceptPlan -Snapshot $snapshot -State $state
    $testName = "AcceptPlan: $($test.Status) HasDraft=$($test.HasDraft) IsInit=$($test.IsInit)"

    if ($result.Ok -eq $test.Expected) {
        if (-not $test.Expected -and $test.Message -and $result.Message -ne $test.Message) {
            Fail $testName "Expected message '$($test.Message)', got '$($result.Message)'"
        } else {
            Pass $testName
        }
    } else {
        Fail $testName "Expected Ok=$($test.Expected), got Ok=$($result.Ok)"
    }
}

# =============================================================================
# Test Matrix for Test-CanGo
# =============================================================================
Write-Host "`n=== Test-CanGo ===" -ForegroundColor Cyan

$goTests = @(
    # Readiness blocked
    @{ Status = "ACCEPTED";  IsInit = $false; BlockFiles=@(); Readiness="live"; DocsPass=$false; Expected = $false; Message = "Run /init first" },
    @{ Status = "ACCEPTED";  IsInit = $true;  BlockFiles=@("DECISION_LOG"); Readiness="live"; DocsPass=$false; Expected = $false; Message = "BLOCKED: Complete these docs first: DECISION_LOG" },
    @{ Status = "ACCEPTED";  IsInit = $true;  BlockFiles=@(); Readiness="fail-open"; DocsPass=$false; Expected = $false; Message = "BLOCKED: Complete docs first" },
    # Not accepted
    @{ Status = "DRAFT";     IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $false; Message = "Run /accept-plan first" },
    # OK
    @{ Status = "ACCEPTED";  IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $true;  Message = "" },
    @{ Status = "RUNNING";   IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $true;  Message = "" },
    @{ Status = "COMPLETED"; IsInit = $true;  BlockFiles=@(); Readiness="live"; DocsPass=$true; Expected = $true;  Message = "" }
)

foreach ($test in $goTests) {
    $snapshot = New-TestSnapshot -Status $test.Status -IsInitialized $test.IsInit -BlockingFiles $test.BlockFiles -ReadinessMode $test.Readiness -DocsAllPassed $test.DocsPass
    $state = New-TestState
    $result = Test-CanGo -Snapshot $snapshot -State $state
    $testName = "Go: $($test.Status) IsInit=$($test.IsInit) -> $(if ($test.Expected) { 'OK' } else { 'BLOCKED' })"

    if ($result.Ok -eq $test.Expected) {
        if (-not $test.Expected -and $test.Message -and $result.Message -notlike "$($test.Message)*") {
            Fail $testName "Expected message containing '$($test.Message)', got '$($result.Message)'"
        } else {
            Pass $testName
        }
    } else {
        Fail $testName "Expected Ok=$($test.Expected), got Ok=$($result.Ok)"
    }
}

# =============================================================================
# Edge case: null snapshot / null state
# =============================================================================
Write-Host "`n=== Edge Cases ===" -ForegroundColor Cyan

# Null snapshot, null state -> should block (not initialized)
$nullResult = Test-CanDraftPlan -Snapshot $null -State $null
if (-not $nullResult.Ok) {
    Pass "DraftPlan: null snapshot/state -> BLOCKED"
} else {
    Fail "DraftPlan: null snapshot/state" "Should block with null snapshot/state"
}

$nullResult = Test-CanAcceptPlan -Snapshot $null -State $null
if (-not $nullResult.Ok) {
    Pass "AcceptPlan: null snapshot/state -> BLOCKED"
} else {
    Fail "AcceptPlan: null snapshot/state" "Should block with null snapshot/state"
}

$nullResult = Test-CanGo -Snapshot $null -State $null
if (-not $nullResult.Ok) {
    Pass "Go: null snapshot/state -> BLOCKED"
} else {
    Fail "Go: null snapshot/state" "Should block with null snapshot/state"
}

# =============================================================================
# Regression: readiness overrides status
# =============================================================================
Write-Host "`n=== Regression: readiness overrides status ===" -ForegroundColor Cyan

# fail-open without docs should block even if status looks OK
$snapshot = New-TestSnapshot -Status "DRAFT" -IsInitialized $true -ReadinessMode "fail-open" -DocsAllPassed $false
$state = New-TestState
$result = Test-CanDraftPlan -Snapshot $snapshot -State $state
if (-not $result.Ok -and $result.Message -like "BLOCKED:*") {
    Pass "REGRESSION: fail-open without docs blocks draft-plan"
} else {
    Fail "REGRESSION: fail-open without docs" "Should block draft-plan when docs not passed"
}

# =============================================================================
# Guard return structure validation
# =============================================================================
Write-Host "`n=== Return Structure ===" -ForegroundColor Cyan

$snapshot = New-TestSnapshot -Status "DRAFT" -HasDraft $true -IsInitialized $true
$state = New-TestState
$result = Test-CanAcceptPlan -Snapshot $snapshot -State $state

if ($result.ContainsKey("Ok") -and $result.ContainsKey("Message") -and
    $result.ContainsKey("Severity") -and $result.ContainsKey("DurationSec")) {
    Pass "Guard returns uniform structure (Ok, Message, Severity, DurationSec)"
} else {
    Fail "Guard return structure" "Missing required keys in result"
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
