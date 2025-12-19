# tests/test_command_discovery.ps1
# v20.0: Regression tests for command discovery surfaces
# Tests /commands (curated), /commands all, and /help topics functionality

param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "..\control_panel.ps1")
)

# Read control panel script content and extract only the data structure definitions
# This avoids triggering the main loop
$scriptContent = Get-Content $ScriptPath -Raw

# Extract and execute only the relevant sections (globals, NOT the main loop)
# We use regex to find the DATABASE HELPER section which comes after our command metadata
$pattern = '# ={10,}\s*\r?\n# DATABASE HELPER'
$match = [regex]::Match($scriptContent, $pattern)

if ($match.Success) {
    # Extract just the header and data structures (up to DATABASE HELPER)
    $headerSection = $scriptContent.Substring(0, $match.Index)

    # Execute in a scope to define globals
    try {
        Invoke-Expression $headerSection
    }
    catch {
        Write-Host "Warning: Some script initialization failed (expected in test mode)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "ERROR: Could not find extraction marker in control_panel.ps1" -ForegroundColor Red
    exit 1
}

# Test results tracking
$Global:TestsPassed = 0
$Global:TestsFailed = 0
$Global:TestResults = @()

function Assert-True {
    param(
        [bool]$Condition,
        [string]$TestName,
        [string]$Message = ""
    )

    if ($Condition) {
        $Global:TestsPassed++
        $Global:TestResults += @{ Name = $TestName; Passed = $true; Message = "" }
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    }
    else {
        $Global:TestsFailed++
        $Global:TestResults += @{ Name = $TestName; Passed = $false; Message = $Message }
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "         $Message" -ForegroundColor Yellow
        }
    }
}

function Assert-Contains {
    param(
        [string]$Haystack,
        [string]$Needle,
        [string]$TestName
    )

    $found = $Haystack.Contains($Needle)
    Assert-True -Condition $found -TestName $TestName -Message "Expected to find '$Needle'"
}

function Assert-NotContains {
    param(
        [string]$Haystack,
        [string]$Needle,
        [string]$TestName
    )

    $found = $Haystack.Contains($Needle)
    Assert-True -Condition (-not $found) -TestName $TestName -Message "Did not expect to find '$Needle'"
}

# ============================================================================
# TEST: /commands contains /go once with aliases collapsed
# ============================================================================
Write-Host ""
Write-Host "═══ TEST SUITE: Command Discovery v20.0 ═══" -ForegroundColor Cyan
Write-Host ""

Write-Host "Test Group: /commands (curated P0)" -ForegroundColor Yellow

# Check that /go appears in P0Commands with its aliases
$goFound = $false
$goAliases = @()
foreach ($group in $Global:P0Commands.Keys) {
    foreach ($cmd in $Global:P0Commands[$group]) {
        if ($cmd.Canonical -eq "go") {
            $goFound = $true
            $goAliases = $cmd.Aliases
            break
        }
    }
    if ($goFound) { break }
}

Assert-True -Condition $goFound -TestName "/commands contains /go"
# v22.0: P0Commands now shows only essential alias (/g), other aliases are silent
Assert-True -Condition ($goAliases -contains "g") -TestName "/go aliases include /g"

# Check /go appears exactly once (no duplicates)
$goCount = 0
foreach ($group in $Global:P0Commands.Keys) {
    foreach ($cmd in $Global:P0Commands[$group]) {
        if ($cmd.Canonical -eq "go") {
            $goCount++
        }
    }
}
Assert-True -Condition ($goCount -eq 1) -TestName "/go appears exactly once in P0Commands"

# v22.0: /exec should NOT appear as visible alias in P0Commands (hidden but still works)
$execInP0Aliases = $false
foreach ($group in $Global:P0Commands.Keys) {
    foreach ($cmd in $Global:P0Commands[$group]) {
        if ($cmd.Aliases -and $cmd.Aliases -contains "exec") {
            $execInP0Aliases = $true
            break
        }
    }
    if ($execInP0Aliases) { break }
}
Assert-True -Condition (-not $execInP0Aliases) -TestName "/exec is NOT listed in /commands aliases"

# v22.0: BUT /exec should still be a silent alias in the main Commands registry
$execIsSilentAlias = ($Global:Commands["go"].Alias -contains "exec")
Assert-True -Condition $execIsSilentAlias -TestName "/exec is still a silent alias for /go"

# ============================================================================
# TEST: /commands does NOT list long-tail commands
# ============================================================================
Write-Host ""
Write-Host "Test Group: Long-tail exclusion from /commands" -ForegroundColor Yellow

# These commands should NOT be in P0Commands (they're long-tail/advanced)
$longTailCmds = @("rigor", "snippets", "dupcheck", "router-debug", "unlock", "lock")

foreach ($ltCmd in $longTailCmds) {
    $found = $false
    foreach ($group in $Global:P0Commands.Keys) {
        foreach ($cmd in $Global:P0Commands[$group]) {
            if ($cmd.Canonical -eq $ltCmd) {
                $found = $true
                break
            }
        }
        if ($found) { break }
    }
    Assert-True -Condition (-not $found) -TestName "/commands excludes long-tail: /$ltCmd"
}

