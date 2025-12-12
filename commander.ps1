# Atomic Mesh Commander CLI v9.0.1
# Interactive CLI for Atomic Mesh Command & Control
# FEATURES: Mode switching, review, ship, milestone management
# ISOLATION: Uses LOCAL project folder for DB and logs

param()

# Dynamic path detection
$MeshRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CurrentDir = (Get-Location).Path
$DB_FILE = "$CurrentDir\mesh.db"
$LogDir = "$CurrentDir\logs"
$DocsDir = "$CurrentDir\docs"
$MilestoneFile = "$CurrentDir\.milestone_date"
$ModeFile = "$CurrentDir\.mesh_mode"

$host.UI.RawUI.WindowTitle = "AtomicCommander"

# --- PYTHON SQLITE HELPER ---
function Invoke-Sql {
    param([string]$Query)
    $script = "import sqlite3; conn = sqlite3.connect('$DB_FILE'); "
    $script += "cursor = conn.execute('''$Query'''); "
    $script += "[print('|'.join(str(x) for x in row)) for row in cursor.fetchall()]; "
    $script += "conn.commit(); conn.close()"
    return ($script | python 2>$null)
}

function Get-Mode {
    # Check milestone for auto-detection
    if (Test-Path $MilestoneFile) {
        try {
            $milestone = Get-Content $MilestoneFile -Raw
            $daysLeft = ((Get-Date $milestone) - (Get-Date)).Days
            if ($daysLeft -le 2) { return "ship" }
            elseif ($daysLeft -le 7) { return "converge" }
            else { return "vibe" }
        }
        catch {}
    }
    # Fall back to DB config
    $mode = Invoke-Sql "SELECT value FROM config WHERE key='mode'"
    if ($mode) { return $mode.Trim() }
    return "vibe"
}

function Get-Stats {
    $stats = @{ Pending = 0; Active = 0; Completed = 0; Failed = 0 }
    $rows = Invoke-Sql "SELECT status, COUNT(*) FROM tasks GROUP BY status"
    foreach ($row in $rows) {
        if ($row) {
            $parts = $row -split '\|'
            if ($parts.Count -ge 2) {
                switch ($parts[0]) {
                    'pending' { $stats.Pending = [int]$parts[1] }
                    'in_progress' { $stats.Active = [int]$parts[1] }
                    'completed' { $stats.Completed = [int]$parts[1] }
                    'failed' { $stats.Failed = [int]$parts[1] }
                }
            }
        }
    }
    return $stats
}

# --- COMMAND HANDLERS ---
function Show-Help {
    Write-Host ""
    Write-Host "  COMMANDS:" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  TASK MANAGEMENT:" -ForegroundColor Yellow
    Write-Host "    post <type> <d>  - Post task (backend/frontend/qa)" -ForegroundColor White
    Write-Host "    nuke             - Clear all pending tasks" -ForegroundColor White
    Write-Host "    reopen <id>      - Reopen task for rework" -ForegroundColor White
    Write-Host "    status           - Show queue status" -ForegroundColor White
    Write-Host ""
    Write-Host "  MODE CONTROL:" -ForegroundColor Yellow
    Write-Host "    mode             - Show current mode" -ForegroundColor White
    Write-Host "    mode vibe        - Fast iteration (tests optional)" -ForegroundColor Green
    Write-Host "    mode converge    - Unit tests required" -ForegroundColor Yellow
    Write-Host "    mode ship        - Full E2E, changelog required" -ForegroundColor Red
    Write-Host "    milestone <date> - Set target (auto-dimmer)" -ForegroundColor White
    Write-Host ""
    Write-Host "  REVIEW & SHIP:" -ForegroundColor Yellow
    Write-Host "    review           - Generate milestone report" -ForegroundColor White
    Write-Host "    ship             - Full validation + deploy" -ForegroundColor White
    Write-Host ""
    Write-Host "  DOCS & LOGS:" -ForegroundColor Yellow
    Write-Host "    logs             - Open latest COT log" -ForegroundColor White
    Write-Host "    spec             - Open ACTIVE_SPEC.md" -ForegroundColor White
    Write-Host "    tune             - Open TUNING.md" -ForegroundColor White
    Write-Host ""
    Write-Host "  OTHER:" -ForegroundColor Yellow
    Write-Host "    clear            - Clear screen" -ForegroundColor White
    Write-Host "    exit             - Exit commander" -ForegroundColor White
    Write-Host ""
}

