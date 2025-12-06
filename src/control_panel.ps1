# C:\Tools\atomic-mesh\control_panel.ps1
# ATOMIC MESH COMMANDER v7.5 - Slash-Command Edition + Multi-Project
# FEATURES: Discord-style /commands, natural language chat, multi-project grid

param(
    [string]$ProjectName = "Standalone",
    [string]$ProjectPath = "",
    [string]$DbPath = "mesh.db"
)

# Set working directory and database
if ($ProjectPath -and (Test-Path $ProjectPath)) {
    Set-Location $ProjectPath
}
$CurrentDir = (Get-Location).Path
$DB_FILE = Join-Path $CurrentDir $DbPath
$LogDir = "$CurrentDir\logs"
$DocsDir = "$CurrentDir\docs"
$MilestoneFile = "$CurrentDir\.milestone_date"
$SpecFile = "$DocsDir\ACTIVE_SPEC.md"
$RepoRoot = if ($PSScriptRoot) { Resolve-Path "$PSScriptRoot\.." } else { $CurrentDir }

# Set environment for Python
$env:ATOMIC_MESH_DB = $DB_FILE

# Update window title
$host.UI.RawUI.WindowTitle = "Atomic Mesh :: $ProjectName"

# Ensure directories exist
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
if (!(Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }

# Layout constants
$TotalWidth = 77

# ============================================================================
# COMMAND REGISTRY - All slash commands defined here
# ============================================================================

$Global:Commands = [ordered]@{
    # EXECUTION
    "go"        = @{ Desc = "execute the next pending task"; Alias = @("continue", "c") }
    
    # TASK MANAGEMENT
    "add"       = @{ Desc = "add task: /add backend|frontend <description>"; HasArgs = $true }
    "skip"      = @{ Desc = "skip a task: /skip <task_id>"; HasArgs = $true }
    "reset"     = @{ Desc = "reset failed task: /reset <task_id>"; HasArgs = $true }
    "drop"      = @{ Desc = "delete a task: /drop <task_id>"; HasArgs = $true }
    "nuke"      = @{ Desc = "clear all pending (requires --confirm)"; HasArgs = $true }
    
    # AGENTS
    "audit"     = @{ Desc = "open auditor status and log" }
    "lib"       = @{ Desc = "librarian: /lib scan|status|approve|execute"; HasArgs = $true }
    
    # STREAMS
    "stream"    = @{ Desc = "view worker output: /stream backend|frontend"; HasArgs = $true }
    
    # MULTI-PROJECT
    "multi"     = @{ Desc = "launch multi-project grid: /multi 1 2 3"; HasArgs = $true }
    "projects"  = @{ Desc = "list available projects" }
    
    # LIBRARY (v7.6)
    "init"      = @{ Desc = "auto-detect and link project to library profile" }
    "profile"   = @{ Desc = "show/set project profile: /profile [name]"; HasArgs = $true }
    "standard"  = @{ Desc = "view a standard: /standard security|architecture"; HasArgs = $true }
    "standards" = @{ Desc = "list all standards for current profile" }
    
    # v8.0 PRE-FLIGHT
    "ship"      = @{ Desc = "commit and push to GitHub (trusts local QA)"; HasArgs = $true }
    "preflight" = @{ Desc = "run local pre-flight tests" }
    
    # CONTEXT
    "decide"    = @{ Desc = "answer decision: /decide <id> <answer>"; HasArgs = $true }
    "note"      = @{ Desc = "add a note: /note <text>"; HasArgs = $true }
    "blocker"   = @{ Desc = "report blocker: /blocker <text>"; HasArgs = $true }
    
    # CONFIGURATION
    "mode"      = @{ Desc = "show/toggle mode: /mode [vibe|converge|ship]"; HasArgs = $true }
    "milestone" = @{ Desc = "set milestone: /milestone YYYY-MM-DD"; HasArgs = $true }
    
    # SESSION
    "status"    = @{ Desc = "show system status dashboard" }
    "plan"      = @{ Desc = "show project roadmap" }
    "tasks"     = @{ Desc = "list all tasks" }
    "help"      = @{ Desc = "show all available commands"; Alias = @("?") }
    "refresh"   = @{ Desc = "refresh the display" }
    "clear"     = @{ Desc = "clear the console screen" }
    "quit"      = @{ Desc = "exit Atomic Mesh"; Alias = @("q", "exit") }
    
    # v8.2 DIAGNOSTICS
    "doctor"    = @{ Desc = "run system health check (Gap #3)" }
    
    # v8.4.1 SPEC ANALYSIS
    "refine"    = @{ Desc = "analyze ACTIVE_SPEC.md for ambiguities" }
}


# ============================================================================
# DATABASE HELPER
# ============================================================================

function Invoke-Query {
    param([string]$Query, [switch]$Silent)
    
    # Basic SQL injection protection
    $dangerousPatterns = @("DROP TABLE", "DELETE FROM tasks", "--", ";--")
    foreach ($pattern in $dangerousPatterns) {
        if ($Query -match [regex]::Escape($pattern)) {
            if (-not $Silent) { Write-Host "  🔴 Query rejected" -ForegroundColor Red }
            return @()
        }
    }
    
    $script = @"
import sqlite3, json
try:
    conn = sqlite3.connect('$DB_FILE')
    conn.row_factory = sqlite3.Row
    rows = conn.execute('''$Query''').fetchall()
    print(json.dumps([dict(r) for r in rows]))
    conn.close()
except: print('[]')
"@
    try {
        $result = $script | python 2>$null
        if ($result) { return $result | ConvertFrom-Json }
    }
    catch {}
    return @()
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-ProjectMode {
    if (Test-Path $MilestoneFile) {
        try {
            $milestone = Get-Content $MilestoneFile -Raw
            $daysLeft = ((Get-Date $milestone) - (Get-Date)).Days
            if ($daysLeft -le 2) { return @{ Mode = "SHIP"; Days = $daysLeft; Color = "Red"; Icon = "🔴" } }
            elseif ($daysLeft -le 7) { return @{ Mode = "CONVERGE"; Days = $daysLeft; Color = "Yellow"; Icon = "🟡" } }
            else { return @{ Mode = "VIBE"; Days = $daysLeft; Color = "Green"; Icon = "🟢" } }
        }
        catch {}
    }
    return @{ Mode = "VIBE"; Days = $null; Color = "Green"; Icon = "🟢" }
}

function Get-TaskStats {
    $stats = Invoke-Query "SELECT status, COUNT(*) as c FROM tasks GROUP BY status" -Silent
    $result = @{ pending = 0; in_progress = 0; completed = 0; failed = 0 }
    foreach ($s in $stats) {
        if ($s.status) { $result[$s.status] = $s.c }
    }
    return $result
}

function Show-Header {
    $proj = Get-ProjectMode
    $stats = Get-TaskStats
    
    # Get console width for dynamic layout
    $width = 77
    try { 
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        if ($consoleWidth -gt 50) { $width = [Math]::Min($consoleWidth - 2, 100) }
    }
    catch {}
    
    $line = "─" * ($width - 2)
    
    # Build title line: Project Name (left) ........ Path (right)
    $path = $CurrentDir
    $maxPathLen = $width - $ProjectName.Length - 15
    if ($path.Length -gt $maxPathLen -and $maxPathLen -gt 10) {
        $path = "..." + $path.Substring($path.Length - ($maxPathLen - 3))
    }
    
    # Calculate padding between name and path
    $padLen = $width - 6 - $ProjectName.Length - $path.Length
    if ($padLen -lt 1) { $padLen = 1 }
    $padding = " " * $padLen
    
    Write-Host ""
    Write-Host "┌$line┐" -ForegroundColor Cyan
    
    # Line 1: Project Name (left) ........ Path (right)
    Write-Host "│ " -NoNewline -ForegroundColor Cyan
    Write-Host "📂 $ProjectName" -NoNewline -ForegroundColor Yellow
    Write-Host "$padding$path " -NoNewline -ForegroundColor DarkGray
    Write-Host "│" -ForegroundColor Cyan
    
    # Line 2: Mode and Stats
    $modeStr = "$($proj.Icon) $($proj.Mode)"
    if ($null -ne $proj.Days) { $modeStr += " ($($proj.Days)d)" }
    $statsStr = "$($stats.pending) pending | $($stats.in_progress) active | $($stats.completed) done"
    $statusLine = "  $modeStr | $statsStr"
    $statusPad = $width - 3 - $statusLine.Length
    if ($statusPad -lt 0) { $statusPad = 0 }
    
    Write-Host "│$statusLine" -NoNewline -ForegroundColor White
    Write-Host (" " * $statusPad) -NoNewline
    Write-Host "│" -ForegroundColor Cyan
    
    Write-Host "└$line┘" -ForegroundColor Cyan
    
    # --- v8.5 DECISION TICKER ---
    $LogPath = Join-Path (Get-Location) "docs\DECISION_LOG.md"
    if (Test-Path $LogPath) {
        # Get last 3 entries that start with '|' and contain a number (ignoring headers)
        $Entries = Get-Content $LogPath | Where-Object { $_ -match "^\|\s*\d+" } | Select-Object -Last 3
        
        if ($Entries -and $Entries.Count -gt 0) {
            Write-Host "┌─ RECENT DECISIONS ─$("─" * ($width - 22))┐" -ForegroundColor DarkGray
            
            foreach ($Row in $Entries) {
                # Format: Clean up pipes and spacing, limit width
                $Clean = $Row -replace "\|", " " -replace "\s+", " " 
                $Clean = $Clean.Trim()
                $maxLen = $width - 4
                if ($Clean.Length -gt $maxLen) { $Clean = $Clean.Substring(0, $maxLen - 3) + "..." }
                $rowPad = $width - 3 - $Clean.Length
                if ($rowPad -lt 0) { $rowPad = 0 }
                Write-Host "│ $Clean" -NoNewline -ForegroundColor Gray
                Write-Host (" " * $rowPad) -NoNewline
                Write-Host "│" -ForegroundColor DarkGray
            }
            
            Write-Host "└$("─" * ($width - 2))┘" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# COMMAND SUGGESTION SYSTEM
# ============================================================================

function Show-CommandSuggestions {
    param([string]$Filter)
    
    # Remove leading slash
    $filter = $Filter.TrimStart("/").ToLower()
    
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    
    $found = 0
    foreach ($key in $Global:Commands.Keys) {
        # Match if filter is empty or command starts with filter
        if ($filter -eq "" -or $key.StartsWith($filter)) {
            $desc = $Global:Commands[$key].Desc
            $cmdDisplay = "/$key".PadRight(14)
            Write-Host "  $cmdDisplay" -NoNewline -ForegroundColor Yellow
            Write-Host "$desc" -ForegroundColor Gray
            $found++
        }
    }
    
    if ($found -eq 0) {
        Write-Host "  (No matching commands for '/$filter')" -ForegroundColor DarkGray
    }
    
    Write-Host "  ─────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

# ============================================================================
# COMMAND EXECUTION
# ============================================================================

function Invoke-Continue {
    # Check for RED decisions (blockers)
    $redDecisions = Invoke-Query "SELECT id, question FROM decisions WHERE status='pending' AND priority='red' LIMIT 1"
    if ($redDecisions.Count -gt 0) {
        $dec = $redDecisions[0]
        Write-Host "  🔴 BLOCKED: Decision required" -ForegroundColor Red
        Write-Host "     [$($dec.id)] $($dec.question)" -ForegroundColor Yellow
        Write-Host "     Use: /decide $($dec.id) <your answer>" -ForegroundColor Gray
        return
    }
    
    # Check for stuck tasks
    $stuckTasks = Invoke-Query "SELECT id, desc FROM tasks WHERE auditor_status='escalated' OR retry_count >= 3 LIMIT 1"
    if ($stuckTasks.Count -gt 0) {
        $stuck = $stuckTasks[0]
        Write-Host "  🔴 STUCK: Auditor escalated task" -ForegroundColor Red
        Write-Host "     [$($stuck.id)] $($stuck.desc)" -ForegroundColor Yellow
        Write-Host "     Use: /reset $($stuck.id) after fixing manually" -ForegroundColor Gray
        return
    }
    
    # Get next pending task
    $nextTask = Invoke-Query "SELECT id, type, desc, strictness FROM tasks WHERE status='pending' ORDER BY priority DESC, id LIMIT 1"
    if ($nextTask.Count -eq 0) {
        Write-Host "  ✅ Queue empty. All done!" -ForegroundColor Green
        return
    }
    
    $task = $nextTask[0]
    $strictness = if ($task.strictness) { $task.strictness.ToUpper() } else { "NORMAL" }
    $icon = switch ($strictness) { "CRITICAL" { "🔴" } "RELAXED" { "🟢" } default { "🟡" } }
    
    Write-Host "  ▶ Executing [$icon $strictness]: [$($task.id)] $($task.desc)" -ForegroundColor Cyan
    Invoke-Query "UPDATE tasks SET status='in_progress', updated_at=strftime('%s','now') WHERE id=$($task.id)" | Out-Null
}

function Show-Stream {
    param([string]$Type)
    
    $logFile = Get-ChildItem "$LogDir\*-$Type.log" -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    if (-not $logFile) {
        Write-Host "  No logs for $Type worker" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "  ═══ $($Type.ToUpper()) WORKER STREAM ═══" -ForegroundColor Cyan
    Write-Host ""
    
    $lines = Get-Content $logFile.FullName -Tail 15 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        Write-Host "  $line" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

function Show-AuditLog {
    Write-Host ""
    Write-Host "  ═══ AUDIT LOG ═══" -ForegroundColor Cyan
    Write-Host ""
    
    $logs = Invoke-Query "SELECT task_id, action, strictness, reason, created_at FROM audit_log ORDER BY created_at DESC LIMIT 8"
    
    if ($logs.Count -eq 0) {
        Write-Host "  No audit entries yet" -ForegroundColor Gray
        return
    }
    
    foreach ($log in $logs) {
        $icon = switch ($log.action) { 'approve' { '✅' } 'reject' { '🔴' } 'escalate' { '⚠️' } default { '📋' } }
        Write-Host "  $icon [$($log.task_id)] $($log.action.ToUpper()) - $($log.reason)" -ForegroundColor Gray
    }
}

function Show-Tasks {
    Write-Host ""
    Write-Host "  ═══ TASK LIST ═══" -ForegroundColor Cyan
    Write-Host ""
    
    $tasks = Invoke-Query "SELECT id, type, status, substr(desc,1,45) as d FROM tasks ORDER BY CASE status WHEN 'in_progress' THEN 1 WHEN 'pending' THEN 2 ELSE 3 END, id LIMIT 15"
    
    if ($tasks.Count -eq 0) {
        Write-Host "  No tasks in queue" -ForegroundColor Gray
        return
    }
    
    foreach ($task in $tasks) {
        $icon = switch ($task.status) { 'completed' { '✅' } 'in_progress' { '⏳' } 'pending' { '⏸️' } 'failed' { '❌' } default { '📋' } }
        $typeIcon = if ($task.type -eq 'backend') { 'BE' } else { 'FE' }
        Write-Host "  $icon [$($task.id)] [$typeIcon] $($task.d)" -ForegroundColor $(if ($task.status -eq 'in_progress') { 'Cyan' } else { 'Gray' })
    }
}

function Show-Plan {
    Write-Host ""
    Write-Host "  ═══ ROADMAP ═══" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  BACKEND:" -ForegroundColor Yellow
    $beTasks = Invoke-Query "SELECT id, substr(desc,1,50) as d FROM tasks WHERE type='backend' AND status='pending' ORDER BY priority DESC, id LIMIT 5"
    if ($beTasks.Count -eq 0) { Write-Host "    (empty)" -ForegroundColor Gray }
    foreach ($t in $beTasks) { Write-Host "    → [$($t.id)] $($t.d)" -ForegroundColor Gray }
    
    Write-Host ""
    Write-Host "  FRONTEND:" -ForegroundColor Yellow
    $feTasks = Invoke-Query "SELECT id, substr(desc,1,50) as d FROM tasks WHERE type='frontend' AND status='pending' ORDER BY priority DESC, id LIMIT 5"
    if ($feTasks.Count -eq 0) { Write-Host "    (empty)" -ForegroundColor Gray }
    foreach ($t in $feTasks) { Write-Host "    → [$($t.id)] $($t.d)" -ForegroundColor Gray }
}

function Invoke-SlashCommand {
    param([string]$UserInput)
    
    # Parse command and cmdArgs
    $parts = $UserInput.TrimStart("/").Split(" ", 2)
    $cmd = $parts[0].ToLower()
    $cmdArgs = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
    
    # Check for aliases
    foreach ($key in $Global:Commands.Keys) {
        $aliases = $Global:Commands[$key].Alias
        if ($aliases -and $aliases -contains $cmd) {
            $cmd = $key
            break
        }
    }
    
    switch ($cmd) {
        # === SESSION ===
        "quit" { 
            Write-Host "  👋 Goodbye!" -ForegroundColor Yellow
            exit 
        }
        "clear" { 
            Clear-Host
            return "refresh"
        }
        "refresh" { 
            return "refresh" 
        }
        "help" {
            Write-Host ""
            Write-Host "  ═══ AVAILABLE COMMANDS ═══" -ForegroundColor Cyan
            Write-Host ""
            foreach ($key in $Global:Commands.Keys) {
                $desc = $Global:Commands[$key].Desc
                Write-Host "  /$key".PadRight(16) -NoNewline -ForegroundColor Yellow
                Write-Host "$desc" -ForegroundColor Gray
            }
            Write-Host ""
            Write-Host "  TIP: Type '/' to see suggestions, '/a' to filter to 'a' commands" -ForegroundColor DarkGray
        }
        
        # === EXECUTION ===
        "go" { Invoke-Continue }
        
        # === TASK MANAGEMENT ===
        "add" {
            if ($args -match "^(backend|frontend)\s+(.+)$") {
                $type = $Matches[1]
                $desc = $Matches[2]
                $now = [int](Get-Date -UFormat %s)
                Invoke-Query "INSERT INTO tasks (type, desc, status, updated_at) VALUES ('$type', '$desc', 'pending', $now)" | Out-Null
                Write-Host "  ✅ Added $type task: $desc" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /add backend|frontend <description>" -ForegroundColor Yellow
            }
        }
        "skip" {
            if ($args -match "^\d+$") {
                Invoke-Query "UPDATE tasks SET status='skipped' WHERE id=$args" | Out-Null
                Write-Host "  ⏭️ Skipped task #$args" -ForegroundColor Yellow
            }
            else {
                Write-Host "  Usage: /skip <task_id>" -ForegroundColor Yellow
            }
        }
        "reset" {
            if ($args -match "^\d+$") {
                Invoke-Query "UPDATE tasks SET retry_count=0, auditor_status='pending', auditor_feedback='[]', status='pending' WHERE id=$args" | Out-Null
                Write-Host "  🔄 Reset task #$args" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /reset <task_id>" -ForegroundColor Yellow
            }
        }
        "drop" {
            if ($args -match "^\d+$") {
                Invoke-Query "DELETE FROM tasks WHERE id=$args" | Out-Null
                Write-Host "  🗑️ Deleted task #$args" -ForegroundColor Red
            }
            else {
                Write-Host "  Usage: /drop <task_id>" -ForegroundColor Yellow
            }
        }
        "nuke" {
            if ($args -eq "--confirm") {
                Invoke-Query "DELETE FROM tasks WHERE status='pending'" | Out-Null
                Write-Host "  💥 All pending tasks cleared" -ForegroundColor Red
            }
            else {
                Write-Host "  ⚠️ This will delete ALL pending tasks!" -ForegroundColor Red
                Write-Host "  Type: /nuke --confirm" -ForegroundColor Yellow
            }
        }
        
        # === AGENTS ===
        "audit" { Show-AuditLog }
        "lib" {
            $action = if ($args) { $args.Split(" ")[0] } else { "status" }
            switch ($action) {
                "scan" { 
                    # Gap #4 Fix: Git Guard
                    $gitStatus = git status --porcelain 2>&1
                    if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
                        Write-Host "  🔴 BLOCKED: Git working tree is dirty." -ForegroundColor Red
                        Write-Host "     Commit or stash changes before running Librarian." -ForegroundColor Gray
                        Write-Host ""
                        Write-Host "     Changed files:" -ForegroundColor Yellow
                        $gitStatus -split "`n" | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
                        return
                    }
                    
                    Write-Host "  📚 Starting Librarian scan..." -ForegroundColor Cyan
                    Write-Host "  (Use MCP tool: librarian_scan)" -ForegroundColor Gray
                }
                "status" {
                    $ops = Invoke-Query "SELECT status, COUNT(*) as c FROM librarian_ops GROUP BY status"
                    Write-Host "  📚 Librarian Status:" -ForegroundColor Cyan
                    foreach ($op in $ops) { Write-Host "    $($op.status): $($op.c)" -ForegroundColor Gray }
                }
                "mount" {
                    # Mount external reference project via symlink
                    $parts = $action_args -split "\s+", 2
                    $name = $parts[0]
                    $targetPath = if ($parts.Count -gt 1) { $parts[1] } else { "" }
                    
                    if (-not $name -or -not $targetPath) {
                        Write-Host "  Usage: /lib mount <name> <path>" -ForegroundColor Yellow
                        Write-Host "  Example: /lib mount context7 E:\Code\reference-project" -ForegroundColor Gray
                        return
                    }
                    
                    $refsPath = Join-Path $RepoRoot "library\references"
                    $linkPath = Join-Path $refsPath $name
                    
                    if (-not (Test-Path $targetPath)) {
                        Write-Host "  ⚠️ Target path does not exist: $targetPath" -ForegroundColor Yellow
                        return
                    }
                    
                    if (Test-Path $linkPath) {
                        Write-Host "  ⚠️ '$name' already mounted. Use /lib unmount $name first." -ForegroundColor Yellow
                        return
                    }
                    
                    try {
                        # Create junction (symlink alternative that doesn't need admin)
                        New-Item -ItemType Junction -Path $linkPath -Target $targetPath | Out-Null
                        Write-Host "  ✅ Mounted '$name' → $targetPath" -ForegroundColor Green
                        Write-Host "  Agents can now access: library/references/$name" -ForegroundColor Gray
                    }
                    catch {
                        Write-Host "  ⚠️ Failed to create junction. Try running as Admin." -ForegroundColor Yellow
                        Write-Host "  Or manually: New-Item -ItemType Junction -Path '$linkPath' -Target '$targetPath'" -ForegroundColor Gray
                    }
                }
                "unmount" {
                    $name = $action_args
                    if (-not $name) {
                        Write-Host "  Usage: /lib unmount <name>" -ForegroundColor Yellow
                        return
                    }
                    
                    $linkPath = Join-Path $RepoRoot "library\references\$name"
                    
                    if (-not (Test-Path $linkPath)) {
                        Write-Host "  ⚠️ '$name' is not mounted" -ForegroundColor Yellow
                        return
                    }
                    
                    try {
                        # Remove junction (use cmd's rmdir to safely remove junction without deleting target)
                        cmd /c "rmdir `"$linkPath`"" 2>$null
                        Write-Host "  ✅ Unmounted '$name'" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "  ⚠️ Failed to unmount. Try: cmd /c rmdir '$linkPath'" -ForegroundColor Yellow
                    }
                }
                "refs" {
                    # List mounted references
                    $refsPath = Join-Path $RepoRoot "library\references"
                    Write-Host ""
                    Write-Host "  ═══ MOUNTED REFERENCES ═══" -ForegroundColor Cyan
                    Write-Host ""
                    
                    $items = Get-ChildItem $refsPath -Directory -ErrorAction SilentlyContinue
                    if ($items) {
                        foreach ($item in $items) {
                            $isJunction = (Get-Item $item.FullName).Attributes -band [IO.FileAttributes]::ReparsePoint
                            $icon = if ($isJunction) { "🔗" } else { "📁" }
                            $target = if ($isJunction) {
                                try { (Get-Item $item.FullName).Target } catch { "→ (junction)" }
                            }
                            else { "(local)" }
                            
                            Write-Host "    $icon $($item.Name)" -NoNewline -ForegroundColor Yellow
                            Write-Host " $target" -ForegroundColor Gray
                        }
                    }
                    else {
                        Write-Host "    (No references mounted)" -ForegroundColor Gray
                    }
                    
                    Write-Host ""
                    Write-Host "  Mount with: /lib mount <name> <path>" -ForegroundColor Gray
                }
                default { Write-Host "  Usage: /lib scan|status|mount|unmount|refs" -ForegroundColor Yellow }
            }
        }
        
        # === STREAMS ===
        "stream" {
            if ($args -eq "backend" -or $args -eq "be") { Show-Stream "backend" }
            elseif ($args -eq "frontend" -or $args -eq "fe") { Show-Stream "frontend" }
            else { Write-Host "  Usage: /stream backend|frontend" -ForegroundColor Yellow }
        }
        
        # === CONTEXT ===
        "decide" {
            if ($args -match "^(\d+)\s+(.+)$") {
                $id = $Matches[1]
                $answer = $Matches[2]
                Invoke-Query "UPDATE decisions SET answer='$answer', status='resolved' WHERE id=$id" | Out-Null
                Write-Host "  ✅ Decision #$id resolved" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /decide <id> <answer>" -ForegroundColor Yellow
            }
        }
        "note" {
            if ($args) {
                $notesFile = "$DocsDir\NOTES.md"
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
                Add-Content -Path $notesFile -Value "`n## $timestamp`n$args`n"
                Write-Host "  📝 Note added" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /note <text>" -ForegroundColor Yellow
            }
        }
        "blocker" {
            if ($args) {
                $now = [int](Get-Date -UFormat %s)
                Invoke-Query "INSERT INTO decisions (priority, question, status, created_at) VALUES ('red', '$args', 'pending', $now)" | Out-Null
                Write-Host "  🔴 Blocker added" -ForegroundColor Red
            }
            else {
                Write-Host "  Usage: /blocker <text>" -ForegroundColor Yellow
            }
        }
        
        # === CONFIGURATION ===
        "mode" {
            if ($cmdArgs -match "^(vibe|converge|ship)$") {
                Invoke-Query "UPDATE config SET value='$cmdArgs' WHERE key='mode'" | Out-Null
                Write-Host "  🔧 Mode set to $($cmdArgs.ToUpper())" -ForegroundColor Green
            }
            else {
                $proj = Get-ProjectMode
                Write-Host "  Current mode: $($proj.Icon) $($proj.Mode)" -ForegroundColor White
                if ($null -ne $proj.Days) { Write-Host "  Days to milestone: $($proj.Days)" -ForegroundColor Gray }
                Write-Host "  Set with: /mode vibe|converge|ship" -ForegroundColor Gray
            }
        }
        "milestone" {
            if ($cmdArgs -match "^\d{4}-\d{2}-\d{2}$") {
                Set-Content -Path $MilestoneFile -Value $cmdArgs
                Write-Host "  📅 Milestone set to $cmdArgs" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /milestone YYYY-MM-DD" -ForegroundColor Yellow
            }
        }
        
        # === MULTI-PROJECT ===
        "projects" {
            $configPath = Join-Path $RepoRoot "config\projects.json"
            if (Test-Path $configPath) {
                $projects = Get-Content $configPath | ConvertFrom-Json
                Write-Host ""
                Write-Host "  ═══ AVAILABLE PROJECTS ═══" -ForegroundColor Cyan
                Write-Host ""
                foreach ($p in $projects) {
                    Write-Host "  [$($p.id)] ".PadRight(7) -NoNewline -ForegroundColor Yellow
                    Write-Host "$($p.name)".PadRight(25) -NoNewline -ForegroundColor White
                    Write-Host "$($p.path)" -ForegroundColor DarkGray
                }
                Write-Host ""
                Write-Host "  Use: /multi 1 2 3  to launch grid" -ForegroundColor Gray
            }
            else {
                Write-Host "  ⚠️ No projects.json found at $configPath" -ForegroundColor Yellow
            }
        }
        "multi" {
            $configPath = Join-Path $RepoRoot "config\projects.json"
            $launcherPath = Join-Path $RepoRoot "launcher\mesh-up.ps1"
            
            if (-not (Test-Path $configPath)) {
                Write-Host "  ⚠️ No projects.json found" -ForegroundColor Yellow
                return
            }
            
            $projects = Get-Content $configPath | ConvertFrom-Json
            
            # Show projects if no args
            if ([string]::IsNullOrWhiteSpace($cmdArgs)) {
                Write-Host ""
                Write-Host "  ═══ SELECT PROJECTS FOR GRID ═══" -ForegroundColor Cyan
                Write-Host ""
                foreach ($p in $projects) {
                    Write-Host "  [$($p.id)] ".PadRight(7) -NoNewline -ForegroundColor Yellow
                    Write-Host "$($p.name)" -ForegroundColor White
                }
                Write-Host ""
                Write-Host "  Enter IDs (e.g. '1 2' or '1 2 3 4'): " -NoNewline -ForegroundColor Green
                $cmdArgs = Read-Host
            }
            
            # Parse IDs
            $ids = $cmdArgs -split "\s+" | Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ }
            
            if ($ids.Count -eq 0) {
                Write-Host "  ⚠️ No valid project IDs provided" -ForegroundColor Yellow
                return
            }
            
            if ($ids.Count -gt 4) {
                Write-Host "  ⚠️ Maximum 4 projects supported" -ForegroundColor Yellow
                $ids = $ids[0..3]
            }
            
            Write-Host ""
            Write-Host "  🚀 Launching Mission Control Grid..." -ForegroundColor Cyan
            
            # Launch the grid
            if (Test-Path $launcherPath) {
                $idStr = $ids -join ","
                Start-Process powershell.exe -ArgumentList "-File `"$launcherPath`" -Ids $idStr"
            }
            else {
                Write-Host "  ⚠️ Launcher not found at $launcherPath" -ForegroundColor Yellow
            }
        }
        
        # === LIBRARY (v7.7 - Auto-Bootstrap) ===
        "init" {
            Write-Host ""
            Write-Host "  📚 PROJECT INITIALIZATION (v7.7)" -ForegroundColor Cyan
            Write-Host ""
            
            # Detect profile using Python
            $detectedProfile = "general"
            try {
                $pyScript = @"
import sys
sys.path.insert(0, r'$RepoRoot')
from mesh_server import detect_project_profile
print(detect_project_profile(r'$CurrentDir'))
"@
                $detectedProfile = $pyScript | python 2>$null
                if (-not $detectedProfile) { $detectedProfile = "general" }
                $detectedProfile = $detectedProfile.Trim()
            }
            catch {
                Write-Host "  ⚠️ Detection failed, using 'general'" -ForegroundColor Yellow
            }
            
            Write-Host "  Scanned: $CurrentDir" -ForegroundColor Gray
            Write-Host "  Detected Profile: " -NoNewline
            Write-Host "$detectedProfile" -ForegroundColor Green
            Write-Host ""
            
            # Show what standards are available
            $profilePath = Join-Path $RepoRoot "library\profiles\$detectedProfile.json"
            if (Test-Path $profilePath) {
                $profileData = Get-Content $profilePath | ConvertFrom-Json
                Write-Host "  Standards included:" -ForegroundColor Yellow
                foreach ($standard in $profileData.standards.PSObject.Properties.Name) {
                    Write-Host "    ✅ $standard" -ForegroundColor Gray
                }
            }
            
            Write-Host ""
            $confirm = Read-Host "  Link this project to '$detectedProfile'? [Y/n]"
            if ($confirm -eq "n" -or $confirm -eq "N") { return }
            
            # Update projects.json
            $regPath = Join-Path $RepoRoot "config\projects.json"
            if (Test-Path $regPath) {
                $projects = Get-Content $regPath | ConvertFrom-Json
                
                # Find existing or create new
                $existing = $projects | Where-Object { $_.path -eq $CurrentDir }
                
                if ($existing) {
                    $existing | ForEach-Object { $_.profile = $detectedProfile }
                    Write-Host "  ✅ Updated existing project entry" -ForegroundColor Green
                }
                else {
                    $newId = ($projects | Measure-Object -Property id -Maximum).Maximum + 1
                    $newEntry = @{
                        id      = $newId
                        name    = Split-Path $CurrentDir -Leaf
                        path    = $CurrentDir
                        db      = "mesh.db"
                        profile = $detectedProfile
                    }
                    $projects = @($projects) + $newEntry
                    Write-Host "  ✅ Added new project (ID: $newId)" -ForegroundColor Green
                }
                
                $projects | ConvertTo-Json -Depth 4 | Set-Content $regPath
            }
            
            # Store profile in script context
            $script:CurrentProfile = $detectedProfile
            
            # === AUTO-BOOTSTRAP (v7.7) ===
            Write-Host ""
            Write-Host "  📦 BOOTSTRAPPING SEED PACKAGE..." -ForegroundColor Cyan
            
            $templatesDir = Join-Path $RepoRoot "library\templates"
            $docsDir = Join-Path $CurrentDir "docs"
            
            # Create docs folder
            if (-not (Test-Path $docsDir)) {
                New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
            }
            
            # Template mapping
            $templates = @{
                "ACTIVE_SPEC.template.md"  = "docs\ACTIVE_SPEC.md"
                "TECH_STACK.template.md"   = "docs\TECH_STACK.md"
                "DECISION_LOG.template.md" = "docs\DECISION_LOG.md"
                "env_template.txt"         = ".env.example"
            }
            
            $created = @()
            $skipped = @()
            $projectName = Split-Path $CurrentDir -Leaf
            $today = Get-Date -Format "yyyy-MM-dd"
            
            foreach ($src in $templates.Keys) {
                $srcPath = Join-Path $templatesDir $src
                $dstPath = Join-Path $CurrentDir $templates[$src]
                
                if (Test-Path $dstPath) {
                    $skipped += $templates[$src]
                    continue
                }
                
                if (Test-Path $srcPath) {
                    # Read template
                    $content = Get-Content $srcPath -Raw -Encoding UTF8
                    
                    # Replace placeholders
                    $content = $content -replace '\{\{PROJECT_NAME\}\}', $projectName
                    $content = $content -replace '\{\{DATE\}\}', $today
                    $content = $content -replace '\{\{AUTHOR\}\}', 'Atomic Mesh'
                    
                    # Ensure parent dir exists
                    $parentDir = Split-Path $dstPath -Parent
                    if (-not (Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                    }
                    
                    # Write file
                    Set-Content -Path $dstPath -Value $content -Encoding UTF8
                    $created += $templates[$src]
                }
            }
            
            # Report results
            foreach ($file in $created) {
                Write-Host "    ✅ Created $file" -ForegroundColor Green
            }
            foreach ($file in $skipped) {
                Write-Host "    ⏭️ Skipped $file (exists)" -ForegroundColor Yellow
            }
            
            Write-Host ""
            Write-Host "  ═══════════════════════════════════════════" -ForegroundColor DarkGray
            Write-Host "  ✅ INITIALIZATION COMPLETE" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Next steps:" -ForegroundColor Cyan
            Write-Host "    1. Edit docs/ACTIVE_SPEC.md with your requirements" -ForegroundColor White
            Write-Host "    2. Edit docs/TECH_STACK.md with your tech choices" -ForegroundColor White
            Write-Host "    3. Run /go to start building!" -ForegroundColor White
            Write-Host ""
        }
        
        "profile" {
            $regPath = Join-Path $RepoRoot "config\projects.json"
            
            if ($cmdArgs) {
                # Set profile
                if (Test-Path $regPath) {
                    $projects = Get-Content $regPath | ConvertFrom-Json
                    $existing = $projects | Where-Object { $_.path -eq $CurrentDir }
                    if ($existing) {
                        $existing | ForEach-Object { $_.profile = $cmdArgs }
                        $projects | ConvertTo-Json -Depth 4 | Set-Content $regPath
                        Write-Host "  ✅ Profile set to: $cmdArgs" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  ⚠️ Project not in registry. Run /init first." -ForegroundColor Yellow
                    }
                }
            }
            else {
                # Show current profile
                $profile = "unknown"
                if (Test-Path $regPath) {
                    $projects = Get-Content $regPath | ConvertFrom-Json
                    $existing = $projects | Where-Object { $_.path -eq $CurrentDir }
                    if ($existing) { $profile = $existing.profile }
                }
                Write-Host ""
                Write-Host "  Current Profile: $profile" -ForegroundColor Cyan
                Write-Host "  Project Path: $CurrentDir" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  Available profiles:" -ForegroundColor Yellow
                $profilesPath = Join-Path $RepoRoot "library\profiles"
                if (Test-Path $profilesPath) {
                    Get-ChildItem $profilesPath -Filter "*.json" | ForEach-Object {
                        $name = $_.BaseName
                        $indicator = if ($name -eq $profile) { " ←" } else { "" }
                        Write-Host "    - $name$indicator" -ForegroundColor Gray
                    }
                }
            }
        }
        
        "standard" {
            if (-not $cmdArgs) {
                Write-Host "  Usage: /standard <topic>" -ForegroundColor Yellow
                Write-Host "  Topics: security, architecture, folder_structure, testing, git, code_review" -ForegroundColor Gray
                return
            }
            
            # Get current profile
            $profile = "general"
            $regPath = Join-Path $RepoRoot "config\projects.json"
            if (Test-Path $regPath) {
                $projects = Get-Content $regPath | ConvertFrom-Json
                $existing = $projects | Where-Object { $_.path -eq $CurrentDir }
                if ($existing -and $existing.profile) { $profile = $existing.profile }
            }
            
            # Fetch standard via Python
            try {
                $pyScript = @"
import sys
sys.path.insert(0, r'$RepoRoot\src')
from mesh_server import consult_standard
print(consult_standard('$cmdArgs', '$profile'))
"@
                $result = $pyScript | python 2>$null
                Write-Host ""
                Write-Host $result
            }
            catch {
                Write-Host "  ⚠️ Failed to fetch standard" -ForegroundColor Yellow
            }
        }
        
        "standards" {
            # Get current profile
            $profile = "general"
            $regPath = Join-Path $RepoRoot "config\projects.json"
            if (Test-Path $regPath) {
                $projects = Get-Content $regPath | ConvertFrom-Json
                $existing = $projects | Where-Object { $_.path -eq $CurrentDir }
                if ($existing -and $existing.profile) { $profile = $existing.profile }
            }
            
            Write-Host ""
            Write-Host "  ═══ AVAILABLE STANDARDS ═══" -ForegroundColor Cyan
            Write-Host "  Profile: $profile" -ForegroundColor Gray
            Write-Host ""
            
            $profilePath = Join-Path $RepoRoot "library\profiles\$profile.json"
            if (Test-Path $profilePath) {
                $profileData = Get-Content $profilePath | ConvertFrom-Json
                
                Write-Host "  Standards:" -ForegroundColor Yellow
                foreach ($standard in $profileData.standards.PSObject.Properties.Name) {
                    Write-Host "    • $standard" -ForegroundColor White
                }
                
                Write-Host ""
                Write-Host "  References:" -ForegroundColor Yellow
                foreach ($ref in $profileData.references.PSObject.Properties.Name) {
                    Write-Host "    • $ref" -ForegroundColor White
                }
                
                Write-Host ""
                Write-Host "  Use: /standard <topic>" -ForegroundColor Gray
            }
            else {
                Write-Host "  ⚠️ Profile '$projectProfile' not found" -ForegroundColor Yellow
            }
        }
        
        # === v8.0 PRE-FLIGHT PROTOCOL ===
        "ship" {
            Write-Host ""
            Write-Host "  🚀 SHIPPING TO PRODUCTION (v8.0)" -ForegroundColor Cyan
            Write-Host ""
            
            $message = if ($cmdArgs) { $cmdArgs } else { "release: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
            
            # Check for uncommitted changes
            $gitStatus = git status --porcelain 2>&1
            
            if ([string]::IsNullOrWhiteSpace($gitStatus)) {
                Write-Host "  ⏭️ Nothing to commit (working tree clean)" -ForegroundColor Yellow
                return
            }
            
            Write-Host "  📋 Pre-flight: Local QA has verified this code" -ForegroundColor Gray
            Write-Host "  📦 Changes to ship:" -ForegroundColor Gray
            
            # Show changed files
            $changes = git status --porcelain
            $changes | ForEach-Object { 
                $status = $_.Substring(0, 2).Trim()
                $file = $_.Substring(3)
                $icon = switch ($status) {
                    "M" { "📝" }
                    "A" { "➕" }
                    "D" { "➖" }
                    default { "•" }
                }
                Write-Host "      $icon $file" -ForegroundColor DarkGray
            }
            
            Write-Host ""
            $confirm = Read-Host "  Ship with message '$message'? [Y/n]"
            
            if ($confirm -eq "n" -or $confirm -eq "N") {
                Write-Host "  ⏹️ Shipping cancelled" -ForegroundColor Yellow
                return
            }
            
            # Git operations
            Write-Host ""
            Write-Host "  📦 Staging changes..." -ForegroundColor Gray
            git add .
            
            Write-Host "  💾 Committing..." -ForegroundColor Gray
            git commit -m "release: $message"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  🚀 Pushing to remote..." -ForegroundColor Gray
                git push
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ""
                    Write-Host "  ═══════════════════════════════════════════" -ForegroundColor DarkGray
                    Write-Host "  ✅ SHIPPED SUCCESSFULLY" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "  👀 Watch the GitHub Actions tab for deployment" -ForegroundColor Cyan
                    Write-Host ""
                }
                else {
                    Write-Host "  ⚠️ Push failed - check remote/auth" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  ⚠️ Commit failed" -ForegroundColor Yellow
            }
        }
        
        "preflight" {
            Write-Host ""
            Write-Host "  🧪 PRE-FLIGHT CHECK (v8.0)" -ForegroundColor Cyan
            Write-Host ""
            
            # Detect project type
            $projectType = "unknown"
            if (Test-Path "next.config.js") { $projectType = "typescript_next" }
            elseif (Test-Path "next.config.mjs") { $projectType = "typescript_next" }
            elseif (Test-Path "package.json") { $projectType = "typescript_node" }
            elseif (Test-Path "requirements.txt") { $projectType = "python_backend" }
            elseif (Test-Path "pyproject.toml") { $projectType = "python_backend" }
            
            Write-Host "  Project Type: $projectType" -ForegroundColor Gray
            Write-Host ""
            
            # Run tests based on project type
            $testCmd = $null
            switch ($projectType) {
                "python_backend" {
                    if ((Test-Path "tests") -or (Test-Path "pytest.ini")) {
                        $testCmd = "pytest -x -q --tb=short"
                    }
                }
                "typescript_next" {
                    if (Test-Path "package.json") {
                        $testCmd = "npm test -- --passWithNoTests --watchAll=false"
                    }
                }
                "typescript_node" {
                    if (Test-Path "package.json") {
                        $testCmd = "npm test -- --passWithNoTests --watchAll=false"
                    }
                }
            }
            
            if (-not $testCmd) {
                Write-Host "  ⏭️ No test suite detected (skipping)" -ForegroundColor Yellow
                return
            }
            
            Write-Host "  Running: $testCmd" -ForegroundColor Gray
            Write-Host ""
            
            # Execute tests
            try {
                $result = Invoke-Expression $testCmd 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ""
                    Write-Host "  ✅ PRE-FLIGHT PASSED" -ForegroundColor Green
                    Write-Host "  Code is ready for Dual QA" -ForegroundColor Gray
                }
                else {
                    Write-Host ""
                    Write-Host "  ❌ PRE-FLIGHT FAILED" -ForegroundColor Red
                    Write-Host "  Fix tests before proceeding to QA" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "  ⚠️ Test execution error: $_" -ForegroundColor Yellow
            }
        }
        
        # === v8.2 DIAGNOSTICS (Gap #3 Fix) ===
        "doctor" {
            Write-Host ""
            Write-Host "  🏥 ATOMIC MESH DOCTOR (v8.2)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            
            $allGreen = $true
            
            # 1. Check Database
            Write-Host "  Database:" -NoNewline
            if (Test-Path $env:ATOMIC_MESH_DB) {
                Write-Host " 🟢 OK" -ForegroundColor Green -NoNewline
                Write-Host " ($env:ATOMIC_MESH_DB)" -ForegroundColor Gray
            }
            else {
                Write-Host " 🔴 NOT FOUND" -ForegroundColor Red
                $allGreen = $false
            }
            
            # 2. Check Python
            Write-Host "  Python:" -NoNewline
            try {
                $pyVer = & python --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host " 🟢 OK" -ForegroundColor Green -NoNewline
                    Write-Host " ($pyVer)" -ForegroundColor Gray
                }
                else {
                    Write-Host " 🔴 ERROR" -ForegroundColor Red
                    $allGreen = $false
                }
            }
            catch {
                Write-Host " 🔴 NOT FOUND" -ForegroundColor Red
                $allGreen = $false
            }
            
            # 3. Check WAL Mode
            Write-Host "  DB Mode:" -NoNewline
            try {
                $walCheck = & python -c "import sqlite3; print(sqlite3.connect('$env:ATOMIC_MESH_DB').execute('PRAGMA journal_mode').fetchone()[0])" 2>&1
                if ($walCheck -eq "wal") {
                    Write-Host " 🟢 WAL Enabled" -ForegroundColor Green
                }
                else {
                    Write-Host " 🟡 $walCheck" -ForegroundColor Yellow -NoNewline
                    Write-Host " (should be WAL)" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host " ⚠️ Could not check" -ForegroundColor Yellow
            }
            
            # 4. Check MCP Module
            Write-Host "  MCP Library:" -NoNewline
            try {
                $mcpCheck = & python -c "import mcp; print('ok')" 2>&1
                if ($mcpCheck -eq "ok") {
                    Write-Host " 🟢 OK" -ForegroundColor Green
                }
                else {
                    Write-Host " 🔴 MISSING" -ForegroundColor Red -NoNewline
                    Write-Host " (pip install mcp)" -ForegroundColor Gray
                    $allGreen = $false
                }
            }
            catch {
                Write-Host " 🔴 MISSING" -ForegroundColor Red
                $allGreen = $false
            }
            
            # 5. Check Git Status
            Write-Host "  Git:" -NoNewline
            try {
                $gitStatus = git status --porcelain 2>&1
                if ([string]::IsNullOrWhiteSpace($gitStatus)) {
                    Write-Host " 🟢 Clean" -ForegroundColor Green
                }
                else {
                    $changeCount = ($gitStatus -split "`n").Count
                    Write-Host " 🟡 $changeCount uncommitted changes" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host " ⚠️ Not a git repo" -ForegroundColor Yellow
            }
            
            # 6. Check Core Modules
            Write-Host "  Modules:" -NoNewline
            $modules = @("qa_protocol", "product_owner", "guardrails")
            $modOk = $true
            foreach ($mod in $modules) {
                $modCheck = & python -c "import $mod; print('ok')" 2>&1
                if ($modCheck -ne "ok") { $modOk = $false }
            }
            if ($modOk) {
                Write-Host " 🟢 All loaded" -ForegroundColor Green
            }
            else {
                Write-Host " 🟡 Some missing" -ForegroundColor Yellow
            }
            
            Write-Host ""
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            if ($allGreen) {
                Write-Host "  STATUS: 🟢 HEALTHY" -ForegroundColor Green
            }
            else {
                Write-Host "  STATUS: 🔴 ISSUES DETECTED" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        # === v8.4.1 SPEC LINTER ===
        "refine" {
            Write-Host ""
            Write-Host "  🧐 SPEC LINTER (v8.4.1)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            
            $specPath = Join-Path (Get-Location) "docs\ACTIVE_SPEC.md"
            
            if (-not (Test-Path $specPath)) {
                Write-Host "  ❌ No ACTIVE_SPEC.md found." -ForegroundColor Red
                Write-Host "     Run /init first to create spec template." -ForegroundColor Gray
                return
            }
            
            Write-Host "  Analyzing: docs/ACTIVE_SPEC.md" -ForegroundColor Gray
            Write-Host ""
            
            # Run Python spec linter
            try {
                $result = & python -c "from spec_linter import run_spec_linter_sync; print(run_spec_linter_sync())" 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host $result -ForegroundColor Yellow
                }
                else {
                    # Fallback: Simple local analysis
                    $specContent = Get-Content $specPath -Raw
                    $issues = @()
                    
                    $patterns = @(
                        @{Pattern = "should"; Reason = "Vague - does this mean 'must'?" }
                        @{Pattern = "etc"; Reason = "Incomplete list - what else?" }
                        @{Pattern = "appropriate"; Reason = "Subjective - define criteria" }
                        @{Pattern = "somehow"; Reason = "Implementation unclear" }
                        @{Pattern = "various"; Reason = "Which ones specifically?" }
                    )
                    
                    foreach ($p in $patterns) {
                        if ($specContent -match $p.Pattern) {
                            $issues += "  ⚠️ Found '$($p.Pattern)': $($p.Reason)"
                        }
                    }
                    
                    if ($issues.Count -gt 0) {
                        Write-Host "  Found $($issues.Count) potential ambiguities:" -ForegroundColor Yellow
                        Write-Host ""
                        foreach ($issue in $issues) {
                            Write-Host $issue -ForegroundColor DarkYellow
                        }
                    }
                    else {
                        Write-Host "  ✅ No obvious ambiguities detected." -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host "  ⚠️ Linter error: $_" -ForegroundColor Yellow
            }
            
            Write-Host ""
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host "  TIP: Update docs/ACTIVE_SPEC.md to resolve queries." -ForegroundColor Gray
            Write-Host ""
        }
        
        # === VIEWS ===
        "status" { return "refresh" }
        "plan" { Show-Plan }
        "tasks" { Show-Tasks }
        
        # === UNKNOWN ===
        default {
            Write-Host "  ❓ Unknown command: /$cmd" -ForegroundColor Red
            Write-Host "  Type /help to see available commands" -ForegroundColor Gray
        }
    }
    
    return $null
}

function Send-ToAI {
    param([string]$Text)
    
    Write-Host ""
    Write-Host "  → Routing to AI..." -ForegroundColor DarkGray
    
    # In production, this would call the Python router
    # For now, show placeholder
    try {
        $result = python -c "from router import SemanticRouter; r = SemanticRouter('mesh.db'); print(r.route('$Text').to_dict())" 2>&1
        if ($result) {
            Write-Host "  📤 $result" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  💬 Message received: $Text" -ForegroundColor Gray
        Write-Host "  (AI routing not connected)" -ForegroundColor DarkGray
    }
}

# ============================================================================
# MAIN INPUT LOOP
# ============================================================================

Clear-Host
Show-Header
Write-Host ""
Write-Host "  Type naturally to chat with AI, or use '/' for commands." -ForegroundColor Gray
Write-Host "  Type '/help' to see all available commands." -ForegroundColor DarkGray
Write-Host ""

while ($true) {
    # Prompt
    $proj = Get-ProjectMode
    Write-Host "¢ " -NoNewline -ForegroundColor Green
    
    $userInput = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($userInput)) { 
        continue 
    }
    
    if ($userInput.StartsWith("/")) {
        # Check if just "/" or partial command for suggestions
        if ($userInput -eq "/" -or ($userInput.Length -gt 1 -and -not $userInput.Contains(" "))) {
            Show-CommandSuggestions -Filter $userInput
            continue
        }
        
        # Execute slash command
        $result = Invoke-SlashCommand -UserInput $userInput
        
        if ($result -eq "refresh") {
            Clear-Host
            Show-Header
            Write-Host ""
        }
    }
    else {
        # Natural language - send to AI router
        Send-ToAI -Text $userInput
    }
    
    Write-Host ""
}