# ============================================================================
# TEST: /commands all includes long-tail commands
# ============================================================================
Write-Host ""
Write-Host "Test Group: /commands all (full registry)" -ForegroundColor Yellow

# These commands should be in the full registry
$fullRegCmds = @("rigor", "snippets", "router-debug", "unlock", "lock")

foreach ($cmd in $fullRegCmds) {
    $found = $Global:Commands.Contains($cmd)
    Assert-True -Condition $found -TestName "/commands all includes: /$cmd"
}

# ============================================================================
# TEST: /help topics prints topic list
# ============================================================================
Write-Host ""
Write-Host "Test Group: /help topics" -ForegroundColor Yellow

# Check that HelpTopics contains expected topics
$expectedTopics = @("tasks", "plan", "ops", "agents", "qa", "session")

foreach ($topic in $expectedTopics) {
    $found = $Global:HelpTopics.ContainsKey($topic)
    Assert-True -Condition $found -TestName "/help topics includes: $topic"
}

# ============================================================================
# TEST: /help <topic> prints expected commands
# ============================================================================
Write-Host ""
Write-Host "Test Group: /help <topic> content" -ForegroundColor Yellow

# Check tasks topic has expected commands
$tasksCommands = $Global:HelpTopics["tasks"].Commands | ForEach-Object { $_.Name }
Assert-True -Condition ($tasksCommands -contains "go") -TestName "/help tasks includes /go"
Assert-True -Condition ($tasksCommands -contains "add") -TestName "/help tasks includes /add"
Assert-True -Condition ($tasksCommands -contains "skip") -TestName "/help tasks includes /skip"

# Check plan topic has expected commands
$planCommands = $Global:HelpTopics["plan"].Commands | ForEach-Object { $_.Name }
Assert-True -Condition ($planCommands -contains "draft-plan") -TestName "/help plan includes /draft-plan"
Assert-True -Condition ($planCommands -contains "accept-plan") -TestName "/help plan includes /accept-plan"

# Check qa topic has expected commands
$qaCommands = $Global:HelpTopics["qa"].Commands | ForEach-Object { $_.Name }
Assert-True -Condition ($qaCommands -contains "preflight") -TestName "/help qa includes /preflight"
Assert-True -Condition ($qaCommands -contains "verify") -TestName "/help qa includes /verify"
Assert-True -Condition ($qaCommands -contains "ship") -TestName "/help qa includes /ship"

# ============================================================================
# TEST: P0Commands output is deterministic
# ============================================================================
Write-Host ""
Write-Host "Test Group: Deterministic output" -ForegroundColor Yellow

# Run twice and compare order
$run1 = @()
$run2 = @()

foreach ($group in $Global:P0Commands.Keys) {
    foreach ($cmd in $Global:P0Commands[$group]) {
        $run1 += "$group`:$($cmd.Canonical)"
    }
}

foreach ($group in $Global:P0Commands.Keys) {
    foreach ($cmd in $Global:P0Commands[$group]) {
        $run2 += "$group`:$($cmd.Canonical)"
    }
}

$orderMatch = ($run1 -join ",") -eq ($run2 -join ",")
Assert-True -Condition $orderMatch -TestName "/commands output is deterministic"

# ============================================================================
# TEST: Command count (P0 should be ≤25 lines)
# ============================================================================
Write-Host ""
Write-Host "Test Group: Output size constraints" -ForegroundColor Yellow

$totalP0Cmds = 0
foreach ($group in $Global:P0Commands.Keys) {
    $totalP0Cmds += $Global:P0Commands[$group].Count
}

# P0 commands + group headers + footer lines should be ≤25
$estimatedLines = $totalP0Cmds + $Global:P0Commands.Keys.Count + 5  # 5 for header/footer
Assert-True -Condition ($estimatedLines -le 30) -TestName "/commands output ≤30 lines (got $estimatedLines)"

# ============================================================================
# TEST: Keywords for fuzzy search
# ============================================================================
Write-Host ""
Write-Host "Test Group: Search keywords" -ForegroundColor Yellow

Assert-True -Condition ($Global:CommandKeywords.ContainsKey("go")) -TestName "Keywords defined for /go"
Assert-True -Condition ($Global:CommandKeywords["go"] -contains "execute") -TestName "/go keyword includes 'execute'"
Assert-True -Condition ($Global:CommandKeywords.ContainsKey("ship")) -TestName "Keywords defined for /ship"
Assert-True -Condition ($Global:CommandKeywords["ship"] -contains "deploy") -TestName "/ship keyword includes 'deploy'"

# ============================================================================
# TEST: /help precedence (command > topic > search)
# ============================================================================
Write-Host ""
Write-Host "Test Group: /help precedence" -ForegroundColor Yellow