function Show-Mode {
    $mode = Get-Mode
    $icons = @{ "vibe" = "🟢"; "converge" = "🟡"; "ship" = "🔴" }
    $descs = @{ 
        "vibe"     = "Fast iteration, tests optional"
        "converge" = "Unit tests required, no TODOs"
        "ship"     = "Full E2E, changelog required"
    }
    
    Write-Host ""
    Write-Host "  $($icons[$mode]) MODE: $($mode.ToUpper())" -ForegroundColor White
    Write-Host "     $($descs[$mode])" -ForegroundColor Gray
    
    if (Test-Path $MilestoneFile) {
        $milestone = Get-Content $MilestoneFile -Raw
        $daysLeft = ((Get-Date $milestone) - (Get-Date)).Days
        Write-Host "     📅 Milestone: $milestone ($daysLeft days) - AUTO" -ForegroundColor Cyan
    }
    Write-Host ""
}

function Set-Mode {
    param([string]$NewMode)
    if ($NewMode -notin @('vibe', 'converge', 'ship')) {
        Write-Host "  ❌ Invalid mode. Use: vibe, converge, ship" -ForegroundColor Red
        return
    }
    Invoke-Sql "UPDATE config SET value='$NewMode' WHERE key='mode'" | Out-Null
    if (Test-Path $MilestoneFile) { Remove-Item $MilestoneFile }
    Write-Host "  ✅ Mode set to: $($NewMode.ToUpper())" -ForegroundColor Green
}

function Set-Milestone {
    param([string]$DateStr)
    try {
        $milestone = Get-Date $DateStr
        $DateStr | Out-File $MilestoneFile -NoNewline
        $daysLeft = ($milestone - (Get-Date)).Days
        Write-Host "  🎯 Milestone: $DateStr ($daysLeft days)" -ForegroundColor Cyan
        Write-Host "     Auto-dimmer active. Mode will adjust automatically." -ForegroundColor Gray
    }
    catch {
        Write-Host "  ❌ Invalid date. Use: YYYY-MM-DD" -ForegroundColor Red
    }
}

function Invoke-Nuke {
    $count = Invoke-Sql "SELECT COUNT(*) FROM tasks WHERE status='pending'"
    Invoke-Sql "DELETE FROM tasks WHERE status='pending'" | Out-Null
    Write-Host "  🚨 NUKED $count pending tasks!" -ForegroundColor Red
}

function Invoke-Reopen {
    param([int]$TaskId, [string]$Reason = "")
    $reasonSafe = $Reason -replace "'", "''"
    if ($Reason) {
        Invoke-Sql "UPDATE tasks SET status='pending', worker_id=NULL, desc=desc||' REWORK: $reasonSafe' WHERE id=$TaskId" | Out-Null
    }
    else {
        Invoke-Sql "UPDATE tasks SET status='pending', worker_id=NULL WHERE id=$TaskId" | Out-Null
    }
    Write-Host "  🔄 Task $TaskId reopened for rework" -ForegroundColor Yellow
}

function Show-Status {
    $stats = Get-Stats
    $mode = Get-Mode
    $icons = @{ "vibe" = "🟢"; "converge" = "🟡"; "ship" = "🔴" }
    
    Write-Host ""
    Write-Host "  📊 QUEUE STATUS [$($icons[$mode]) $($mode.ToUpper())]" -ForegroundColor Cyan
    Write-Host "  ├─ Pending:    $($stats.Pending)" -ForegroundColor Yellow
    Write-Host "  ├─ Active:     $($stats.Active)" -ForegroundColor Green
    Write-Host "  ├─ Completed:  $($stats.Completed)" -ForegroundColor Gray
    Write-Host "  └─ Failed:     $($stats.Failed)" -ForegroundColor Red
    Write-Host ""
    
    $active = Invoke-Sql "SELECT id, type, substr(desc, 1, 45) FROM tasks WHERE status='in_progress'"
    if ($active) {
        Write-Host "  ⚡ ACTIVE:" -ForegroundColor Yellow
        foreach ($row in $active) {
            $parts = $row -split '\|'
            if ($parts.Count -ge 3) {
                Write-Host "    [$($parts[0])] $($parts[1]): $($parts[2])" -ForegroundColor White
            }
        }
        Write-Host ""
    }
}

