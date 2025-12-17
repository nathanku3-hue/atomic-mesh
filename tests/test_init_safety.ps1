# Test: /init safety - must NOT suggest init when repo is initialized
# Acceptance: "First time here? Type /init" must NOT appear when Test-RepoInitialized().initialized is true
#
# Run: pwsh tests/test_init_safety.ps1

param([switch]$Verbose)

$ErrorActionPreference = "Stop"
$testsPassed = 0
$testsFailed = 0

function Write-TestResult($name, $passed, $detail = "") {
    if ($passed) {
        Write-Host "  [PASS] $name" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "  [FAIL] $name" -ForegroundColor Red
        if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
        $script:testsFailed++
    }
}

Write-Host "`n=== /init Safety Tests ===" -ForegroundColor Cyan

# Setup: Get paths
$scriptDir = Split-Path -Parent $PSScriptRoot
$cpPath = Join-Path $scriptDir "control_panel.ps1"

# Extract Test-RepoInitialized function from control_panel.ps1
$cpContent = Get-Content $cpPath -Raw

# Find the function start
$funcStart = $cpContent.IndexOf("function Test-RepoInitialized {")
if ($funcStart -eq -1) {
    Write-Host "  [FAIL] Could not find Test-RepoInitialized function" -ForegroundColor Red
    exit 1
}

# Find matching closing brace by counting
$braceCount = 0
$funcEnd = $funcStart
$inFunc = $false
$chars = $cpContent.ToCharArray()
for ($i = $funcStart; $i -lt $chars.Length; $i++) {
    $char = $chars[$i]
    if ($char -eq '{') {
        $braceCount++
        $inFunc = $true
    }
    elseif ($char -eq '}') {
        $braceCount--
        if ($inFunc -and $braceCount -eq 0) {
            $funcEnd = $i + 1
            break
        }
    }
}

$funcCode = $cpContent.Substring($funcStart, $funcEnd - $funcStart)

# Set up globals needed by the function
$Global:RepoRoot = $scriptDir
$Global:CurrentDir = $scriptDir

# Load the function
try {
    Invoke-Expression $funcCode
    Write-TestResult "Test-RepoInitialized function loaded" $true
}
catch {
    Write-Host "  [FAIL] Could not load Test-RepoInitialized: $_" -ForegroundColor Red
    exit 1
}

# Test 1: Fresh folder (no docs) -> not initialized
$freshDir = New-Item -ItemType Directory -Path "$env:TEMP\test_init_fresh_$(Get-Random)" -Force
$Global:CurrentDir = $freshDir.FullName
$result = Test-RepoInitialized -Path $freshDir.FullName
Write-TestResult "Fresh folder detected as NOT initialized" (-not $result.initialized) `
    "Got: initialized=$($result.initialized), reason=$($result.reason)"
Remove-Item -Recurse -Force $freshDir

# Test 2: Folder with 2/3 golden docs -> initialized (backward compat)
$legacyDir = New-Item -ItemType Directory -Path "$env:TEMP\test_init_legacy_$(Get-Random)" -Force
$docsDir = New-Item -ItemType Directory -Path "$legacyDir\docs" -Force
"# PRD" | Out-File "$docsDir\PRD.md"
"# SPEC" | Out-File "$docsDir\SPEC.md"
$Global:CurrentDir = $legacyDir.FullName
$result = Test-RepoInitialized -Path $legacyDir.FullName
Write-TestResult "Legacy repo (2/3 docs) detected as initialized" $result.initialized `
    "Got: initialized=$($result.initialized), reason=$($result.reason)"
Write-TestResult "Legacy detection reason is 'golden_docs'" ($result.reason -eq "golden_docs") `
    "Got reason: $($result.reason)"
Remove-Item -Recurse -Force $legacyDir

# Test 3: Folder with only 1/3 golden docs -> NOT initialized
$partialDir = New-Item -ItemType Directory -Path "$env:TEMP\test_init_partial_$(Get-Random)" -Force
$docsDir = New-Item -ItemType Directory -Path "$partialDir\docs" -Force
"# PRD only" | Out-File "$docsDir\PRD.md"
$Global:CurrentDir = $partialDir.FullName
$result = Test-RepoInitialized -Path $partialDir.FullName
Write-TestResult "Partial docs (1/3) detected as NOT initialized" (-not $result.initialized) `
    "Got: initialized=$($result.initialized), reason=$($result.reason)"
Remove-Item -Recurse -Force $partialDir

# Test 4: Result object has expected shape
$testDir = New-Item -ItemType Directory -Path "$env:TEMP\test_init_shape_$(Get-Random)" -Force
$Global:CurrentDir = $testDir.FullName
$result = Test-RepoInitialized -Path $testDir.FullName
$hasInitialized = $null -ne $result.initialized
$hasReason = $null -ne $result.reason
$hasDetails = $null -ne $result.details
Write-TestResult "Result has 'initialized' property" $hasInitialized
Write-TestResult "Result has 'reason' property" $hasReason
Write-TestResult "Result has 'details' property" $hasDetails
Remove-Item -Recurse -Force $testDir

# Test 5: Verify footer hint is guarded by init check
$footerPattern = 'First time here\? Type /init'
$footerCode = Select-String -Path $cpPath -Pattern $footerPattern -Context 10,0
if ($footerCode) {
    $contextLines = $footerCode.Context.PreContext -join "`n"
    $usesInitCheck = $contextLines -match 'initStatus\.initialized'
    Write-TestResult "Footer hint guarded by initStatus.initialized" $usesInitCheck `
        "Footer should check initialization status before showing /init hint"
} else {
    Write-TestResult "Footer hint pattern exists in code" $false "Could not find footer hint"
}

# Test 6: Verify /init handler has protection
$initPattern = '"init" \{'
$initCode = Select-String -Path $cpPath -Pattern $initPattern -Context 0,25
if ($initCode) {
    $contextLines = $initCode.Line + "`n" + ($initCode.Context.PostContext -join "`n")
    $hasForceCheck = $contextLines -match '--force'
    $hasAbortMessage = $contextLines -match 'REPO ALREADY INITIALIZED|Aborting'
    Write-TestResult "/init handler checks for --force flag" $hasForceCheck
    Write-TestResult "/init handler has abort message for re-init" $hasAbortMessage
} else {
    Write-TestResult "/init handler found in code" $false "Could not find /init handler"
}

# Summary
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

if ($testsFailed -gt 0) {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Yellow
}

exit $testsFailed