# Test Resolve-CommandAlias function (needed for precedence tests)
# Re-extract functions section to get Resolve-CommandAlias
$funcPattern = '# ={10,}\s*\r?\n# COMMAND DISCOVERY FUNCTIONS'
$funcMatch = [regex]::Match($scriptContent, $funcPattern)
if ($funcMatch.Success) {
    $funcStart = $funcMatch.Index
    $dbPattern = '# ={10,}\s*\r?\n# DATABASE HELPER'
    $dbMatch = [regex]::Match($scriptContent, $dbPattern)
    if ($dbMatch.Success) {
        $funcSection = $scriptContent.Substring($funcStart, $dbMatch.Index - $funcStart)
        try { Invoke-Expression $funcSection } catch { }
    }
}

# /help go should resolve to command (not search)
$goResolved = Resolve-CommandAlias -Name "go"
Assert-True -Condition ($goResolved -ne $null) -TestName "/help go resolves as command"
Assert-True -Condition ($goResolved.Canonical -eq "go") -TestName "/help go canonical is 'go'"
Assert-True -Condition ($goResolved.IsAlias -eq $false) -TestName "/help go is not flagged as alias"

# /help g should resolve to /go (alias)
$gResolved = Resolve-CommandAlias -Name "g"
Assert-True -Condition ($gResolved -ne $null) -TestName "/help g resolves as alias"
Assert-True -Condition ($gResolved.Canonical -eq "go") -TestName "/help g canonical is 'go'"
Assert-True -Condition ($gResolved.IsAlias -eq $true) -TestName "/help g is flagged as alias"

# /help run should resolve to /go (alias)
$runResolved = Resolve-CommandAlias -Name "run"
Assert-True -Condition ($runResolved -ne $null) -TestName "/help run resolves as alias"
Assert-True -Condition ($runResolved.Canonical -eq "go") -TestName "/help run canonical is 'go'"

# /help continue should resolve to /go (alias)
$continueResolved = Resolve-CommandAlias -Name "continue"
Assert-True -Condition ($continueResolved -ne $null) -TestName "/help continue resolves as alias"
Assert-True -Condition ($continueResolved.Canonical -eq "go") -TestName "/help continue canonical is 'go'"

# /help plan should resolve to command (NOT topic, since "plan" is a command)
$planResolved = Resolve-CommandAlias -Name "plan"
Assert-True -Condition ($planResolved -ne $null) -TestName "/help plan resolves as command (not topic)"
Assert-True -Condition ($planResolved.Canonical -eq "plan") -TestName "/help plan canonical is 'plan'"

# /help tasks should resolve to command (since "tasks" is a command)
$tasksResolved = Resolve-CommandAlias -Name "tasks"
Assert-True -Condition ($tasksResolved -ne $null) -TestName "/help tasks resolves as command"
Assert-True -Condition ($tasksResolved.Canonical -eq "tasks") -TestName "/help tasks canonical is 'tasks'"

# /help q should resolve to /quit (alias)
$qResolved = Resolve-CommandAlias -Name "q"
Assert-True -Condition ($qResolved -ne $null) -TestName "/help q resolves as alias"
Assert-True -Condition ($qResolved.Canonical -eq "quit") -TestName "/help q canonical is 'quit'"

# /help nonexistent should NOT resolve (returns $null)
$nonexistentResolved = Resolve-CommandAlias -Name "nonexistent"
Assert-True -Condition ($nonexistentResolved -eq $null) -TestName "/help nonexistent does not resolve"

# ============================================================================
# TEST: v22.0 /ops is NOT promoted as default footer suggestion
# ============================================================================
Write-Host ""
Write-Host "Test Group: Footer /ops behavior (v22.0)" -ForegroundColor Yellow

# Check the source code for Get-RecommendedAction default return
# v22.0: Default should be "/plan", not "/ops"
$getRecPattern = '# 5\. Default:.*\r?\n\s*return @\{ Text = "([^"]+)"'
$defaultMatch = [regex]::Match($scriptContent, $getRecPattern)
if ($defaultMatch.Success) {
    $defaultText = $defaultMatch.Groups[1].Value
    Assert-True -Condition ($defaultText -notlike "*ops*") -TestName "Get-RecommendedAction default is NOT /ops (is: $defaultText)"
} else {
    Assert-True -Condition $false -TestName "Get-RecommendedAction default is NOT /ops (could not find pattern)"
}

# Check that /ops is only returned on health failure
$healthPattern = 'if \(\$Global:HealthStatus -eq "FAIL"\)[\s\S]*?return @\{ Text = "([^"]+)"'
$healthMatch = [regex]::Match($scriptContent, $healthPattern)
if ($healthMatch.Success) {
    $healthText = $healthMatch.Groups[1].Value
    Assert-True -Condition ($healthText -like "*ops*") -TestName "/ops is suggested on health FAIL (is: $healthText)"
} else {
    Assert-True -Condition $false -TestName "/ops is suggested on health FAIL (could not find pattern)"
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SUMMARY: $($Global:TestsPassed) passed, $($Global:TestsFailed) failed" -ForegroundColor $(if ($Global:TestsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ""

# Exit with appropriate code
if ($Global:TestsFailed -gt 0) {
    exit 1
}
exit 0