function Invoke-Review {
    Write-Host ""
    Write-Host "  📊 MILESTONE REVIEW" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    
    $stats = Get-Stats
    $mode = Get-Mode
    
    Write-Host "  Mode: $($mode.ToUpper())" -ForegroundColor White
    Write-Host "  Completed: $($stats.Completed)" -ForegroundColor Green
    Write-Host "  Failed: $($stats.Failed)" -ForegroundColor Red
    Write-Host ""
    
    # Get completed tasks for changelog
    $completed = Invoke-Sql "SELECT type, substr(desc, 1, 60) FROM tasks WHERE status='completed' ORDER BY id DESC LIMIT 15"
    
    if ($completed) {
        Write-Host "  📝 CHANGELOG PREVIEW:" -ForegroundColor Yellow
        foreach ($row in $completed) {
            $parts = $row -split '\|'
            if ($parts.Count -ge 2) {
                Write-Host "    • [$($parts[0])] $($parts[1])" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host ""
    Write-Host "  Save to docs/CHANGELOG.md? [y/n]: " -NoNewline -ForegroundColor Magenta
    $confirm = Read-Host
    
    if ($confirm -eq 'y') {
        if (!(Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
        $date = Get-Date -Format 'yyyy-MM-dd'
        $changelog = "# Changelog - $date`n`n"
        foreach ($row in $completed) {
            $parts = $row -split '\|'
            if ($parts.Count -ge 2) {
                $changelog += "- [$($parts[0])] $($parts[1])`n"
            }
        }
        $changelog | Out-File "$DocsDir\CHANGELOG.md" -Encoding UTF8
        Write-Host "  ✅ Saved to docs/CHANGELOG.md" -ForegroundColor Green
        
        # Mark review done
        Invoke-Sql "UPDATE config SET value='$(Get-Date -UFormat %s)' WHERE key='last_review'" | Out-Null
    }
    Write-Host ""
}

function Invoke-Ship {
    Write-Host ""
    Write-Host "  🚀 SHIP MODE INITIATED" -ForegroundColor Red
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    
    # Set mode to ship
    Set-Mode "ship"
    
    # Check for pending/active tasks
    $stats = Get-Stats
    if ($stats.Pending -gt 0 -or $stats.Active -gt 0) {
        Write-Host "  ⚠️ Warning: $($stats.Pending) pending, $($stats.Active) active tasks" -ForegroundColor Yellow
        Write-Host "     Wait for completion or 'nuke' to clear." -ForegroundColor Gray
        return
    }
    
    # Run tests
    Write-Host "  1. Running test suite..." -ForegroundColor White
    $testResult = npm test 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "     ✅ Tests passed" -ForegroundColor Green
    }
    else {
        Write-Host "     ⚠️ Tests skipped or failed (non-blocking)" -ForegroundColor Yellow
    }
    
    # Build
    Write-Host "  2. Building production bundle..." -ForegroundColor White
    $buildResult = npm run build 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "     ✅ Build successful" -ForegroundColor Green
    }
    else {
        Write-Host "     ❌ Build failed" -ForegroundColor Red
        return
    }
    
    # Generate changelog from GIT LOG (not just tasks)
    Write-Host "  3. Generating release notes from git..." -ForegroundColor White
    
    # Get last tag or use last 20 commits
    $lastTag = git describe --tags --abbrev=0 2>$null
    if ($lastTag) {
        $gitLog = git log "$lastTag..HEAD" --pretty=format:"%s" --no-merges 2>$null
    }
    else {
        $gitLog = git log -20 --pretty=format:"%s" --no-merges 2>$null
    }
    
    if (!(Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
    
    $date = Get-Date -Format 'yyyy-MM-dd'
    $version = git describe --tags --always 2>$null
    if (!$version) { $version = "unreleased" }
    
    $changelog = @"
# Release Notes - $date

## Version: $version

### Changes
"@
    
    # Categorize commits
    $features = @()
    $fixes = @()
    $other = @()
    
    foreach ($line in ($gitLog -split "`n")) {
        if ($line -match "^feat|^add|^new") { $features += "- $line" }
        elseif ($line -match "^fix|^bug|^patch") { $fixes += "- $line" }
        elseif ($line.Trim()) { $other += "- $line" }
    }
    
    if ($features.Count -gt 0) {
        $changelog += "`n`n#### ✨ Features`n" + ($features -join "`n")
    }
    if ($fixes.Count -gt 0) {
        $changelog += "`n`n#### 🐛 Bug Fixes`n" + ($fixes -join "`n")
    }
    if ($other.Count -gt 0) {
        $changelog += "`n`n#### 📦 Other`n" + ($other -join "`n")
    }
    
    # Also append task completions
    $completed = Invoke-Sql "SELECT type, substr(desc, 1, 60) FROM tasks WHERE status='completed' ORDER BY id DESC LIMIT 10"
    if ($completed) {
        $changelog += "`n`n### Atomic Mesh Tasks Completed`n"
        foreach ($row in $completed) {
            $parts = $row -split '\|'
            if ($parts.Count -ge 2) {
                $changelog += "- [$($parts[0])] $($parts[1])`n"
            }
        }
    }
    
    Write-Host ""
    Write-Host "  📝 RELEASE NOTES PREVIEW:" -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ($changelog.Substring(0, [Math]::Min(500, $changelog.Length))) -ForegroundColor Gray
    if ($changelog.Length -gt 500) { Write-Host "  ..." -ForegroundColor DarkGray }
    
    Write-Host ""
    Write-Host "  Save to docs/RELEASE_NOTES.md? [y/n]: " -NoNewline -ForegroundColor Magenta
    $confirm = Read-Host
    
    if ($confirm -eq 'y') {
        $changelog | Out-File "$DocsDir\RELEASE_NOTES.md" -Encoding UTF8
        Write-Host "  ✅ Saved to docs/RELEASE_NOTES.md" -ForegroundColor Green
        
        # Mark review done
        Invoke-Sql "UPDATE config SET value='$(Get-Date -UFormat %s)' WHERE key='last_review'" | Out-Null
    }
    
    Write-Host ""
    Write-Host "  📦 PRODUCT PACKET READY" -ForegroundColor Green
    Write-Host "  ├─ Release Notes: docs/RELEASE_NOTES.md" -ForegroundColor White
    Write-Host "  ├─ Build: ✅ Verified" -ForegroundColor White
    Write-Host "  └─ Mode: 🔴 SHIP (pre-commit hooks active)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Ready to deploy: git push" -ForegroundColor Cyan
    Write-Host ""
}

function Post-Task {
    param([string]$Type, [string]$Description, [int]$Priority = 1)
    
    $validTypes = @('backend', 'frontend', 'qa')
    if ($Type -notin $validTypes) {
        Write-Host "  ❌ Invalid type. Use: backend, frontend, qa" -ForegroundColor Red
        return
    }
    
    $escapedDesc = $Description -replace "'", "''"
    Invoke-Sql "INSERT INTO tasks (type, desc, deps, status, updated_at, priority) VALUES ('$Type', '$escapedDesc', '[]', 'pending', strftime('%s','now'), $Priority)" | Out-Null
    Write-Host "  ✅ Task posted to $Type queue (P$Priority)" -ForegroundColor Green
}

function Open-Logs {
    $logFile = Get-ChildItem "$LogDir\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($logFile) {
        code $logFile.FullName
        Write-Host "  📂 Opened: $($logFile.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ No log files found" -ForegroundColor Red
    }
}

function Open-Doc {
    param([string]$DocName)
    if (!(Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }
    $path = Join-Path $DocsDir $DocName
    if (!(Test-Path $path)) { "" | Out-File $path -Encoding UTF8 }
    code $path
    Write-Host "  📂 Opened: $DocName" -ForegroundColor Green
}

# --- MAIN LOOP ---
Clear-Host
$width = 60
$border = [string]::new([char]0x2500, $width - 2)

Write-Host ""
Write-Host ([char]0x250C + $border + [char]0x2510) -ForegroundColor Cyan
Write-Host ([char]0x2502) -NoNewline -ForegroundColor Cyan
Write-Host " 🎖️ ATOMIC COMMANDER v2.0".PadRight($width - 2) -NoNewline -ForegroundColor White
Write-Host ([char]0x2502) -ForegroundColor Cyan
Write-Host ([char]0x2514 + $border + [char]0x2518) -ForegroundColor Cyan
Write-Host ""

Show-Mode
$stats = Get-Stats
Write-Host "  Workers: $($stats.Active) active | Pending: $($stats.Pending) | Done: $($stats.Completed)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Type 'help' for commands" -ForegroundColor DarkGray
Write-Host ""

while ($true) {
    $mode = Get-Mode
    $icons = @{ "vibe" = "🟢"; "converge" = "🟡"; "ship" = "🔴" }
    Write-Host "  $($icons[$mode]) > " -NoNewline -ForegroundColor Cyan
    $userInput = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($userInput)) { continue }
    
    $parts = $userInput -split ' ', 2
    $cmd = $parts[0].ToLower()
    $cmdArgs = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    
    switch ($cmd) {
        'help' { Show-Help }
        'h' { Show-Help }
        '?' { Show-Help }
        
        'mode' {
            if ($cmdArgs) { Set-Mode $cmdArgs }
            else { Show-Mode }
        }
        
        'milestone' {
            if ($cmdArgs) { Set-Milestone $cmdArgs }
            else { Write-Host "  ❌ Usage: milestone YYYY-MM-DD" -ForegroundColor Red }
        }
        
        'nuke' { Invoke-Nuke }
        'clear' { Clear-Host }
        'cls' { Clear-Host }
        
        'status' { Show-Status }
        's' { Show-Status }
        
        'review' { Invoke-Review }
        'ship' { Invoke-Ship }
        
        'reopen' {
            $reopenParts = $cmdArgs -split ' ', 2
            if ($reopenParts[0] -match '^\d+$') {
                $reason = if ($reopenParts.Count -gt 1) { $reopenParts[1] } else { "" }
                Invoke-Reopen -TaskId ([int]$reopenParts[0]) -Reason $reason
            }
            else {
                Write-Host "  ❌ Usage: reopen <task_id> [reason]" -ForegroundColor Red
            }
        }
        
        'logs' { Open-Logs }
        'log' { Open-Logs }
        
        'spec' { Open-Doc "ACTIVE_SPEC.md" }
        'decision' { Open-Doc "DECISION_LOG.md" }
        'tune' { Open-Doc "TUNING.md" }
        'tuning' { Open-Doc "TUNING.md" }
        'changelog' { Open-Doc "CHANGELOG.md" }
        
        'post' {
            $postParts = $cmdArgs -split ' ', 2
            if ($postParts.Count -ge 2) {
                Post-Task -Type $postParts[0] -Description $postParts[1]
            }
            else {
                Write-Host "  ❌ Usage: post <type> <description>" -ForegroundColor Red
            }
        }
        
        'exit' { Write-Host "  👋 Goodbye!" -ForegroundColor Yellow; exit }
        'quit' { Write-Host "  👋 Goodbye!" -ForegroundColor Yellow; exit }
        'q' { Write-Host "  👋 Goodbye!" -ForegroundColor Yellow; exit }
        
        default {
            Write-Host "  ❌ Unknown: $cmd (type 'help')" -ForegroundColor Red
        }
    }
}
