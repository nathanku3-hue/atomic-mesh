# C:\Tools\atomic-mesh\control_panel.ps1
# ATOMIC MESH COMMANDER v7.5 - Slash-Command Edition
# FEATURES: Discord-style /commands, natural language chat, no hotkeys

param()

$CurrentDir = (Get-Location).Path
$DB_FILE = "$CurrentDir\mesh.db"
$LogDir = "$CurrentDir\logs"
$DocsDir = "$CurrentDir\docs"
$MilestoneFile = "$CurrentDir\.milestone_date"
$SpecFile = "$DocsDir\ACTIVE_SPEC.md"

$host.UI.RawUI.WindowTitle = "Atomic Mesh v7.5"

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
    
    Write-Host ""
    Write-Host "┌─ Atomic Mesh v7.5 ─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    $modeStr = "$($proj.Icon) $($proj.Mode)"
    if ($null -ne $proj.Days) { $modeStr += " ($($proj.Days)d)" }
    $statsStr = "$($stats.pending) pending | $($stats.in_progress) active | $($stats.completed) done"
    Write-Host "│  $modeStr    $statsStr" -ForegroundColor White
    Write-Host "└────────────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
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
    param([string]$Input)
    
    # Parse command and args
    $parts = $Input.TrimStart("/").Split(" ", 2)
    $cmd = $parts[0].ToLower()
    $args = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
    
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
                    Write-Host "  📚 Starting Librarian scan..." -ForegroundColor Cyan
                    Write-Host "  (Use MCP tool: librarian_scan)" -ForegroundColor Gray
                }
                "status" {
                    $ops = Invoke-Query "SELECT status, COUNT(*) as c FROM librarian_ops GROUP BY status"
                    Write-Host "  📚 Librarian Status:" -ForegroundColor Cyan
                    foreach ($op in $ops) { Write-Host "    $($op.status): $($op.c)" -ForegroundColor Gray }
                }
                default { Write-Host "  Usage: /lib scan|status|approve|execute" -ForegroundColor Yellow }
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
            if ($args -match "^(vibe|converge|ship)$") {
                Invoke-Query "UPDATE config SET value='$args' WHERE key='mode'" | Out-Null
                Write-Host "  🔧 Mode set to $($args.ToUpper())" -ForegroundColor Green
            }
            else {
                $proj = Get-ProjectMode
                Write-Host "  Current mode: $($proj.Icon) $($proj.Mode)" -ForegroundColor White
                if ($null -ne $proj.Days) { Write-Host "  Days to milestone: $($proj.Days)" -ForegroundColor Gray }
                Write-Host "  Set with: /mode vibe|converge|ship" -ForegroundColor Gray
            }
        }
        "milestone" {
            if ($args -match "^\d{4}-\d{2}-\d{2}$") {
                Set-Content -Path $MilestoneFile -Value $args
                Write-Host "  📅 Milestone set to $args" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /milestone YYYY-MM-DD" -ForegroundColor Yellow
            }
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
    
    $input = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($input)) { 
        continue 
    }
    
    if ($input.StartsWith("/")) {
        # Check if just "/" or partial command for suggestions
        if ($input -eq "/" -or ($input.Length -gt 1 -and -not $input.Contains(" "))) {
            Show-CommandSuggestions -Filter $input
            continue
        }
        
        # Execute slash command
        $result = Invoke-SlashCommand -Input $input
        
        if ($result -eq "refresh") {
            Clear-Host
            Show-Header
            Write-Host ""
        }
    }
    else {
        # Natural language - send to AI router
        Send-ToAI -Text $input
    }
    
    Write-Host ""
}
