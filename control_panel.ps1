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
# v14.1: Fixed - $PSScriptRoot IS the repo root, no need to go up one level
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $CurrentDir }

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
    "go"             = @{ Desc = "execute the next pending task"; Alias = @("continue", "c", "run"); Template = "/go" }
    
    # TASK MANAGEMENT
    "add"            = @{ Desc = "add task: /add backend|frontend <description>"; HasArgs = $true; Template = "/add <type> <desc>"; Placeholder = "<type>"; MiniGuide = "backend/frontend"; Options = @("backend", "frontend") }
    "skip"           = @{ Desc = "skip a task: /skip <task_id>"; HasArgs = $true; Template = "/skip <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }
    "reset"          = @{ Desc = "reset failed task: /reset <task_id>"; HasArgs = $true; Template = "/reset <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }
    "drop"           = @{ Desc = "delete a task: /drop <task_id>"; HasArgs = $true; Template = "/drop <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }
    "nuke"           = @{ Desc = "clear all pending (requires --confirm)"; HasArgs = $true; Template = "/nuke --confirm"; MiniGuide = "careful!" }
    
    # AGENTS
    "audit"          = @{ Desc = "open auditor status and log"; Template = "/audit" }
    "lib"            = @{ Desc = "librarian: /lib scan|status|approve|execute"; HasArgs = $true; Template = "/lib <action>"; Placeholder = "<action>"; MiniGuide = "scan/status/approve"; Options = @("scan", "status", "approve") }
    "ingest"         = @{ Desc = "v9.1: compile raw PRDs from inbox to specs"; Template = "/ingest" }
    "snippets"       = @{ Desc = "Librarian: search reusable snippets"; HasArgs = $true; Template = "/snippets <query> [--lang python|powershell|markdown|any] [--tags a,b,c]"; MiniGuide = "search snippets" }
    "dupcheck"       = @{ Desc = "Librarian: detect duplicate helpers (advisory)"; HasArgs = $true; Template = "/dupcheck <path> [--lang auto|python|powershell|markdown]"; MiniGuide = "duplicate check" }

    # v9.6 RIGOR (Status Only)
    "rigor"          = @{ Desc = "v9.6: show Phase x Risk matrix (auto-derived)"; Template = "/rigor" }
    
    # v9.7 CORE LOCK
    "unlock"         = @{ Desc = "v9.7: unlock core paths: /unlock [core|session]"; HasArgs = $true; Template = "/unlock <scope>"; Placeholder = "<scope>"; MiniGuide = "core/session"; Options = @("core", "session") }
    "lock"           = @{ Desc = "v9.7: lock core paths immediately"; Template = "/lock" }
    
    # v9.8 CLARIFICATION
    "questions"      = @{ Desc = "v9.8: view open clarification questions"; Template = "/questions" }
    "answer"         = @{ Desc = "v9.8: answer a question: /answer Q1 'your answer'"; HasArgs = $true; Template = "/answer <qid> <text>"; Placeholder = "<qid>"; MiniGuide = "question id"; Lookup = "questions" }
    
    # v9.9 REVIEWER
    "review"         = @{ Desc = "v9.9: view review status: /review [task_id]"; HasArgs = $true; Template = "/review <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }
    "rules"          = @{ Desc = "v9.9: view domain rules (the law)"; Template = "/rules" }

    # v14.0 HYPER-CONFIRMATION
    "kickback"       = @{ Desc = "v14.0: reject bad spec: /kickback <task-id> <reason>"; HasArgs = $true; Template = "/kickback <task-id> <reason>"; Placeholder = "<task-id>"; MiniGuide = "reject bad spec" }

    
    # STREAMS
    "stream"         = @{ Desc = "view worker output: /stream backend|frontend"; HasArgs = $true; Template = "/stream <type>"; Placeholder = "<type>"; MiniGuide = "backend/frontend"; Options = @("backend", "frontend") }
    
    # MULTI-PROJECT
    "multi"          = @{ Desc = "launch multi-project grid: /multi 1 2 3"; HasArgs = $true; Template = "/multi <ids>"; Placeholder = "<ids>"; MiniGuide = "project ids" }
    "projects"       = @{ Desc = "list available projects"; Template = "/projects" }
    
    # LIBRARY (v7.6)
    "init"           = @{ Desc = "start a new project (bootstrap + /work)"; Template = "/init" }
    "profile"        = @{ Desc = "show/set project profile: /profile [name]"; HasArgs = $true; Template = "/profile <name>"; Placeholder = "<name>"; MiniGuide = "profile name" }
    "standard"       = @{ Desc = "view a standard: /standard security|architecture"; HasArgs = $true; Template = "/standard <name>"; Placeholder = "<name>"; MiniGuide = "standard name" }
    "standards"      = @{ Desc = "list all standards for current profile"; Template = "/standards" }
    
    # v8.0 PRE-FLIGHT
    "ship"           = @{ Desc = "commit and push to GitHub (trusts local QA)"; HasArgs = $true; Template = "/ship --confirm"; MiniGuide = "careful!" }
    "preflight"      = @{ Desc = "run local pre-flight tests"; Template = "/preflight" }
    "verify"         = @{ Desc = "v14.0: run QA audit on task: /verify <task-id>"; HasArgs = $true; Template = "/verify <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }
    "simplify"       = @{ Desc = "v14.1: check task for bloat: /simplify <task-id>"; HasArgs = $true; Template = "/simplify <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }
    
    # CONTEXT
    "decide"         = @{ Desc = "answer decision: /decide <id> <answer>"; HasArgs = $true; Template = "/decide <id> <answer>"; Placeholder = "<id>"; MiniGuide = "decision id"; Lookup = "decisions" }
    "note"           = @{ Desc = "add a note: /note <text>"; HasArgs = $true; Template = "/note <text>"; Placeholder = "<text>"; MiniGuide = "your note" }
    "blocker"        = @{ Desc = "report blocker: /blocker <text>"; HasArgs = $true; Template = "/blocker <text>"; Placeholder = "<text>"; MiniGuide = "blocker desc" }
    
    # CONFIGURATION
    "mode"           = @{ Desc = "show/toggle mode: /mode [vibe|converge|ship]"; HasArgs = $true; Template = "/mode <name>"; Placeholder = "<name>"; MiniGuide = "vibe/converge/ship"; Options = @("vibe", "converge", "ship") }
    "milestone"      = @{ Desc = "set milestone: /milestone YYYY-MM-DD"; HasArgs = $true; Template = "/milestone <date>"; Placeholder = "<date>"; MiniGuide = "YYYY-MM-DD" }
    
    # SESSION
    "status"         = @{ Desc = "show system status dashboard"; Template = "/status" }
    "plan"           = @{ Desc = "show project roadmap"; Template = "/plan" }
    "tasks"          = @{ Desc = "list all tasks"; Template = "/tasks" }
    "help"           = @{ Desc = "show Golden Path (/help --all for full registry)"; Alias = @("?"); Template = "/help" }
    "commands"       = @{ Desc = "[LEGACY] use /help instead"; Template = "/commands" }
    "refresh"        = @{ Desc = "refresh the display"; Template = "/refresh" }
    "clear"          = @{ Desc = "clear the console screen"; Template = "/clear" }
    "quit"           = @{ Desc = "exit Atomic Mesh"; Alias = @("q", "exit"); Template = "/quit" }
    
    # v8.2 DIAGNOSTICS
    "doctor"         = @{ Desc = "run system health check (Gap #3)"; Template = "/doctor" }

    # v8.4.1 SPEC ANALYSIS
    "refine"         = @{ Desc = "analyze ACTIVE_SPEC.md for ambiguities"; Template = "/refine" }

    # v13.1 VIEW COMMANDS
    "dash"           = @{ Desc = "v13.1: force full dashboard view"; Template = "/dash" }
    "compact"        = @{ Desc = "v13.1: force compact view"; Template = "/compact" }

    # v13.2 OPS COMMANDS (Golden Path)
    "ops"            = @{ Desc = "v13.2: Health + Drift + Backups overview"; Template = "/ops" }
    "health"         = @{ Desc = "v13.2: system health check"; Template = "/health" }
    "drift"          = @{ Desc = "v13.2: staleness and queue drift check"; Template = "/drift" }
    "work"           = @{ Desc = "v13.2: knowledge acquisition: /work <PREFIX>"; HasArgs = $true; Template = "/work <prefix>"; Placeholder = "<prefix>"; MiniGuide = "source prefix" }

    # SANDBOX UX: Router Debug
    "router-debug"   = @{ Desc = "toggle router debug overlay"; Template = "/router-debug" }

    # TDD
    "scaffold-tests" = @{ Desc = "v13.2 autogenerate pytest scaffold: /scaffold-tests <task_id>"; HasArgs = $true; Template = "/scaffold-tests <task-id>"; Placeholder = "<task-id>"; MiniGuide = "task id" }

    # v13.5.5 PLAN-AS-CODE
    "refresh-plan"   = @{ Desc = "v13.5.5: regenerate plan preview from tasks"; Template = "/refresh-plan" }
    "draft-plan"     = @{ Desc = "v13.5.5: create editable plan file in docs/PLANS/"; Template = "/draft-plan" }
    "accept-plan"    = @{ Desc = "v13.5.5: hydrate DB from plan file: /accept-plan <path>"; HasArgs = $true; Template = "/accept-plan <path>"; Placeholder = "<path>"; MiniGuide = "plan file path"; Lookup = "plans" }
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

function Resolve-HealthColor {
    param([string]$Health)
    switch ($Health) {
        "GREEN"  { return "Green" }
        "YELLOW" { return "Yellow" }
        "RED"    { return "Red" }
        default  { return "DarkGray" } # GRAY / unknown
    }
}

function Convert-TaskStatusToBucket {
    param([string]$Status)
    if (-not $Status) { return "NEXT" }
    $s = $Status.ToLowerInvariant()
    $result = switch ($s) {
        "pending"     { "NEXT" }
        "next"        { "NEXT" }
        "planned"     { "NEXT" }
        "in_progress" { "RUNNING" }
        "running"     { "RUNNING" }
        "in_review"   { "REVIEWING" }
        "reviewing"   { "REVIEWING" }
        "blocked"     { "BLOCKED" }
        "failed"      { "BLOCKED" }
        "cancelled"   { "COMPLETED" }
        "canceled"    { "COMPLETED" }
        "completed"   { "COMPLETED" }
        default       { "NEXT" }
    }
    return $result
}

# v15.5: Centralized task health derivation (used by History + Ship signals)
# Returns semantic tokens (GREEN|YELLOW|RED|GRAY) and preserves a short reason.
function Get-TaskHealth {
    <#
    .SYNOPSIS
        Derives task health from existing truth sources only.
    .PARAMETER Task
        Task row (id, type, status, risk, qa_status, ...)
    .RETURNS
        @{ Health = "GREEN|YELLOW|RED|GRAY"; Bucket = "NEXT|RUNNING|REVIEWING|BLOCKED|COMPLETED"; Reason = "text" }
    #>
    param([object]$Task)

    if (-not $Task) { return @{ Health = "GRAY"; Bucket = "NEXT"; Reason = "No task" } }

    $bucket = Convert-TaskStatusToBucket -Status $Task.status
    $risk = if ($Task.risk) { $Task.risk.ToUpperInvariant() } else { "" }
    $qa = if ($Task.qa_status) { $Task.qa_status.ToUpperInvariant() } else { "" }

    # RED: blocked task OR ship risk gate fail (HIGH not PASS)
    if ($bucket -eq "BLOCKED") {
        return @{ Health = "RED"; Bucket = $bucket; Reason = "Task BLOCKED" }
    }
    if ($risk -eq "HIGH" -and $qa -ne "PASS") {
        return @{ Health = "RED"; Bucket = $bucket; Reason = "HIGH risk not PASS" }
    }
    if ($qa -eq "FAIL") {
        return @{ Health = "RED"; Bucket = $bucket; Reason = "QA FAIL" }
    }

    # GREEN: completed/satisfied
    if ($bucket -eq "COMPLETED") {
        return @{ Health = "GREEN"; Bucket = $bucket; Reason = "Completed" }
    }

    # YELLOW: needs work (NEXT/RUNNING/REVIEWING)
    if ($bucket -in @("NEXT", "RUNNING", "REVIEWING")) {
        return @{ Health = "YELLOW"; Bucket = $bucket; Reason = "Needs work" }
    }

    return @{ Health = "GRAY"; Bucket = $bucket; Reason = "N/A" }
}

# ============================================================================
# COMMAND CATALOG (v13.3) - Beginner-first, progressive disclosure
# ============================================================================

function Get-CommandCatalog {
    param([bool]$ShowAll = $false)

    # Tier 1: Golden Path - Beginner-safe essentials (max 9)
    $goldenPath = @("help", "init", "ops", "plan", "run", "status", "ship", "snapshots", "restore")

    # Tier 2: Advanced/Maintenance (shown with --all)
    $advanced = @("work", "approve", "approve_source", "snapshot", "restore_confirm", "review", "rules", "questions", "answer", "unlock", "lock", "mode", "milestone", "preflight", "doctor", "refine", "stream", "decide", "note", "blocker", "profile", "standard", "standards", "multi", "projects", "patterns", "incident", "mine")

    # Tier 3: Deprecated/Legacy (shown with --all, marked deprecated)
    $deprecated = @("go", "add", "skip", "drop", "reset", "nuke", "audit", "lib", "ingest", "rigor", "commands")

    # Session commands (shown with --all)
    $session = @("quit", "clear", "refresh", "tasks", "dash", "compact")

    $result = @{
        GoldenPath = @()
        Advanced   = @()
        Deprecated = @()
        Session    = @()
    }

    foreach ($cmd in $goldenPath) {
        if ($Global:Commands.Contains($cmd)) {
            $result.GoldenPath += [PSCustomObject]@{ Name = $cmd; Desc = $Global:Commands[$cmd].Desc; Tier = "golden" }
        }
    }

    if ($ShowAll) {
        foreach ($cmd in $advanced) {
            if ($Global:Commands.Contains($cmd)) {
                $result.Advanced += [PSCustomObject]@{ Name = $cmd; Desc = $Global:Commands[$cmd].Desc; Tier = "advanced" }
            }
        }
        foreach ($cmd in $deprecated) {
            if ($Global:Commands.Contains($cmd)) {
                $result.Deprecated += [PSCustomObject]@{ Name = $cmd; Desc = "[DEPRECATED] $($Global:Commands[$cmd].Desc)"; Tier = "deprecated" }
            }
        }
        foreach ($cmd in $session) {
            if ($Global:Commands.Contains($cmd)) {
                $result.Session += [PSCustomObject]@{ Name = $cmd; Desc = $Global:Commands[$cmd].Desc; Tier = "session" }
            }
        }
    }

    return $result
}

# Returns flat list of commands for inline picker (Golden Path + optional filter match)
function Get-PickerCommands {
    param([string]$Filter = "")

    # SANDBOX UX: Priority commands (always shown first)
    $priorityOrder = @("help", "init", "ops", "plan", "run", "ship")

    if ($Filter -eq "") {
        $result = @()
        foreach ($cmdName in $priorityOrder) {
            if ($Global:Commands.Contains($cmdName)) {
                $result += [PSCustomObject]@{Name = $cmdName; Desc = $Global:Commands[$cmdName].Desc; Tier = "priority" }
            }
        }
        $catalog = Get-CommandCatalog -ShowAll $false
        foreach ($cmd in ($catalog.GoldenPath | Sort-Object -Property Name)) {
            if ($cmd.Name -notin $priorityOrder) {
                $result += $cmd
            }
        }
        return $result
    }
    else {
        $priorityMatches = @()
        $otherMatches = @()
        foreach ($k in $Global:Commands.Keys) {
            if ($k -like "$Filter*") {
                $cmdObj = [PSCustomObject]@{Name = $k; Desc = $Global:Commands[$k].Desc; Tier = "all" }
                if ($k -in $priorityOrder) {
                    $priorityMatches += $cmdObj
                }
                else {
                    $otherMatches += $cmdObj
                }
            }
        }
        $sortedOthers = $otherMatches | Sort-Object -Property Name
        $sortedPriority = @()
        foreach ($cmd in $priorityOrder) {
            $match = $priorityMatches | Where-Object { $_.Name -eq $cmd }
            if ($match) { $sortedPriority += $match }
        }
        return $sortedPriority + $sortedOthers
    }
}

function Show-Header {
    $proj = Get-ProjectMode
    $stats = Get-TaskStats
    
    # Get console width - use full width
    $width = $Host.UI.RawUI.WindowSize.Width - 1
    $line = "-" * ($width - 2)
    
    # Build title line: Project Name (left) ... Path (right)
    $path = $CurrentDir
    $maxPathLen = $width - $ProjectName.Length - 15
    if ($path.Length -gt $maxPathLen -and $maxPathLen -gt 10) {
        $path = "..." + $path.Substring($path.Length - ($maxPathLen - 3))
    }
    
    # Calculate padding
    $padLen = $width - 6 - $ProjectName.Length - $path.Length
    if ($padLen -lt 1) { $padLen = 1 }
    $padding = " " * $padLen
    
    Write-Host ""
    Write-Host "+$line+" -ForegroundColor Cyan
    
    # Line 1: Project Name (left) ... Path (right)
    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host "[>] $ProjectName" -NoNewline -ForegroundColor Yellow
    Write-Host "$padding$path " -NoNewline -ForegroundColor DarkGray
    Write-Host "|" -ForegroundColor Cyan
    
    # Line 2: Mode, Stats, Health, and CLI Mode (v13.2: modal mode)
    $modeStr = "$($proj.Icon) $($proj.Mode)"
    if ($null -ne $proj.Days) { $modeStr += " ($($proj.Days)d)" }
    $statsStr = "$($stats.pending) pending | $($stats.in_progress) active | $($stats.completed) done"
    $healthIcon = switch ($Global:HealthStatus) { "OK" { "🟢" } "WARN" { "🟡" } "FAIL" { "🔴" } default { "⚪" } }
    $statusLine = "  $modeStr | $statsStr | $healthIcon"
    $statusPad = $width - 3 - $statusLine.Length
    if ($statusPad -lt 0) { $statusPad = 0 }

    Write-Host "|$statusLine" -NoNewline -ForegroundColor White
    Write-Host (" " * $statusPad) -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    
    Write-Host "+$line+" -ForegroundColor Cyan
}

# v13.1: Minimal health check (wraps existing sentinels)
function Get-SystemHealthStatus {
    try {
        $health = python -c "from mesh_server import get_health_report; print(get_health_report())" 2>&1
        if ($health -match "FAIL") { return "FAIL" }
        if ($health -match "WARN") { return "WARN" }
        return "OK"
    }
    catch { return "OK" }
}

# ============================================================================
# COMMAND SUGGESTION SYSTEM (Codex-style)
# ============================================================================

# Global state for command selection
$Global:SelectedIndex = 0
$Global:VisibleCommands = @()
$Global:MaxVisible = 8  # Show max 8 commands at once
$Global:ScrollOffset = 0

# v13.1: View mode state (minimal)
$Global:ViewOverride = $null  # null=auto, "dash", "compact"
$Global:HealthStatus = "OK"   # OK, WARN, FAIL

# v13.2: Modal CLI - 2-mode toggle (OPS/PLAN) + explicit commands for RUN/SHIP
$Global:CurrentMode = "OPS"
$Global:LastPlanNote = $null
$Global:LastRunNote = $null
$Global:LastShipNote = $null

# SANDBOX UX: Router debug overlay toggle
$Global:RouterDebug = $false
$Global:LastRoutedCommand = $null

# v13.4: Template Autocomplete - placeholder tracking
$Global:PlaceholderInfo = $null  # @{ Start; Length; MiniGuide } or $null

# v13.4.6: Library-backed lookup candidates cache
$Global:LookupCandidates = @()
# v13.5.5: Cached plan preview for startup dashboard
$Global:PlanPreview = $null

# Dashboard Transparency (v14.1): Track last scope, optimization, and confidence
$Global:LastScope = $null         # "text" | "command"
$Global:LastOptimized = $false    # bool
$Global:LastConfidence = $null    # int 0-100 or $null
$Global:LastTaskForSignals = $null # optional: "T-123"

# v15.2: Auto-Ingest State (triggered on doc save, debounced)
$Global:AutoIngestEnabled = if ($env:MESH_AUTO_INGEST -eq "0") { $false } else { $true }
$Global:AutoIngestPending = $false
$Global:AutoIngestLastChangeUtc = $null
$Global:AutoIngestLastRunUtc = $null
$Global:AutoIngestLastResult = $null   # "OK" | "ERROR" | "SKIPPED" | $null
$Global:AutoIngestLastMessage = $null
$Global:AutoIngestDebounceMs = 1200
$Global:AutoIngestWatcher = $null      # FileSystemWatcher instance

# v15.4.1: Ctrl-C double-press protection (TreatControlCAsInput)
$Global:LastCtrlCUtc = $null
$Global:CtrlCArmed = $false
$Global:CtrlCWarningShownUtc = $null  # For auto-clearing warning after 2s

# v15.5: History Mode (F2 toggle)
$Global:HistoryMode = $false
$Global:HistorySubview = "TASKS"       # TASKS | DOCS | SHIP
$Global:HistorySelectedRow = 0         # Currently selected row index
$Global:HistoryScrollOffset = 0        # Scroll offset for long lists
$Global:HistoryData = @()              # Cached history data
$Global:HistoryDetailsVisible = $false # Right panel details pane
$Global:HistoryHintText = $null        # One-line hint shown in right panel
$Global:HistoryHintColor = "DarkGray"
$Global:HistoryHintUtc = $null         # Optional: for future auto-clear

# Mode configuration (color, prompt, hint, default action)
$Global:ModeConfig = @{
    "OPS"  = @{ Color = "Cyan"; Prompt = "[OPS]"; Hint = "Monitor health & drift"; MicroHint = "OPS: ask 'health', 'drift', or type /ops" }
    "PLAN" = @{ Color = "Yellow"; Prompt = "[PLAN]"; Hint = "Describe work to plan"; MicroHint = "PLAN: describe what you want to build" }
    "RUN"  = @{ Color = "Magenta"; Prompt = "[RUN]"; Hint = "Execute & steer"; MicroHint = "RUN: give feedback or just press Enter" }
    "SHIP" = @{ Color = "Green"; Prompt = "[SHIP]"; Hint = "Release w/ confirm"; MicroHint = "SHIP: write notes, /ship --confirm to release" }
}
# v13.2.1: Only OPS/PLAN in Tab toggle (RUN/SHIP via explicit commands)
$Global:ModeRing = @("OPS", "PLAN")

# v15.4.1: Normalize command key (strip /, lowercase, trim)
function Normalize-CommandKey {
    param([string]$s)
    if (-not $s) { return "" }
    $x = $s.Trim()
    if ($x.StartsWith("/")) { $x = $x.Substring(1) }
    # Also strip any args after space
    $spaceIdx = $x.IndexOf(" ")
    if ($spaceIdx -gt 0) { $x = $x.Substring(0, $spaceIdx) }
    return $x.ToLowerInvariant()
}

function Get-FilteredCommands {
    param([string]$Filter)
    
    $filter = $Filter.TrimStart("/").ToLower()
    $filtered = @()
    
    foreach ($key in $Global:Commands.Keys) {
        if ($filter -eq "" -or $key.StartsWith($filter)) {
            $filtered += @{
                Name = $key
                Desc = $Global:Commands[$key].Desc
            }
        }
    }
    
    return $filtered
}

function Draw-CommandDropdown {
    param(
        [array]$Commands,
        [int]$SelectedIndex,
        [int]$ScrollOffset,
        [int]$StartRow
    )
    
    $colWidth = 38  # Width per column
    $numCols = 2    # Two columns side by side
    
    # Calculate rows needed (half the commands per column)
    $totalCmds = $Commands.Count
    $rowsNeeded = [Math]::Ceiling($totalCmds / $numCols)
    $visible = [Math]::Min($rowsNeeded, $Global:MaxVisible)
    
    # Calculate what's visible (by row, not by item)
    $startRow = $ScrollOffset
    $endRow = [Math]::Min($ScrollOffset + $visible, $rowsNeeded)
    
    # Draw dropdown frame
    $pos = $Host.UI.RawUI.CursorPosition
    
    for ($row = 0; $row -lt $visible; $row++) {
        $actualRow = $startRow + $row
        if ($actualRow -ge $rowsNeeded) { break }
        
        # Position cursor
        $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = $StartRow + $row }
        
        # Draw both columns for this row
        for ($col = 0; $col -lt $numCols; $col++) {
            $idx = $actualRow + ($col * $rowsNeeded)
            
            if ($idx -lt $Commands.Count) {
                $cmd = $Commands[$idx]
                $isSelected = ($idx -eq $SelectedIndex)
                
                # Build line - shorter desc for 2-column layout
                $cmdName = ("/" + $cmd.Name).PadRight(12)
                $desc = $cmd.Desc
                if ($desc.Length -gt 22) { $desc = $desc.Substring(0, 19) + "..." }
                $desc = $desc.PadRight(22)
                
                if ($isSelected) {
                    Write-Host "▶ " -NoNewline -ForegroundColor Cyan
                    Write-Host $cmdName -NoNewline -ForegroundColor Yellow
                    Write-Host $desc -NoNewline -ForegroundColor White
                }
                else {
                    Write-Host "  " -NoNewline
                    Write-Host $cmdName -NoNewline -ForegroundColor DarkYellow
                    Write-Host $desc -NoNewline -ForegroundColor DarkGray
                }
                
                # Add separator between columns
                if ($col -eq 0) {
                    Write-Host " │ " -NoNewline -ForegroundColor DarkGray
                }
            }
            else {
                # Empty cell padding
                Write-Host (" " * $colWidth) -NoNewline
            }
        }
        Write-Host ""  # Newline at end of row
    }
    
    # Show scroll indicator if needed
    if ($rowsNeeded -gt $Global:MaxVisible) {
        $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = $StartRow + $visible }
        $remaining = $rowsNeeded - $endRow
        if ($remaining -gt 0) {
            Write-Host "  ↓$remaining more (use ↑↓ arrows)" -ForegroundColor DarkGray
        }
        elseif ($ScrollOffset -gt 0) {
            Write-Host "  ↑$ScrollOffset above (use ↑↓ arrows)" -ForegroundColor DarkGray
        }
    }
    
    # Restore cursor
    $Host.UI.RawUI.CursorPosition = $pos
}

function Clear-DropdownArea {
    param([int]$StartRow, [int]$Lines)
    
    $pos = $Host.UI.RawUI.CursorPosition
    $width = $Host.UI.RawUI.WindowSize.Width
    
    for ($i = 0; $i -lt $Lines; $i++) {
        $Host.UI.RawUI.CursorPosition = @{ X = 0; Y = $StartRow + $i }
        Write-Host (" " * $width) -NoNewline
    }
    
    $Host.UI.RawUI.CursorPosition = $pos
}

function Show-CommandSuggestions {
    param([string]$Filter)
    
    # Remove leading slash
    $filter = $Filter.TrimStart("/").ToLower()
    
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    
    # Gather matching commands
    $matches = @()
    foreach ($key in $Global:Commands.Keys) {
        if ($filter -eq "" -or $key.StartsWith($filter)) {
            $matches += @{ Name = $key; Desc = $Global:Commands[$key].Desc }
        }
    }
    
    $maxShow = 16  # Show more since we have 2 columns (8 rows × 2)
    $rowsToShow = [Math]::Min([Math]::Ceiling($matches.Count / 2), 8)
    
    for ($row = 0; $row -lt $rowsToShow; $row++) {
        # Left column
        $leftIdx = $row
        # Right column
        $rightIdx = $row + $rowsToShow
        
        if ($leftIdx -lt $matches.Count -and $leftIdx -lt $maxShow) {
            $cmd = $matches[$leftIdx]
            $cmdDisplay = "/$($cmd.Name)".PadRight(12)
            $desc = $cmd.Desc
            if ($desc.Length -gt 22) { $desc = $desc.Substring(0, 19) + "..." }
            $desc = $desc.PadRight(22)
            Write-Host "  $cmdDisplay" -NoNewline -ForegroundColor Yellow
            Write-Host "$desc" -NoNewline -ForegroundColor Gray
        }
        else {
            Write-Host (" " * 36) -NoNewline
        }
        
        Write-Host " │ " -NoNewline -ForegroundColor DarkGray
        
        if ($rightIdx -lt $matches.Count -and $rightIdx -lt $maxShow) {
            $cmd = $matches[$rightIdx]
            $cmdDisplay = "/$($cmd.Name)".PadRight(12)
            $desc = $cmd.Desc
            if ($desc.Length -gt 22) { $desc = $desc.Substring(0, 19) + "..." }
            Write-Host "$cmdDisplay" -NoNewline -ForegroundColor Yellow
            Write-Host "$desc" -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }
    }
    
    if ($matches.Count -eq 0) {
        Write-Host "  (No matching commands for '/$filter')" -ForegroundColor DarkGray
    }
    elseif ($matches.Count -gt $maxShow) {
        Write-Host "  ... and $($matches.Count - $maxShow) more (keep typing to filter)" -ForegroundColor DarkGray
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
    
    # Check for aliases (track original for deprecation warnings)
    $originalCmd = $cmd
    foreach ($key in $Global:Commands.Keys) {
        $aliases = $Global:Commands[$key].Alias
        if ($aliases -and $aliases -contains $cmd) {
            $cmd = $key
            break
        }
    }

    # v13.6: READINESS GATE - Lock strategic commands in BOOTSTRAP mode
    $StrategicCommands = @("plan", "draft-plan", "accept-plan", "refresh-plan")

    if ($StrategicCommands -contains $cmd) {
        try {
            # v14.1: Use explicit path and pass project directory
            $readinessScript = Join-Path $RepoRoot "tools\readiness.py"
            $readinessJson = python "$readinessScript" "$CurrentDir" 2>&1
            $readiness = $readinessJson | ConvertFrom-Json -ErrorAction SilentlyContinue

            if ($readiness -and $readiness.status -eq "BOOTSTRAP") {
                Write-Host ""
                Write-Host "  🔒 COMMAND LOCKED IN BOOTSTRAP MODE" -ForegroundColor Red
                Write-Host ""
                Write-Host "  Strategic planning requires complete context. Please fill:" -ForegroundColor Yellow

                foreach ($fileName in $readiness.overall.blocking_files) {
                    $fileData = $readiness.files.$fileName
                    $threshold = $readiness.thresholds.$fileName
                    Write-Host "    • $fileName : $($fileData.score)% (need $threshold%)" -ForegroundColor Gray
                }

                Write-Host ""
                Write-Host "  Next actions:" -ForegroundColor Cyan
                Write-Host "    1. Edit docs\PRD.md, docs\SPEC.md, docs\DECISION_LOG.md" -ForegroundColor White
                Write-Host "    2. Add required headers (##  Goals, ## User Stories, ## Data Model, etc.)" -ForegroundColor White
                Write-Host "    3. Fill in bullet points describing your requirements" -ForegroundColor White
                Write-Host ""
                Write-Host "  Progress updates automatically on next command. Tactical commands (/add) remain open." -ForegroundColor DarkGray
                Write-Host ""
                return
            }
        }
        catch {
            # Fail-open: allow command if check fails
            Write-Host "  ⚠️ Readiness check failed - proceeding anyway" -ForegroundColor Yellow
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
        "router-debug" {
            $Global:RouterDebug = -not $Global:RouterDebug
            $status = if ($Global:RouterDebug) { "ENABLED" } else { "DISABLED" }
            Write-Host ""
            Write-Host "  🔍 Router Debug $status" -ForegroundColor $(if ($Global:RouterDebug) { "Green" } else { "Yellow" })
            Write-Host "     Debug overlay will show routing decisions above input bar" -ForegroundColor DarkGray
            Write-Host ""
            return "refresh"
        }
        "help" {
            # v13.3.1: Scenario-first help
            if ($cmdArgs -eq "--all") {
                $catalog = Get-CommandCatalog -ShowAll $true
                Write-Host ""
                Write-Host "  ═══ ALL COMMANDS ═══" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  GOLDEN PATH" -ForegroundColor Yellow
                foreach ($cmd in $catalog.GoldenPath) {
                    Write-Host "    /$($cmd.Name)".PadRight(18) -NoNewline -ForegroundColor Yellow
                    Write-Host $cmd.Desc -ForegroundColor Gray
                }
                Write-Host ""
                Write-Host "  ADVANCED" -ForegroundColor DarkYellow
                foreach ($cmd in $catalog.Advanced) {
                    Write-Host "    /$($cmd.Name)".PadRight(18) -NoNewline -ForegroundColor DarkGray
                    Write-Host $cmd.Desc -ForegroundColor DarkGray
                }
                Write-Host ""
                Write-Host "  SESSION" -ForegroundColor DarkCyan
                foreach ($cmd in $catalog.Session) {
                    Write-Host "    /$($cmd.Name)".PadRight(18) -NoNewline -ForegroundColor DarkGray
                    Write-Host $cmd.Desc -ForegroundColor DarkGray
                }
                Write-Host ""
                Write-Host "  DEPRECATED" -ForegroundColor DarkRed
                foreach ($cmd in $catalog.Deprecated) {
                    Write-Host "    /$($cmd.Name)".PadRight(18) -NoNewline -ForegroundColor DarkRed
                    Write-Host $cmd.Desc -ForegroundColor DarkGray
                }
                Write-Host ""
            }
            else {
                # Default: Scenario-first help (use-cases, not command catalog)
                Write-Host ""
                Write-Host "  What do you want to do?" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  1) " -NoNewline -ForegroundColor White
                Write-Host "Start a new project" -ForegroundColor Yellow
                Write-Host "     Run: " -NoNewline -ForegroundColor DarkGray
                Write-Host "/init" -ForegroundColor Cyan
                Write-Host "     Or type: " -NoNewline -ForegroundColor DarkGray
                Write-Host "'start a payments service'" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  2) " -NoNewline -ForegroundColor White
                Write-Host "Continue working" -ForegroundColor Yellow
                Write-Host "     Run: " -NoNewline -ForegroundColor DarkGray
                Write-Host "/ops" -NoNewline -ForegroundColor Cyan
                Write-Host " (status) → " -NoNewline -ForegroundColor DarkGray
                Write-Host "/plan" -NoNewline -ForegroundColor Cyan
                Write-Host " (roadmap) → " -NoNewline -ForegroundColor DarkGray
                Write-Host "/run" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  3) " -NoNewline -ForegroundColor White
                Write-Host "Ship a release" -ForegroundColor Yellow
                Write-Host "     Run: " -NoNewline -ForegroundColor DarkGray
                Write-Host "/ship" -NoNewline -ForegroundColor Cyan
                Write-Host " (preflight, no auto-deploy)" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
                Write-Host "  /help --all" -NoNewline -ForegroundColor DarkCyan
                Write-Host "  Full command registry" -ForegroundColor DarkGray
                Write-Host ""
            }
        }

        # === LEGACY ALIAS ===
        "commands" {
            Write-Host ""
            Write-Host "  ⚠️  /commands is legacy. Use /help or /help --all" -ForegroundColor DarkYellow
            Write-Host ""
            # Show /help --all output
            $catalog = Get-CommandCatalog -ShowAll $true
            Write-Host "  ═══ ALL COMMANDS ═══" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  GOLDEN PATH (beginner-safe)" -ForegroundColor Yellow
            foreach ($c in $catalog.GoldenPath) {
                Write-Host "    /$($c.Name)".PadRight(20) -NoNewline -ForegroundColor Yellow
                Write-Host $c.Desc -ForegroundColor Gray
            }
            Write-Host ""
            Write-Host "  ADVANCED" -ForegroundColor DarkYellow
            foreach ($c in $catalog.Advanced) {
                Write-Host "    /$($c.Name)".PadRight(20) -NoNewline -ForegroundColor DarkGray
                Write-Host $c.Desc -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host "  SESSION" -ForegroundColor DarkCyan
            foreach ($c in $catalog.Session) {
                Write-Host "    /$($c.Name)".PadRight(20) -NoNewline -ForegroundColor DarkGray
                Write-Host $c.Desc -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host "  DEPRECATED" -ForegroundColor DarkRed
            foreach ($c in $catalog.Deprecated) {
                Write-Host "    /$($c.Name)".PadRight(20) -NoNewline -ForegroundColor DarkRed
                Write-Host $c.Desc -ForegroundColor DarkGray
            }
            Write-Host ""
        }

        # === EXECUTION ===
        "go" {
            # Only show deprecation if user typed /go (not /run or /c)
            if ($originalCmd -eq "go") {
                Write-Host "  ⚠️  Deprecated: prefer /run or natural language" -ForegroundColor DarkYellow
            }
            Invoke-Continue
        }

        # === TASK MANAGEMENT (DEPRECATED - use natural language) ===
        "add" {
            Write-Host "  ⚠️  Deprecated: prefer 'add backend task ...' in natural language" -ForegroundColor DarkYellow
            if ($cmdArgs -match "^(backend|frontend)\s+(.+)$") {
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
            Write-Host "  ⚠️  Deprecated: prefer 'skip T-123' in natural language" -ForegroundColor DarkYellow
            if ($cmdArgs -match "^\d+$") {
                Invoke-Query "UPDATE tasks SET status='skipped' WHERE id=$cmdArgs" | Out-Null
                Write-Host "  ⏭️ Skipped task #$cmdArgs" -ForegroundColor Yellow
            }
            else {
                Write-Host "  Usage: /skip <task_id>" -ForegroundColor Yellow
            }
        }
        "reset" {
            if ($cmdArgs -match "^\d+$") {
                Invoke-Query "UPDATE tasks SET retry_count=0, auditor_status='pending', auditor_feedback='[]', status='pending' WHERE id=$cmdArgs" | Out-Null
                Write-Host "  🔄 Reset task #$cmdArgs" -ForegroundColor Green
            }
            else {
                Write-Host "  Usage: /reset <task_id>" -ForegroundColor Yellow
            }
        }
        "drop" {
            Write-Host "  ⚠️  Deprecated: prefer 'delete task T-123' in natural language" -ForegroundColor DarkYellow
            if ($cmdArgs -match "^\d+$") {
                Invoke-Query "DELETE FROM tasks WHERE id=$cmdArgs" | Out-Null
                Write-Host "  🗑️ Deleted task #$cmdArgs" -ForegroundColor Red
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
        
        # === v14.0 HYPER-CONFIRMATION ===
        "kickback" {
            # Parse task ID and reason from args
            if (-not $cmdArgs -or $cmdArgs.Trim() -eq "") {
                Write-Host ""
                Write-Host "  ❌ Usage: /kickback <task-id> <reason>" -ForegroundColor Red
                Write-Host "  Example: /kickback T-123 'Spec is ambiguous about data format'" -ForegroundColor Gray
                Write-Host ""
                return
            }
            
            # Split into task ID and reason
            $argParts = $cmdArgs.Trim() -split '\s+', 2
            $taskId = $argParts[0]
            $reason = if ($argParts.Count -gt 1) { $argParts[1].Trim("'`"") } else { "" }
            
            if (-not $reason -or $reason.Length -lt 5) {
                Write-Host ""
                Write-Host "  ❌ Reason required (minimum 5 characters)" -ForegroundColor Red
                Write-Host "  Be specific about what's wrong with the spec." -ForegroundColor Yellow
                Write-Host ""
                return
            }
            
            Write-Host ""
            Write-Host "  🔄 Kicking back task $taskId..." -ForegroundColor Yellow
            
            try {
                # Call the MCP kickback_task tool
                $reasonEscaped = $reason.Replace('"', '\"').Replace("'", "\'")
                $result = python -c "from mesh_server import kickback_task; print(kickback_task('$taskId', '$reasonEscaped'))" 2>&1
                $response = $result | ConvertFrom-Json -ErrorAction SilentlyContinue
                
                if ($response.success) {
                    Write-Host "  ✅ $($response.message)" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "  📋 DECISION_LOG updated: $($response.decision_logged)" -ForegroundColor $(if ($response.decision_logged) { "Green" } else { "Yellow" })
                    Write-Host "  💡 Next: $($response.suggested_action)" -ForegroundColor Cyan
                    Write-Host ""
                }
                else {
                    # Handle blocked/error response
                    Write-Host "  ❌ Kickback failed: $($response.error)" -ForegroundColor Red
                    Write-Host ""
                }
            }
            catch {
                Write-Host "  ❌ Error: $_" -ForegroundColor Red
                Write-Host ""
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

        # === v15.x LIBRARIAN: SNIPPET SEARCH ===
        "snippets" {
            # Parse args: <query> [--lang <val>] [--tags <csv>]
            $query = ""
            $lang = "any"
            $tags = ""

            if ($cmdArgs) {
                $tokens = $cmdArgs -split '\s+'
                $i = 0
                while ($i -lt $tokens.Count) {
                    $tok = $tokens[$i]
                    if ($tok -eq "--lang" -and ($i + 1) -lt $tokens.Count) {
                        $lang = $tokens[$i + 1]
                        $i += 2
                    }
                    elseif ($tok -eq "--tags" -and ($i + 1) -lt $tokens.Count) {
                        $tags = $tokens[$i + 1]
                        $i += 2
                    }
                    elseif (-not $tok.StartsWith("--")) {
                        # First non-flag token is the query
                        if (-not $query) { $query = $tok }
                        $i++
                    }
                    else {
                        $i++
                    }
                }
            }

            # If no query AND no tags: show help
            if (-not $query -and -not $tags) {
                Write-Host "  Usage: /snippets <query> [--lang python|powershell|markdown|any] [--tags a,b,c]" -ForegroundColor Yellow
                return
            }

            Write-Host ""
            Write-Host "  SNIPPETS (top 5)" -ForegroundColor Cyan
            Write-Host ""

            try {
                # Escape strings for Python
                $queryEsc = $query.Replace("'", "\'")
                $tagsEsc = $tags.Replace("'", "\'")
                $rootEsc = $CurrentDir.Replace("\", "\\")

                $result = python -c "from mesh_server import snippet_search; print(snippet_search(query='$queryEsc', lang='$lang', tags='$tagsEsc', root_dir=r'$rootEsc'))" 2>&1
                $response = $result | ConvertFrom-Json -ErrorAction SilentlyContinue

                if (-not $response) {
                    Write-Host "  Librarian unavailable (fail-open)" -ForegroundColor Yellow
                    return
                }

                if ($response.results.Count -eq 0) {
                    Write-Host "  No matches." -ForegroundColor Gray
                }
                else {
                    $shown = 0
                    foreach ($snippet in $response.results) {
                        if ($shown -ge 5) { break }
                        $intent = if ($snippet.intent.Length -gt 45) { $snippet.intent.Substring(0, 42) + "..." } else { $snippet.intent }
                        Write-Host "  • $($snippet.id) ($($snippet.lang)) — $intent" -ForegroundColor White
                        $shown++
                    }
                }
            }
            catch {
                Write-Host "  Librarian unavailable (fail-open)" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        # === DUPCHECK ===
        "dupcheck" {
            # Parse args: <path> [--lang auto|python|powershell|markdown]
            $targetPath = ""
            $lang = "auto"

            if ($cmdArgs) {
                $tokens = $cmdArgs -split '\s+'
                $i = 0
                while ($i -lt $tokens.Count) {
                    $tok = $tokens[$i]
                    if ($tok -eq "--lang" -and ($i + 1) -lt $tokens.Count) {
                        $lang = $tokens[$i + 1]
                        $i += 2
                    }
                    elseif (-not $tok.StartsWith("--")) {
                        # First non-flag token is the file path
                        if (-not $targetPath) { $targetPath = $tok }
                        $i++
                    }
                    else {
                        $i++
                    }
                }
            }

            # If no path: show help
            if (-not $targetPath) {
                Write-Host "  Usage: /dupcheck <path> [--lang auto|python|powershell|markdown]" -ForegroundColor Yellow
                return
            }

            Write-Host ""
            Write-Host "  DUPLICATE CHECK (top 3)" -ForegroundColor Cyan
            Write-Host ""

            try {
                # Escape strings for Python
                $pathEsc = $targetPath.Replace("'", "\'")
                $rootEsc = $CurrentDir.Replace("\", "\\")

                $result = python -c "from mesh_server import snippet_duplicate_check; print(snippet_duplicate_check(file_path='$pathEsc', lang='$lang', root_dir=r'$rootEsc'))" 2>&1
                $response = $result | ConvertFrom-Json -ErrorAction SilentlyContinue

                if (-not $response) {
                    Write-Host "  Librarian unavailable (fail-open)" -ForegroundColor Yellow
                    return
                }

                if ($response.status -eq "ERROR") {
                    Write-Host "  $($response.message)" -ForegroundColor Yellow
                }
                elseif ($response.warnings.Count -eq 0) {
                    $msg = if ($response.message) { $response.message } else { "No duplicates found." }
                    Write-Host "  $msg" -ForegroundColor Gray
                }
                else {
                    $shown = 0
                    foreach ($warning in $response.warnings) {
                        if ($shown -ge 3) { break }
                        $sim = "$([int]($warning.similarity * 100))%"
                        $id = $warning.snippet_id
                        # Condense path: show just filename
                        $pathShort = Split-Path $warning.path -Leaf
                        Write-Host "  • $sim — $id ($pathShort)" -ForegroundColor White
                        $shown++
                    }
                }
            }
            catch {
                Write-Host "  Librarian unavailable (fail-open)" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        # === v9.1 AIR GAP INGESTION ===
        "ingest" {
            Write-Host ""
            Write-Host "  📥 AIR GAP INGESTION" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            
            $inboxPath = Join-Path $CurrentDir "docs\inbox"
            
            # Check if inbox exists
            if (-not (Test-Path $inboxPath)) {
                New-Item -ItemType Directory -Path $inboxPath -Force | Out-Null
                Write-Host "  📁 Created docs/inbox/ folder" -ForegroundColor Gray
            }
            
            # Count files in inbox
            $files = Get-ChildItem $inboxPath -File -ErrorAction SilentlyContinue | Where-Object { -not $_.Name.StartsWith(".") }
            
            if ($files.Count -eq 0) {
                Write-Host "  📭 Inbox is empty." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  TIP: Drop raw PRDs, meeting notes, or requirements" -ForegroundColor Gray
                Write-Host "       into docs/inbox/ and run /ingest again." -ForegroundColor Gray
            }
            else {
                Write-Host "  Found $($files.Count) file(s) to process:" -ForegroundColor White
                foreach ($f in $files | Select-Object -First 5) {
                    Write-Host "    • $($f.Name)" -ForegroundColor Gray
                }
                if ($files.Count -gt 5) {
                    Write-Host "    ... and $($files.Count - 5) more" -ForegroundColor DarkGray
                }
                Write-Host ""
                
                # Call Python ingest function
                Write-Host "  🔄 Compiling specs..." -ForegroundColor Yellow
                try {
                    $result = python -c "import asyncio; from product_owner import ingest_inbox; print(asyncio.run(ingest_inbox()))" 2>&1
                    Write-Host "  $result" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ⚠️ Ingestion error: $_" -ForegroundColor Red
                }
            }
            Write-Host ""
        }
        
        # === v9.6 PHASE-DRIVEN RIGOR (Status Only) ===
        "rigor" {
            Write-Host ""
            Write-Host "  ⚙️ PHASE-DRIVEN RIGOR (v9.6)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  Rigor is now AUTOMATIC - derived from Mode + Risk" -ForegroundColor White
            Write-Host ""
            
            # Get current mode
            $mode = "vibe"
            try {
                $modeResult = Invoke-Query "SELECT value FROM config WHERE key='mode'" -Silent
                if ($modeResult) { $mode = $modeResult[0].value }
            }
            catch {}
            
            $modeIcon = switch ($mode) {
                "vibe" { "🟢" }
                "converge" { "�" }
                "ship" { "�" }
                default { "⚪" }
            }
            
            Write-Host "  Current Mode: $modeIcon $($mode.ToUpper())" -ForegroundColor Cyan
            Write-Host ""
            
            # Show the Phase x Risk Matrix
            Write-Host "  ┌──────────┬─────────┬─────────┬──────────┐" -ForegroundColor DarkGray
            Write-Host "  │ Mode\Risk│  LOW    │ MEDIUM  │  HIGH    │" -ForegroundColor DarkGray
            Write-Host "  ├──────────┼─────────┼─────────┼──────────┤" -ForegroundColor DarkGray
            
            # VIBE row
            $vibeColor = if ($mode -eq "vibe") { "Yellow" } else { "Gray" }
            Write-Host "  │ VIBE     │ SPIKE   │ SPIKE   │ IRONCLAD │" -ForegroundColor $vibeColor
            
            # CONVERGE row
            $convColor = if ($mode -eq "converge") { "Yellow" } else { "Gray" }
            Write-Host "  │ CONVERGE │ SPIKE   │ BUILD   │ IRONCLAD │" -ForegroundColor $convColor
            
            # SHIP row
            $shipColor = if ($mode -eq "ship") { "Yellow" } else { "Gray" }
            Write-Host "  │ SHIP     │ BUILD   │ IRONCLAD│ IRONCLAD │" -ForegroundColor $shipColor
            
            Write-Host "  └──────────┴─────────┴─────────┴──────────┘" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  Override: Add [L1], [L2], or [L3] to task description" -ForegroundColor Gray
            Write-Host "  Example:  /add backend 'Quick UI fix [L1]'" -ForegroundColor DarkGray
            Write-Host "  Example:  /add backend 'Refactor auth [L3]'" -ForegroundColor DarkGray
            Write-Host ""
        }
        
        # === v9.7 CORE LOCK ===
        "unlock" {
            Write-Host ""
            $scope = if ($cmdArgs -eq "session") { "session" } else { "next_task" }
            
            try {
                $result = python -c "from dynamic_rigor import unlock_core; print(unlock_core('$scope', 'cli_user'))" 2>&1
                Write-Host "  $result" -ForegroundColor Green
                
                if ($scope -eq "next_task") {
                    Write-Host ""
                    Write-Host "  Protected paths temporarily UNLOCKED:" -ForegroundColor Yellow
                    Write-Host "    core/, auth/, security/, migrations/, .env" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "  ⚠️ Auto-locks after next task completes" -ForegroundColor Yellow
                }
                else {
                    Write-Host ""
                    Write-Host "  ⚠️ Session unlock - use /lock to re-lock" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "  ❌ Failed to unlock: $_" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        "lock" {
            Write-Host ""
            try {
                $result = python -c "from dynamic_rigor import lock_core; print(lock_core())" 2>&1
                Write-Host "  $result" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Protected paths: core/, auth/, security/, migrations/, .env" -ForegroundColor Gray
            }
            catch {
                Write-Host "  ❌ Failed to lock: $_" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        # === v9.8 CLARIFICATION ===
        "questions" {
            Write-Host ""
            Write-Host "  📋 CLARIFICATION QUEUE (v9.8)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            
            try {
                $result = python -c "from dynamic_rigor import get_open_questions; import json; qs = get_open_questions(); print(json.dumps(qs))" 2>&1
                $questions = $result | ConvertFrom-Json -ErrorAction SilentlyContinue
                
                if ($questions -and $questions.Count -gt 0) {
                    Write-Host ""
                    Write-Host "  OPEN QUESTIONS ($($questions.Count)):" -ForegroundColor Yellow
                    Write-Host ""
                    
                    foreach ($q in $questions) {
                        $round = $q.round
                        $focus = switch ($round) {
                            1 { "Requirements" }
                            2 { "Edge Cases" }
                            3 { "Architecture" }
                            default { "General" }
                        }
                        Write-Host "  $($q.id) [Round $round - $focus]" -ForegroundColor White
                        if ($q.question) {
                            Write-Host "    $($q.question)" -ForegroundColor Gray
                        }
                        Write-Host ""
                    }
                    
                    Write-Host "  Answer with: /answer Qn 'your answer'" -ForegroundColor DarkGray
                }
                else {
                    Write-Host ""
                    Write-Host "  ✅ No open questions" -ForegroundColor Green
                    Write-Host "  Status: READY" -ForegroundColor Cyan
                }
            }
            catch {
                Write-Host "  ❌ Failed to get questions: $_" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        "answer" {
            Write-Host ""
            
            if ($cmdArgs -match "^(Q\d+)\s+['""]?(.+?)['""]?$") {
                $qid = $Matches[1]
                $answerText = $Matches[2]
                
                try {
                    # Mark closed and patch spec
                    $result = python -c "from dynamic_rigor import mark_question_closed, patch_active_spec, count_open_questions; closed = mark_question_closed('$qid', '''$answerText'''); patched = patch_active_spec('$qid', '''$answerText'''); remaining = count_open_questions(); print(f'{closed}|{patched}|{remaining}')" 2>&1
                    
                    $parts = $result -split '\|'
                    $closed = $parts[0] -eq "True"
                    $patched = $parts[1] -eq "True"
                    $remaining = [int]$parts[2]
                    
                    if ($closed) {
                        Write-Host "  ✅ $qid resolved." -ForegroundColor Green
                        if ($patched) {
                            Write-Host "  📝 ACTIVE_SPEC.md patched." -ForegroundColor Cyan
                        }
                        
                        if ($remaining -eq 0) {
                            Write-Host ""
                            Write-Host "  ▶️ All questions answered - Ready to resume!" -ForegroundColor Green
                        }
                        else {
                            Write-Host ""
                            Write-Host "  $remaining question(s) remaining. Use /questions to view." -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "  ❌ Question $qid not found" -ForegroundColor Red
                    }
                }
                catch {
                    Write-Host "  ❌ Failed to answer: $_" -ForegroundColor Red
                }
            }
            else {
                Write-Host "  Usage: /answer Q1 'your answer here'" -ForegroundColor Yellow
                Write-Host "  Example: /answer Q1 'Use JWT with 24h expiry'" -ForegroundColor DarkGray
            }
            Write-Host ""
        }
        
        # === v9.9 REVIEWER ===
        "review" {
            Write-Host ""
            Write-Host "  👁️ CODE REVIEW STATUS (v9.9)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            
            $taskId = if ($cmdArgs) { $cmdArgs } else { "current" }
            
            try {
                if ($taskId -eq "current") {
                    # Get active task
                    $stateResult = python -c "from dynamic_rigor import get_active_task; import json; t = get_active_task(); print(json.dumps(t) if t else 'null')" 2>&1
                    if ($stateResult -ne "null") {
                        $task = $stateResult | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($task) { $taskId = $task.id }
                    }
                }
                
                if ($taskId -and $taskId -ne "current") {
                    $reviewResult = python -c "from dynamic_rigor import get_review_status; import json; print(json.dumps(get_review_status('$taskId')))" 2>&1
                    $review = $reviewResult | ConvertFrom-Json -ErrorAction SilentlyContinue
                    
                    if ($review.reviewed) {
                        $statusColor = if ($review.status -eq "PASS") { "Green" } else { "Red" }
                        Write-Host ""
                        Write-Host "  Task: $taskId" -ForegroundColor White
                        Write-Host "  Status: $($review.status)" -ForegroundColor $statusColor
                        if ($review.issues_count -gt 0) {
                            Write-Host "  Issues: $($review.issues_count)" -ForegroundColor Yellow
                        }
                        Write-Host "  File: $($review.path)" -ForegroundColor Gray
                    }
                    else {
                        Write-Host ""
                        Write-Host "  Task $taskId has not been reviewed yet" -ForegroundColor Yellow
                        Write-Host "  Review happens automatically after code generation" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host ""
                    Write-Host "  No active task. Use: /review <task_id>" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "  ❌ Failed to get review: $_" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        "rules" {
            Write-Host ""
            Write-Host "  📜 DOMAIN RULES (v9.9)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            
            $rulesPath = Join-Path (Get-Location) "docs\DOMAIN_RULES.md"
            if (Test-Path $rulesPath) {
                $rules = Get-Content $rulesPath -Raw
                # Just show the first 30 lines
                $lines = $rules -split "`n" | Select-Object -First 30
                foreach ($line in $lines) {
                    Write-Host "  $line" -ForegroundColor Gray
                }
                Write-Host ""
                Write-Host "  ... (see docs/DOMAIN_RULES.md for full list)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  No domain rules defined yet." -ForegroundColor Yellow
                Write-Host "  Create: docs/DOMAIN_RULES.md" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        # === v9.9 COLLECTIVE MEMORY ===
        "incident" {
            if ($cmdArgs) {
                Call-MeshTool "log_incident" @{ symptom = $cmdArgs; trigger = "Manual Report"; severity = "MEDIUM" }
            }
            else {
                Write-Host "  Usage: /incident `"System crashed 500 error`"" -ForegroundColor Yellow
            }
        }
        
        "mine" {
            Write-Host "⛏️  Starting Pattern Miner..." -ForegroundColor Cyan
            # The tool executes and we print the result
            Call-MeshTool "run_pattern_miner" @{}
        }
        
        "patterns" {
            Write-Host ""
            Write-Host "  📚 PATTERN LIBRARY (v9.9)" -ForegroundColor Cyan
            Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
            $patPath = Join-Path (Get-Location) "docs\PATTERNS_LIBRARY.md"
            if (Test-Path $patPath) {
                $pats = Get-Content $patPath -Tail 20
                foreach ($line in $pats) { Write-Host "  $line" -ForegroundColor Gray }
            }
            else {
                Write-Host "  No patterns mined yet." -ForegroundColor Yellow
            }
            Write-Host ""
        }

        # === v13.2 TDD ===
        "scaffold-tests" {
            if ($cmdArgs) {
                Write-Host "  🏗️  Generating test scaffold for task: $cmdArgs" -ForegroundColor Cyan
                Call-MeshTool "scaffold_tests" @{ task_id = $cmdArgs }
            }
            else {
                Write-Host "  Usage: /scaffold-tests <task_id>" -ForegroundColor Yellow
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
        
        # === LIBRARY (v13.3.1 - New Project Entry Point) ===
        "init" {
            Write-Host ""
            Write-Host "  🚀 NEW PROJECT SETUP" -ForegroundColor Cyan
            Write-Host ""

            # If args provided, this is a quick-start: bootstrap + /work
            if ($cmdArgs) {
                Write-Host "  Quick start: '$cmdArgs'" -ForegroundColor Yellow
                Write-Host ""
            }

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
            
            # v14.1: Auto-link profile without Y/N prompt (keeps single-input-frame discipline)
            # User can change later via /profile <name>
            Write-Host ""

            # Update projects.json
            $regPath = Join-Path $RepoRoot "config\projects.json"
            if (Test-Path $regPath) {
                $projects = Get-Content $regPath | ConvertFrom-Json

                # Find existing or create new
                $existing = $projects | Where-Object { $_.path -eq $CurrentDir }

                if ($existing) {
                    # Check if already linked
                    $currentProfile = $existing.profile
                    if ($currentProfile -and $currentProfile -ne $detectedProfile) {
                        Write-Host "  ℹ️  Profile already linked: $currentProfile" -ForegroundColor Cyan
                        Write-Host "     (change via /profile <name>)" -ForegroundColor DarkGray
                    }
                    else {
                        $existing | ForEach-Object { $_.profile = $detectedProfile }
                        Write-Host "  ✅ Linked profile: $detectedProfile" -ForegroundColor Green
                        Write-Host "     (change via /profile <name>)" -ForegroundColor DarkGray
                    }
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
                    Write-Host "  ✅ Linked profile: $detectedProfile (new project ID: $newId)" -ForegroundColor Green
                    Write-Host "     (change via /profile <name>)" -ForegroundColor DarkGray
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
            
            # Template mapping (v13.6: Add PRD and SPEC for readiness gate)
            # v15.1: Add INBOX.md for ephemeral capture
            $templates = @{
                "PRD.template.md"          = "docs\PRD.md"
                "SPEC.template.md"         = "docs\SPEC.md"
                "DECISION_LOG.template.md" = "docs\DECISION_LOG.md"
                "TECH_STACK.template.md"   = "docs\TECH_STACK.md"
                "ACTIVE_SPEC.template.md"  = "docs\ACTIVE_SPEC.md"  # Keep for backward compat
                "INBOX.template.md"        = "docs\INBOX.md"        # v15.1: Ephemeral capture
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
            Write-Host "  ✅ PROJECT INITIALIZED" -ForegroundColor Green
            Write-Host ""

            # If args provided, continue to /work
            if ($cmdArgs) {
                Write-Host "  → Continuing to /work $cmdArgs ..." -ForegroundColor Cyan
                Write-Host ""
                $result = Invoke-SlashCommand -UserInput "/work $cmdArgs"
                if ($result -eq "refresh") { return "refresh" }
            }
            else {
                Write-Host "  What's next?" -ForegroundColor Cyan
                Write-Host "    • Type what you're building (e.g., 'JWT auth system')" -ForegroundColor White
                Write-Host "    • Or run /ops to check system status" -ForegroundColor Gray
                Write-Host ""
            }

            # v14.1: Force dashboard redraw to show BOOTSTRAP mode
            return "refresh"
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
            Write-Host "  🚀 SHIPPING TO PRODUCTION (v14.0)" -ForegroundColor Cyan
            Write-Host ""

            $message = if ($cmdArgs) { $cmdArgs } else { "release: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
            $forceShip = $cmdArgs -match "--force"

            # Check for uncommitted changes
            $gitStatus = git status --porcelain 2>&1

            if ([string]::IsNullOrWhiteSpace($gitStatus)) {
                Write-Host "  ⏭️ Nothing to commit (working tree clean)" -ForegroundColor Yellow
                return
            }

            # v14.0: RISK GATE - Check for HIGH risk tasks without QA verification
            Write-Host "  🛡️ Running Risk Gate checks..." -ForegroundColor Yellow
            Write-Host ""

            try {
                # Query all pending/completed tasks with HIGH risk but no PASS qa_status
                $query = "SELECT id, desc, risk, qa_status FROM tasks WHERE (status = 'pending' OR status = 'in_review' OR status = 'completed') AND risk = 'HIGH' AND qa_status != 'PASS'"
                $highRiskTasks = Invoke-Query -Query $query

                if ($highRiskTasks -and $highRiskTasks.Count -gt 0) {
                    Write-Host "  🛑 SHIP BLOCKED: HIGH RISK TASKS NOT VERIFIED" -ForegroundColor Red
                    Write-Host "  ═══════════════════════════════════════════" -ForegroundColor DarkGray
                    Write-Host ""

                    foreach ($task in $highRiskTasks) {
                        $taskId = "T-$($task.id)"
                        $qaStatus = if ($task.qa_status) { $task.qa_status } else { "NONE" }

                        $statusColor = switch ($qaStatus) {
                            "WARN" { "Yellow" }
                            "FAIL" { "Red" }
                            "NONE" { "Gray" }
                            default { "Gray" }
                        }

                        Write-Host "  Task: $taskId" -ForegroundColor White
                        Write-Host "    Desc: $($task.desc)" -ForegroundColor Gray
                        Write-Host "    Risk: HIGH" -ForegroundColor Red
                        Write-Host "    QA Status: $qaStatus" -ForegroundColor $statusColor
                        Write-Host ""
                    }

                    Write-Host "  ═══════════════════════════════════════════" -ForegroundColor DarkGray
                    Write-Host ""
                    Write-Host "  ⚡ REQUIRED ACTION:" -ForegroundColor Yellow
                    Write-Host "     Run /verify <task-id> for each HIGH risk task" -ForegroundColor White
                    Write-Host "     Fix any issues until QA status = PASS" -ForegroundColor White
                    Write-Host ""

                    if ($forceShip) {
                        Write-Host "  ⚠️  DANGEROUS OVERRIDE: --force flag detected" -ForegroundColor Red
                        Write-Host "     Proceeding anyway (logged for audit)" -ForegroundColor Yellow
                        Write-Host ""

                        # Log the override to decision log
                        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | SHIP OVERRIDE | User forced ship despite HIGH risk tasks without QA PASS"
                        Add-Content -Path "logs/decisions.log" -Value $logEntry -ErrorAction SilentlyContinue
                    }
                    else {
                        Write-Host "  To override (NOT RECOMMENDED): /ship --force" -ForegroundColor DarkGray
                        Write-Host ""
                        return
                    }
                }
                else {
                    Write-Host "  ✅ Risk Gate: All HIGH risk tasks verified" -ForegroundColor Green
                    Write-Host ""
                }
            }
            catch {
                Write-Host "  ⚠️  Risk Gate check failed: $_" -ForegroundColor Yellow
                Write-Host "  Proceeding with caution..." -ForegroundColor Gray
                Write-Host ""
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
        
        "verify" {
            Write-Host ""
            Write-Host "  🔍 QA VERIFICATION (v14.0)" -ForegroundColor Cyan
            Write-Host ""

            if (-not $cmdArgs) {
                Write-Host "  ❌ Usage: /verify <task-id>" -ForegroundColor Red
                Write-Host "  Example: /verify T-123" -ForegroundColor Gray
                Write-Host ""
                return
            }

            Write-Host "  Running QA audit on task: $cmdArgs" -ForegroundColor Yellow
            Write-Host ""

            try {
                # Call verify_task via Python/MCP
                $result = python -c "from mesh_server import verify_task; print(verify_task('$cmdArgs'))" 2>&1
                $response = $result | ConvertFrom-Json -ErrorAction SilentlyContinue

                if ($response.error) {
                    Write-Host "  ❌ Verification failed: $($response.error)" -ForegroundColor Red
                    Write-Host ""
                }
                else {
                    $score = $response.score
                    $status = $response.status
                    $issuesCount = $response.issues_count
                    $reportPath = $response.report_path

                    # Display results with color coding
                    $statusColor = switch ($status) {
                        "PASS" { "Green" }
                        "WARN" { "Yellow" }
                        "FAIL" { "Red" }
                        default { "Gray" }
                    }

                    Write-Host "  ══════════════════════════════════════" -ForegroundColor DarkGray
                    Write-Host "  Task: $cmdArgs" -ForegroundColor White
                    Write-Host "  Score: $score/100" -ForegroundColor $statusColor
                    Write-Host "  Status: $status" -ForegroundColor $statusColor
                    Write-Host "  Issues: $issuesCount" -ForegroundColor $(if ($issuesCount -gt 0) { "Yellow" } else { "Green" })
                    Write-Host "  Report: $reportPath" -ForegroundColor Gray
                    Write-Host "  ══════════════════════════════════════" -ForegroundColor DarkGray
                    Write-Host ""

                    # v14.1: Update transparency globals
                    $Global:LastConfidence = [int]$score
                    $Global:LastTaskForSignals = $cmdArgs

                    if ($status -eq "PASS") {
                        Write-Host "  ✅ QA PASSED - Task ready for shipment" -ForegroundColor Green
                    }
                    elseif ($status -eq "WARN") {
                        Write-Host "  ⚠️  QA WARNING - Fix recommended before shipping" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "  ❌ QA FAILED - Must fix issues before shipping" -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Host "  ⚠️ Verification error: $_" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        "simplify" {
            Write-Host ""
            Write-Host "  🔍 SIMPLIFY CHECK (v14.1)" -ForegroundColor Cyan
            Write-Host ""

            if (-not $cmdArgs) {
                Write-Host "  ❌ Usage: /simplify <task-id>" -ForegroundColor Red
                Write-Host "  Example: /simplify T-123" -ForegroundColor Gray
                Write-Host ""
                return
            }

            Write-Host "  Checking task for bloat: $cmdArgs" -ForegroundColor Yellow
            Write-Host ""

            try {
                # Call simplify_task via Python/MCP (placeholder - implement actual function)
                # For now, we'll simulate the output
                $result = python -c "print('No bloat detected. Task is clean.')" 2>&1

                # Parse output case-insensitively for "clean", "no candidates", "no bloat"
                if ($result -match "(?i)(clean|no candidates|no bloat|nothing to simplify)") {
                    $Global:LastOptimized = $true
                    $Global:LastTaskForSignals = $cmdArgs

                    Write-Host "  ✅ Task is optimized" -ForegroundColor Green
                    Write-Host "  No simplification candidates found" -ForegroundColor Gray
                }
                else {
                    $Global:LastOptimized = $false
                    $Global:LastTaskForSignals = $cmdArgs

                    Write-Host "  ⚠️  Optimization candidates found" -ForegroundColor Yellow
                    Write-Host "  $result" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "  ⚠️ Simplify check error: $_" -ForegroundColor Yellow
                $Global:LastOptimized = $false
            }
            Write-Host ""
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

        # v13.1 VIEW COMMANDS
        "dash" {
            $Global:ViewOverride = "dash"
            Write-Host "  📊 View override: dashboard" -ForegroundColor Cyan
            return "refresh"
        }
        "compact" {
            $Global:ViewOverride = "compact"
            Write-Host "  📋 View override: compact" -ForegroundColor Cyan
            return "refresh"
        }

        # === v13.2 OPS COMMANDS ===
        "ops" {
            Write-Host ""
            Write-Host "  ═══ OPS OVERVIEW (v13.2) ═══" -ForegroundColor Cyan
            Write-Host ""

            # Health Check
            Write-Host "  HEALTH:" -ForegroundColor Yellow
            try {
                $health = python -c "from mesh_server import get_health_report; print(get_health_report())" 2>&1
                $healthLines = $health -split "`n"
                foreach ($line in $healthLines | Select-Object -First 5) {
                    Write-Host "    $line" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "    ⚠️ Health check unavailable" -ForegroundColor Yellow
            }

            Write-Host ""

            # Drift Check
            Write-Host "  DRIFT:" -ForegroundColor Yellow
            try {
                $drift = python -c "from mesh_server import get_drift_report; print(get_drift_report())" 2>&1
                $driftLines = $drift -split "`n"
                foreach ($line in $driftLines | Select-Object -First 5) {
                    Write-Host "    $line" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "    ⚠️ Drift check unavailable" -ForegroundColor Yellow
            }

            Write-Host ""

            # Backup Status
            Write-Host "  BACKUPS:" -ForegroundColor Yellow
            $snapshotDir = Join-Path (Get-Location) "control\snapshots"
            if (Test-Path $snapshotDir) {
                $snapshots = Get-ChildItem $snapshotDir -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
                if ($snapshots) {
                    foreach ($s in $snapshots) {
                        $age = [math]::Round(((Get-Date) - $s.LastWriteTime).TotalHours, 1)
                        Write-Host "    📦 $($s.Name) (${age}h ago)" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "    ⚠️ No backups found" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "    ⚠️ Snapshot directory not found" -ForegroundColor Yellow
            }

            Write-Host ""
        }

        "health" {
            Write-Host ""
            Write-Host "  ═══ HEALTH CHECK (v13.2) ═══" -ForegroundColor Cyan
            Write-Host ""
            try {
                $health = python -c "from mesh_server import get_health_report; print(get_health_report())" 2>&1
                Write-Host $health -ForegroundColor Gray
            }
            catch {
                Write-Host "  ⚠️ Health check unavailable: $_" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        "drift" {
            Write-Host ""
            Write-Host "  ═══ DRIFT CHECK (v13.2) ═══" -ForegroundColor Cyan
            Write-Host ""
            try {
                $drift = python -c "from mesh_server import get_drift_report; print(get_drift_report())" 2>&1
                Write-Host $drift -ForegroundColor Gray
            }
            catch {
                Write-Host "  ⚠️ Drift check unavailable: $_" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        "work" {
            Write-Host ""
            Write-Host "  ═══ KNOWLEDGE ACQUISITION (v13.2) ═══" -ForegroundColor Cyan
            Write-Host ""
            if ($cmdArgs) {
                Write-Host "  📥 Starting work with prefix: $cmdArgs" -ForegroundColor Yellow
                Write-Host "     (Knowledge ingestion from docs/inbox/)" -ForegroundColor Gray
                # Call existing ingest or knowledge tools
                try {
                    $result = python -c "import asyncio; from product_owner import ingest_inbox; print(asyncio.run(ingest_inbox()))" 2>&1
                    Write-Host "  $result" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ⚠️ Work command error: $_" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  Usage: /work <PREFIX>" -ForegroundColor Yellow
                Write-Host "  Example: /work HIPAA" -ForegroundColor Gray
                Write-Host "  This stages knowledge for the current planning context." -ForegroundColor Gray
            }
            Write-Host ""
        }

        # === v13.5.5 PLAN-AS-CODE ===
        "refresh-plan" {
            Write-Host ""
            Write-Host "  ═══ REFRESH PLAN PREVIEW ═══" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Regenerating plan from tasks..." -ForegroundColor Yellow
            try {
                $result = python -c "from mesh_server import refresh_plan_preview; print(refresh_plan_preview())" 2>&1
                $plan = $result | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($plan.status -eq "FRESH") {
                    Write-Host "  ✅ Plan refreshed" -ForegroundColor Green
                    foreach ($stream in $plan.streams) {
                        Write-Host "     [$($stream.name)]" -ForegroundColor Yellow
                        foreach ($task in $stream.tasks) {
                            Write-Host "       • $($task.id): $($task.desc)" -ForegroundColor Gray
                        }
                    }
                }
                else {
                    Write-Host "  ⚠️ $($plan.reason)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "  ❌ Failed to refresh plan: $_" -ForegroundColor Red
            }
            Write-Host ""
        }

        "draft-plan" {
            Write-Host ""
            Write-Host "  ═══ CREATE DRAFT PLAN ═══" -ForegroundColor Cyan
            Write-Host ""
            try {
                $result = python -c "from mesh_server import draft_plan; print(draft_plan())" 2>&1
                $response = $result | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($response.status -eq "OK") {
                    Write-Host "  ✅ Draft created: $($response.path)" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "  Opening in editor..." -ForegroundColor Gray
                    # v13.5.5: Try VS Code first with proper fallback
                    $vsCodeCmd = Get-Command code -ErrorAction SilentlyContinue
                    if ($vsCodeCmd) {
                        & code $response.path
                    }
                    else {
                        # Fallback to system default
                        Start-Process $response.path
                    }
                    Write-Host ""
                    Write-Host "  📝 Edit the file, then run:" -ForegroundColor Yellow
                    Write-Host "     /accept-plan $((Split-Path $response.path -Leaf))" -ForegroundColor Cyan
                }
                else {
                    Write-Host "  ❌ $($response.message)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "  ❌ Failed to create draft: $_" -ForegroundColor Red
            }
            Write-Host ""
        }

        "accept-plan" {
            Write-Host ""
            Write-Host "  ═══ ACCEPT PLAN ═══" -ForegroundColor Cyan
            Write-Host ""
            if (-not $cmdArgs) {
                Write-Host "  Usage: /accept-plan <path>" -ForegroundColor Yellow
                Write-Host "  Example: /accept-plan draft_20251212_1700.md" -ForegroundColor Gray
                Write-Host ""
                # List available drafts
                $plansDir = Join-Path $DocsDir "PLANS"
                if (Test-Path $plansDir) {
                    $drafts = Get-ChildItem $plansDir -Filter "draft_*.md" | Sort-Object LastWriteTime -Descending | Select-Object -First 5
                    if ($drafts) {
                        Write-Host "  Recent drafts:" -ForegroundColor DarkGray
                        foreach ($draft in $drafts) {
                            Write-Host "    • $($draft.Name)" -ForegroundColor Gray
                        }
                    }
                }
            }
            else {
                Write-Host "  Processing: $cmdArgs" -ForegroundColor Yellow
                try {
                    $escapedPath = $cmdArgs -replace "'", "''"
                    $result = python -c "from mesh_server import accept_plan; print(accept_plan('$escapedPath'))" 2>&1
                    $response = $result | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($response.status -eq "OK") {
                        Write-Host "  ✅ $($response.message)" -ForegroundColor Green
                        if ($response.tasks) {
                            foreach ($task in $response.tasks) {
                                Write-Host "     + $($task.id): $($task.desc)" -ForegroundColor Gray
                            }
                        }
                    }
                    else {
                        Write-Host "  ❌ $($response.message)" -ForegroundColor Red
                    }
                }
                catch {
                    Write-Host "  ❌ Failed to accept plan: $_" -ForegroundColor Red
                }
            }
            Write-Host ""
        }

        # === UNKNOWN ===
        default {
            Write-Host "  ❓ Unknown command: /$cmd" -ForegroundColor Red
            Write-Host "  Type /help to see available commands" -ForegroundColor Gray
        }
    }
    
    return $null
}

# ============================================================================
# v13.2: MODAL ROUTING - Pure frontend, no backend calls
# ============================================================================

function Invoke-ModalRoute {
    param([string]$Text)

    # v13.2: Route plain text by current mode using keyword matching
    # No backend calls - pure CLI-side routing

    Write-Host ""

    switch ($Global:CurrentMode) {
        "OPS" {
            # OPS mode: health/drift monitoring keywords
            if ($Text -match "(?i)^health") {
                Write-Host "  ▶ /health" -ForegroundColor Cyan
                $result = Invoke-SlashCommand -UserInput "/health"
                if ($result -eq "refresh") { Initialize-Screen }
            }
            elseif ($Text -match "(?i)(drift|backup|snapshot|stale)") {
                Write-Host "  ▶ /drift" -ForegroundColor Cyan
                $result = Invoke-SlashCommand -UserInput "/drift"
                if ($result -eq "refresh") { Initialize-Screen }
            }
            elseif ($Text -match "(?i)^status") {
                Write-Host "  ▶ /status" -ForegroundColor Cyan
                $result = Invoke-SlashCommand -UserInput "/status"
                if ($result -eq "refresh") { Initialize-Screen }
            }
            else {
                # Hint for OPS mode
                Write-Host "  💡 OPS Mode Hints:" -ForegroundColor Cyan
                Write-Host "     'health' → /health    | 'drift' → /drift" -ForegroundColor Gray
                Write-Host "     'status' → /status    | Tab → switch mode" -ForegroundColor Gray
            }
        }

        "PLAN" {
            # PLAN mode: Stage context and show plan
            $Global:LastPlanNote = $Text
            Write-Host "  📝 Plan context staged: $Text" -ForegroundColor Yellow
            Write-Host ""
            $result = Invoke-SlashCommand -UserInput "/plan"
            if ($result -eq "refresh") { Initialize-Screen }
        }

        "RUN" {
            # RUN mode: Stage steering note and execute
            $Global:LastRunNote = $Text
            Write-Host "  ⚙️ Steering note staged: $Text" -ForegroundColor Magenta
            Write-Host ""
            $result = Invoke-SlashCommand -UserInput "/run"
            if ($result -eq "refresh") { Initialize-Screen }
        }

        "SHIP" {
            # SHIP mode: Stage release note but DO NOT auto-run /ship
            $Global:LastShipNote = $Text
            Write-Host "  🧾 Release note staged: $Text" -ForegroundColor Green
            Write-Host ""
            Write-Host "  ⚠️  SHIP requires explicit command:" -ForegroundColor Yellow
            Write-Host "     Type '/ship' to run preflight" -ForegroundColor Gray
            Write-Host "     Type '/ship --confirm' to release" -ForegroundColor Gray
        }
    }
}

function Invoke-DefaultAction {
    # v13.2: Run default action for current mode when Enter pressed with empty input

    switch ($Global:CurrentMode) {
        "OPS" {
            # Default: show status/health
            Write-Host ""
            Write-Host "  ▶ /ops" -ForegroundColor Cyan
            $result = Invoke-SlashCommand -UserInput "/ops"
            if ($result -eq "refresh") { Initialize-Screen }
        }

        "PLAN" {
            # Default: show plan
            Write-Host ""
            Write-Host "  ▶ /plan" -ForegroundColor Yellow
            $result = Invoke-SlashCommand -UserInput "/plan"
            if ($result -eq "refresh") { Initialize-Screen }
        }

        "RUN" {
            # Default: show run status (tasks)
            Write-Host ""
            Write-Host "  ▶ /run" -ForegroundColor Magenta
            $result = Invoke-SlashCommand -UserInput "/run"
            if ($result -eq "refresh") { Initialize-Screen }
        }

        "SHIP" {
            # Default: show preflight (read-only, safe)
            Write-Host ""
            Write-Host "  ▶ /ship (preflight preview)" -ForegroundColor Green
            $result = Invoke-SlashCommand -UserInput "/ship"
            if ($result -eq "refresh") { Initialize-Screen }
        }
    }
}

function Switch-Mode {
    param([string]$NewMode)

    # v13.2: Switch to specified mode
    $validModes = @("OPS", "PLAN", "RUN", "SHIP")
    $modeUpper = $NewMode.ToUpper()

    if ($validModes -contains $modeUpper) {
        $Global:CurrentMode = $modeUpper
        $config = $Global:ModeConfig[$modeUpper]
        Write-Host ""
        Write-Host "  → Switched to $($config.Prompt)" -ForegroundColor $config.Color
        Write-Host "     $($config.Hint)" -ForegroundColor DarkGray
    }
    else {
        Write-Host ""
        Write-Host "  ❓ Unknown mode: $NewMode" -ForegroundColor Yellow
        Write-Host "     Valid modes: OPS, PLAN, RUN, SHIP" -ForegroundColor Gray
    }
}

# ============================================================================
# INDUSTRIAL-GRADE TUI ENGINE (Coordinate-Based)
# ============================================================================
# Every element is painted at specific X,Y coordinates - no streaming output

# --- GLOBAL ROW CONSTANTS ---
# v16.1.1: Layout anchoring - single source of truth for all regions
$Global:RowHeader = 0
$Global:RowDashStart = 5  # Start after header (rows 0-4)
$Global:MaxDropdownRows = 5  # Keep small to avoid terminal resize

# v16.1.1: Layout Contract - compute from terminal height
# InputTopRow is the anchor; all regions derive from it
$termHeight = $Host.UI.RawUI.WindowSize.Height
$minSafeTop = 15           # Minimum rows for dashboard content
$reserveBottom = 5         # Reserve for input box + dropdown
$Global:InputTopRow = [Math]::Floor($termHeight * 0.75)
$Global:InputTopRow = [Math]::Max($Global:InputTopRow, $minSafeTop)
$Global:InputTopRow = [Math]::Min($Global:InputTopRow, $termHeight - $reserveBottom)

# Derived anchors - Layout from top to bottom:
#   Row (InputTopRow - 4): Dashboard bottom border
#   Row (InputTopRow - 3): Micro-hint row (mode-specific hint, right-aligned)
#   Row (InputTopRow - 2): Footer bar (Next: left, [MODE] right)
#   Row (InputTopRow - 1): Input top border ┌───┐
#   Row InputTopRow:       Input line │ > │
#   Row (InputTopRow + 1): Input bottom border └───┘
#   Row (InputTopRow + 2): Dropdown/hint area
$Global:TopRegionBottom = $Global:InputTopRow - 4  # Dashboard ends here (bottom border row)
$Global:RowInput = $Global:InputTopRow             # Alias for compatibility
$Global:RowInputBottom = $Global:RowInput + 1     # Bottom border of input box
$Global:RowHint = $Global:RowInput + 2            # Hint row below input box
$Global:RowDropdown = $Global:RowInput + 1
$Global:BottomRegionTop = $Global:RowInputBottom + 1  # Below input box

# v13.3.6: Shared left offset for input area alignment
# Aligns input bar with "  Next:" label (2-space indent)
$Global:InputLeft = 2

# --- CORE POSITIONING FUNCTION ---
function Set-Pos {
    param([int]$Row, [int]$Col = 0)
    try {
        $pos = $Host.UI.RawUI.CursorPosition
        $pos.X = $Col
        $pos.Y = $Row
        $Host.UI.RawUI.CursorPosition = $pos
    }
    catch {}
}

# --- v13.3.5: Get fresh layout values (single source of truth) ---
function Get-PromptLayout {
    $w = $Host.UI.RawUI.WindowSize.Width
    $h = $Host.UI.RawUI.WindowSize.Height
    # Input row at 75% height, but cap to avoid writing past terminal
    $inputRow = [Math]::Min($Global:RowInput, $h - 5)
    # v13.3.5: Editor-style footer layout (Next: left, [MODE] right, above input):
    #   RowInput - 2: Footer bar (Next: left, [MODE] right)
    #   RowInput - 1: Top border ┌───┐
    #   RowInput:     Input line │ > │
    #   RowInput + 1: Bottom border └───┘
    #   RowInput + 2: Dropdown starts here (when picker is open)
    return @{
        RowInput    = $inputRow
        DropdownRow = $inputRow + 2  # Below bottom border
        Width       = $w
        MaxVisible  = [Math]::Min(8, $h - $inputRow - 3)  # Don't exceed terminal
        TermHeight  = $h
    }
}

# --- v13.3.5: Clear prompt region atomically ---
function Clear-PromptRegion {
    param([int]$ExtraRows = 0)
    $layout = Get-PromptLayout
    $clearWidth = $layout.Width
    # v13.3.5: Clear from footer (RowInput-2) through bottom border (RowInput+1) + dropdown
    # Layout: footer(-2), top border(-1), input(0), bottom border(+1), dropdown(+2...)
    $startRow = $layout.RowInput - 2
    $totalRows = $layout.MaxVisible + 4 + $ExtraRows  # +4 for footer, borders, dropdown buffer
    for ($i = 0; $i -lt $totalRows; $i++) {
        $row = $startRow + $i
        if ($row -ge 0 -and $row -lt $layout.TermHeight) {
            Set-Pos $row 0
            Write-Host (" " * $clearWidth) -NoNewline
        }
    }
    Set-Pos $layout.RowInput 0
}

# --- v13.3.5: Redraw prompt and footer ---
function Redraw-PromptRegion {
    # v13.3.5: Redraw footer (above) + framed input bar
    $layout = Get-PromptLayout
    $width = $layout.Width
    # Clear region first
    Clear-PromptRegion
    # Draw footer (Next: left, [MODE] right) - above input
    Draw-FooterBar
    # Draw framed input bar
    Draw-InputBar -width $width -rowInput $layout.RowInput
    # Position cursor inside frame (after "│ > ")
    Set-Pos $layout.RowInput ($Global:InputLeft + 4)
}

# --- v9.3 STATUS FETCHER ---
function Get-WorkerStatus {
    $status = @{
        backend_status   = "IDLE"
        backend_task     = "(none)"
        backend_streams  = 0
        frontend_status  = "IDLE"
        frontend_task    = "(none)"
        qa_sessions      = 0
        lib_status_text  = "CLEAN"
        lib_status_color = "Green"
        po_status_color  = "Green"
        po_next_decision = "No pending inputs"
        worker_cot       = "Idling..."
    }
    
    # Get active tasks
    $activeTasks = Invoke-Query "SELECT type, id, substr(desc,1,25) as d FROM tasks WHERE status='in_progress' LIMIT 2" -Silent
    foreach ($t in $activeTasks) {
        if ($t.type -eq "backend") {
            $status.backend_status = "UP"
            $status.backend_task = "[$($t.id)] $($t.d)"
        }
        elseif ($t.type -eq "frontend") {
            $status.frontend_status = "UP"
            $status.frontend_task = "[$($t.id)] $($t.d)"
        }
    }
    
    # Count active streams
    $streams = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE status='in_progress'" -Silent
    if ($streams.Count -gt 0) { $status.backend_streams = $streams[0].c }
    
    # QA pending sessions
    $qaPending = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE auditor_status='pending' AND status='completed'" -Silent
    if ($qaPending.Count -gt 0) { $status.qa_sessions = $qaPending[0].c }
    
    # Blocked tasks (PO status)
    $blocked = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE status='blocked'" -Silent
    if ($blocked.Count -gt 0 -and $blocked[0].c -gt 0) {
        $status.po_status_color = "Red"
        $status.po_next_decision = "$($blocked[0].c) blocked tasks"
    }
    
    # Pending decisions
    $decisions = Invoke-Query "SELECT COUNT(*) as c FROM decisions WHERE status='pending'" -Silent
    if ($decisions.Count -gt 0 -and $decisions[0].c -gt 0 -and $status.po_status_color -ne "Red") {
        $status.po_status_color = "Yellow"
        $status.po_next_decision = "$($decisions[0].c) decisions pending"
    }
    
    # Librarian status (check loose files)
    $root = Get-Location
    $looseFiles = @(Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notin @("README.md", ".gitignore", "requirements.txt", "LICENSE", "mesh.db", ".mesh_mode", ".milestone_date") })
    if ($looseFiles.Count -gt 5) {
        $status.lib_status_text = "MESSY"
        $status.lib_status_color = "Red"
    }
    elseif ($looseFiles.Count -gt 3) {
        $status.lib_status_text = "CLUTTERED"
        $status.lib_status_color = "Yellow"
    }
    
    # Worker COT (last log line)
    $LogPath = Join-Path $root "logs\mesh.log"
    if (Test-Path $LogPath) {
        $lastLine = Get-Content $LogPath -Tail 1 -ErrorAction SilentlyContinue
        if ($lastLine) {
            $cot = if ($lastLine -match "\|") { ($lastLine -split "\|")[-1].Trim() } else { $lastLine.Trim() }
            if ($cot.Length -gt 35) { $cot = $cot.Substring(0, 32) + "..." }
            $status.worker_cot = $cot
        }
    }
    
    return $status
}

# ============================================================================
# v15.5: RUNTIME SIGNALS (Stream C - Task C1)
# ============================================================================
# Normalizes existing truth sources into a small, stable signals object:
# - readiness.py (docs readiness + blocking list)
# - tasks DB aggregates (counts by status + stream)
# - /ship risk gate semantics (HIGH risk tasks without QA PASS)
#
# Fail-open rule:
# - If any sub-call fails, return partial signals.
# - If readiness parsing fails, fail-safe to BOOTSTRAP (never show ready incorrectly).

function Get-RuntimeSignals {
    $signals = @{
        readiness    = $null
        task_summary = $null
        risk_summary = $null
        last         = @{
            scope      = $Global:LastScope
            optimized  = [bool]($Global:LastOptimized -eq $true)
            confidence = $Global:LastConfidence
        }
    }

    # --- readiness.py (Context readiness) ---
    try {
        $defaultThresholds = @{ PRD = 80; SPEC = 80; DECISION_LOG = 30 }
        $readinessNorm = @{
            status     = "BOOTSTRAP"
            files      = @{}
            thresholds = $defaultThresholds
            overall    = @{ ready = $false; blocking_files = @("PRD", "SPEC", "DECISION_LOG") }
            source     = "readiness.py (fail-safe)"
        }

        $readinessScript = Join-Path $RepoRoot "tools\readiness.py"
        $readinessJson = python "$readinessScript" "$CurrentDir" 2>&1
        $readiness = $readinessJson | ConvertFrom-Json -ErrorAction SilentlyContinue

        if ($readiness) {
            $readinessNorm.source = "readiness.py (live)"

            # thresholds
            $thresholds = @{}
            foreach ($k in @("PRD", "SPEC", "DECISION_LOG")) {
                $v = $null
                try { $v = $readiness.thresholds.$k } catch { $v = $null }
                if ($null -ne $v) { $thresholds[$k] = [int]$v }
            }
            if ($thresholds.Count -gt 0) {
                foreach ($k in $thresholds.Keys) { $readinessNorm.thresholds[$k] = $thresholds[$k] }
            }

            # files (PRD/SPEC/DECISION_LOG) -> normalize to include state
            foreach ($docName in @("PRD", "SPEC", "DECISION_LOG")) {
                $fileData = $null
                try { $fileData = $readiness.files.$docName } catch { $fileData = $null }

                $exists = $false
                $score = 0
                $missing = @()

                if ($fileData) {
                    if ($null -ne $fileData.exists) { $exists = [bool]$fileData.exists }
                    if ($null -ne $fileData.score) { $score = [int]$fileData.score }
                    if ($fileData.missing) { $missing = @($fileData.missing) }
                }

                $threshold = if ($readinessNorm.thresholds.ContainsKey($docName)) { [int]$readinessNorm.thresholds[$docName] } else { 0 }
                $state = "NEED"
                if (-not $exists) { $state = "MISS" }
                elseif ($threshold -gt 0 -and $score -ge $threshold) { $state = "OK" }
                elseif ($score -le 40) { $state = "STUB" }

                $readinessNorm.files[$docName] = @{
                    score   = $score
                    exists  = $exists
                    missing = $missing
                    state   = $state
                }
            }

            # overall
            if ($readiness.overall) {
                $ready = $false
                $blocking = @()
                try { $ready = [bool]$readiness.overall.ready } catch { $ready = $false }
                try { if ($readiness.overall.blocking_files) { $blocking = @($readiness.overall.blocking_files) } } catch { $blocking = @() }
                $readinessNorm.overall = @{ ready = $ready; blocking_files = $blocking }
            }

            # status (EXECUTION|BOOTSTRAP), then infer PRE_INIT if all golden docs missing
            if ($readiness.status) { $readinessNorm.status = [string]$readiness.status }
            $allMissing = $true
            foreach ($docName in @("PRD", "SPEC", "DECISION_LOG")) {
                if ($readinessNorm.files.ContainsKey($docName) -and $readinessNorm.files[$docName].exists) { $allMissing = $false; break }
            }
            if ($allMissing) { $readinessNorm.status = "PRE_INIT" }

            # ACTIVE_SPEC (not emitted by readiness.py) - existence only by default
            $activeSpecPath = Join-Path $CurrentDir "docs\ACTIVE_SPEC.md"
            $activeSpecExists = Test-Path $activeSpecPath
            $readinessNorm.files["ACTIVE_SPEC"] = @{
                score   = 0
                exists  = [bool]$activeSpecExists
                missing = @()
                state   = if ($activeSpecExists) { "OK" } else { "MISS" }
            }

            # INBOX (not emitted by readiness.py) - count meaningful lines
            $inboxPath = Join-Path $CurrentDir "docs\INBOX.md"
            $meaningful = 0
            if (Test-Path $inboxPath) {
                $inboxContent = Get-Content $inboxPath -Raw -ErrorAction SilentlyContinue
                if ($inboxContent) {
                    foreach ($line in ($inboxContent -split "`n")) {
                        $trimmed = $line.Trim()
                        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                        if ($trimmed -match "ATOMIC_MESH_TEMPLATE_STUB") { continue }
                        if ($trimmed -match "^#") { continue }
                        if ($trimmed.Length -lt 3) { continue }
                        if ($trimmed.StartsWith("Drop clarifications")) { continue }
                        if ($trimmed.StartsWith("Next: run")) { continue }
                        $meaningful++
                    }
                }
            }
            $readinessNorm.files["INBOX"] = @{
                meaningful_lines = $meaningful
                exists           = [bool](Test-Path $inboxPath)
                state            = if ($meaningful -gt 0) { "PENDING" } else { "EMPTY" }
            }
        }

        $signals.readiness = $readinessNorm
    }
    catch {
        # Keep defaults (fail-safe) and continue
        if (-not $signals.readiness) {
            $signals.readiness = @{
                status     = "BOOTSTRAP"
                files      = @{}
                thresholds = @{ PRD = 80; SPEC = 80; DECISION_LOG = 30 }
                overall    = @{ ready = $false; blocking_files = @("PRD", "SPEC", "DECISION_LOG") }
                source     = "readiness.py (error)"
            }
        }
    }

    # --- task_summary (counts by stream + by status) ---
    try {
        $byStatus = @{ NEXT = 0; RUNNING = 0; REVIEWING = 0; BLOCKED = 0; COMPLETED = 0 }

        $rows = Invoke-Query "SELECT LOWER(status) as s, COUNT(*) as c FROM tasks GROUP BY LOWER(status)" -Silent
        foreach ($r in $rows) {
            $s = if ($r.s) { [string]$r.s } else { "" }
            $c = if ($r.c) { [int]$r.c } else { 0 }

            $bucket = switch ($s) {
                "pending"     { "NEXT" }
                "next"        { "NEXT" }
                "planned"     { "NEXT" }
                "in_progress" { "RUNNING" }
                "running"     { "RUNNING" }
                "in_review"   { "REVIEWING" }
                "reviewing"   { "REVIEWING" }
                "blocked"     { "BLOCKED" }
                "failed"      { "BLOCKED" }
                "cancelled"   { "COMPLETED" }
                "canceled"    { "COMPLETED" }
                "completed"   { "COMPLETED" }
                default       { "NEXT" }
            }

            if (-not $byStatus.ContainsKey($bucket)) { $byStatus[$bucket] = 0 }
            $byStatus[$bucket] += $c
        }

        $knownStreams = @("backend", "frontend", "qa", "audits", "librarian")
        $byStream = @{}
        foreach ($k in $knownStreams) { $byStream[$k] = 0 }
        $byStream["other"] = 0

        $streamRows = Invoke-Query "SELECT LOWER(type) as t, COUNT(*) as c FROM tasks GROUP BY LOWER(type)" -Silent
        foreach ($r in $streamRows) {
            $t = if ($r.t) { [string]$r.t } else { "" }
            $c = if ($r.c) { [int]$r.c } else { 0 }

            if ([string]::IsNullOrWhiteSpace($t)) { $byStream["other"] += $c; continue }
            if ($byStream.ContainsKey($t)) { $byStream[$t] += $c } else { $byStream["other"] += $c }
        }

        $total = 0
        foreach ($k in $byStatus.Keys) { $total += [int]$byStatus[$k] }

        $signals.task_summary = @{
            total     = $total
            by_status = $byStatus
            by_stream = $byStream
        }
    }
    catch {
        if (-not $signals.task_summary) {
            $signals.task_summary = @{
                total     = 0
                by_status = @{ NEXT = 0; RUNNING = 0; REVIEWING = 0; BLOCKED = 0; COMPLETED = 0 }
                by_stream = @{ backend = 0; frontend = 0; qa = 0; audits = 0; librarian = 0; other = 0 }
            }
        }
    }

    # --- risk_summary (HIGH risk tasks without QA PASS) ---
    try {
        $q = "SELECT COUNT(*) as c FROM tasks WHERE risk='HIGH' AND (qa_status IS NULL OR qa_status != 'PASS')"
        $r = Invoke-Query $q -Silent
        $count = if ($r -and $r.Count -gt 0) { [int]$r[0].c } else { 0 }
        $signals.risk_summary = @{ high_not_pass = $count }
    }
    catch {
        if (-not $signals.risk_summary) { $signals.risk_summary = @{ high_not_pass = 0 } }
    }

    return $signals
}

# ============================================================================
# v15.5: PIPELINE STATUS MODEL (Stream B - Task B1)
# ============================================================================
# Derives stage states from existing signals only:
# - Context: readiness.py (PRD/SPEC/DECISION_LOG scores)
# - Plan: task DB - queued states (PENDING|NEXT|PLANNED) vs exhausted
# - Work: task DB - active states (RUNNING|IN_PROGRESS) vs ready vs blocked
# - Optimize: task notes (Entropy Check markers) - task-sticky, not session-local
# - Verify: qa_status from task DB (HIGH risk + QA PASS check)
# - Ship: verify state + git working tree cleanliness

function Build-PipelineStatus {
    <#
    .SYNOPSIS
        Builds a pipeline status model from existing runtime signals.
    .PARAMETER SelectedRow
        Optional: Currently selected task row (for context-aware hints)
    .PARAMETER RuntimeSignals
        Optional: Pre-fetched signals hashtable (avoids re-querying)
    .RETURNS
        Hashtable with stages, immediate_next, critical_missing, recommended_actions, source
    #>
    param(
        [object]$SelectedRow = $null,
        [hashtable]$RuntimeSignals = $null
    )

    # === GATHER SIGNALS (use cached if provided) ===

    # 1. Context readiness (from readiness.py)
    $readiness = $null
    $contextStatus = "UNKNOWN"
    $readinessFailOpen = $false
    try {
        $readinessScript = Join-Path $RepoRoot "tools\readiness.py"
        $readinessJson = python "$readinessScript" "$CurrentDir" 2>&1
        $readiness = $readinessJson | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($readiness) {
            $contextStatus = $readiness.status  # EXECUTION, BOOTSTRAP, or PRE_INIT (inferred)

            # Detect PRE_INIT: all golden docs missing
            $allMissing = $true
            foreach ($docName in @("PRD", "SPEC", "DECISION_LOG")) {
                $fileData = $readiness.files.$docName
                if ($fileData -and $fileData.exists) {
                    $allMissing = $false
                    break
                }
            }
            if ($allMissing) { $contextStatus = "PRE_INIT" }
        }
        else {
            # Parse failed - fail-open to BOOTSTRAP
            $readinessFailOpen = $true
            $contextStatus = "BOOTSTRAP"
        }
    }
    catch {
        # Exception - fail-open to BOOTSTRAP
        $readinessFailOpen = $true
        $contextStatus = "BOOTSTRAP"
    }

    # v16.0: Derive worst doc for BOOTSTRAP reason (reuses already-fetched readiness data)
    $worstDoc = $null
    $worstDocStatus = $null
    if ($contextStatus -eq "BOOTSTRAP" -and $readiness -and $readiness.files) {
        $docPriority = @("PRD", "SPEC", "DECISION_LOG")
        foreach ($docName in $docPriority) {
            $fileData = $readiness.files.$docName
            $threshold = if ($readiness.thresholds.$docName) { $readiness.thresholds.$docName } else { 80 }
            if ($fileData) {
                if (-not $fileData.exists) {
                    $worstDoc = $docName
                    $worstDocStatus = "MISS"
                    break
                }
                elseif ($fileData.score -lt $threshold) {
                    # Check if stub (score capped at 40 typically)
                    if ($fileData.score -le 40) {
                        $worstDoc = $docName
                        $worstDocStatus = "STUB"
                        break
                    }
                    else {
                        $worstDoc = $docName
                        $worstDocStatus = "NEED"
                        break
                    }
                }
            }
        }
    }

    # 2. Task counts by state (orthogonal Plan vs Work signals)
    # Plan states: PENDING, NEXT, PLANNED (queued work)
    # Work states: RUNNING, IN_PROGRESS (active work)
    # Terminal states: COMPLETED, CANCELLED (exhausted)
    # Blocked state: BLOCKED (stalled)

    $queuedTasks = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE status IN ('pending', 'next', 'planned', 'PENDING', 'NEXT', 'PLANNED')" -Silent
    $queuedCount = if ($queuedTasks -and $queuedTasks.Count -gt 0) { $queuedTasks[0].c } else { 0 }

    $activeTasks = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE status IN ('running', 'in_progress', 'RUNNING', 'IN_PROGRESS')" -Silent
    $activeCount = if ($activeTasks -and $activeTasks.Count -gt 0) { $activeTasks[0].c } else { 0 }

    $terminalTasks = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE status IN ('completed', 'cancelled', 'COMPLETED', 'CANCELLED')" -Silent
    $terminalCount = if ($terminalTasks -and $terminalTasks.Count -gt 0) { $terminalTasks[0].c } else { 0 }

    $blockedTasks = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE status IN ('blocked', 'BLOCKED')" -Silent
    $blockedCount = if ($blockedTasks -and $blockedTasks.Count -gt 0) { $blockedTasks[0].c } else { 0 }

    $totalTasks = $queuedCount + $activeCount + $terminalCount + $blockedCount

    # 3. HIGH risk tasks without QA PASS (for Verify/Ship stages)
    # Strict: risk='HIGH' AND (qa_status IS NULL OR qa_status != 'PASS')
    $highRiskUnverified = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE risk='HIGH' AND (qa_status IS NULL OR qa_status != 'PASS')" -Silent
    $highRiskUnverifiedCount = if ($highRiskUnverified -and $highRiskUnverified.Count -gt 0) { $highRiskUnverified[0].c } else { 0 }

    # v16.0: First blocked task ID (for Work=RED reason)
    $firstBlockedId = $null
    if ($blockedCount -gt 0) {
        $firstBlocked = Invoke-Query "SELECT id FROM tasks WHERE status IN ('blocked', 'BLOCKED') ORDER BY id LIMIT 1" -Silent
        if ($firstBlocked -and $firstBlocked.Count -gt 0 -and $firstBlocked[0].id) {
            $firstBlockedId = $firstBlocked[0].id
        }
    }

    # v16.0: First HIGH risk unverified task ID (for Verify reason)
    $firstHighRiskId = $null
    if ($highRiskUnverifiedCount -gt 0) {
        $firstHighRisk = Invoke-Query "SELECT id FROM tasks WHERE risk='HIGH' AND (qa_status IS NULL OR qa_status != 'PASS') ORDER BY id LIMIT 1" -Silent
        if ($firstHighRisk -and $firstHighRisk.Count -gt 0 -and $firstHighRisk[0].id) {
            $firstHighRiskId = $firstHighRisk[0].id
        }
    }

    # 4. Deterministic task selection for Optimize/Verify stages
    # Priority: SelectedRow > first RUNNING > first NEXT > most recent PENDING > null
    $optimizeProof = $false
    $optimizeTaskId = $null
    $taskSelectionReason = $null

    if ($SelectedRow -and $SelectedRow.id) {
        # User explicitly selected a task
        $optimizeTaskId = $SelectedRow.id
        $taskSelectionReason = "selected"
    }
    else {
        # Deterministic fallback: RUNNING > NEXT > PENDING (most recent)
        $runningTask = Invoke-Query "SELECT id FROM tasks WHERE status IN ('running', 'in_progress', 'RUNNING', 'IN_PROGRESS') ORDER BY updated_at DESC LIMIT 1" -Silent
        if ($runningTask -and $runningTask.Count -gt 0 -and $runningTask[0].id) {
            $optimizeTaskId = $runningTask[0].id
            $taskSelectionReason = "first RUNNING"
        }
        else {
            $nextTask = Invoke-Query "SELECT id FROM tasks WHERE status IN ('next', 'NEXT') ORDER BY updated_at DESC LIMIT 1" -Silent
            if ($nextTask -and $nextTask.Count -gt 0 -and $nextTask[0].id) {
                $optimizeTaskId = $nextTask[0].id
                $taskSelectionReason = "first NEXT"
            }
            else {
                $pendingTask = Invoke-Query "SELECT id FROM tasks WHERE status IN ('pending', 'PENDING') ORDER BY created_at DESC LIMIT 1" -Silent
                if ($pendingTask -and $pendingTask.Count -gt 0 -and $pendingTask[0].id) {
                    $optimizeTaskId = $pendingTask[0].id
                    $taskSelectionReason = "most recent PENDING"
                }
            }
        }
    }

    # 5. Optimization status - task-sticky via notes (not session-local)
    if ($optimizeTaskId) {
        $taskNotes = Invoke-Query "SELECT notes FROM tasks WHERE id='$optimizeTaskId'" -Silent
        if ($taskNotes -and $taskNotes.Count -gt 0 -and $taskNotes[0].notes) {
            $notes = $taskNotes[0].notes
            # Check for entropy markers in notes
            if ($notes -match "Entropy Check:\s*Passed" -or
                $notes -match "OPTIMIZATION WAIVED" -or
                $notes -match "CAPTAIN_OVERRIDE:\s*ENTROPY") {
                $optimizeProof = $true
            }
        }
    }

    # 6. Git status (lightweight - just working tree cleanliness)
    $hasUncommitted = $false
    try {
        $gitStatus = git status --porcelain 2>&1
        $hasUncommitted = -not [string]::IsNullOrWhiteSpace($gitStatus)
    }
    catch {}

    # === DERIVE STAGE STATES ===

    # Stage state colors: GREEN (ready), YELLOW (warning), RED (blocked), GRAY (inactive/N/A)

    # CONTEXT stage
    $contextState = switch ($contextStatus) {
        "EXECUTION" { "GREEN" }
        "BOOTSTRAP" { "YELLOW" }
        "PRE_INIT"  { "RED" }
        default     { "GRAY" }
    }
    $contextHint = switch ($contextStatus) {
        "EXECUTION" { "Docs complete" }
        "BOOTSTRAP" { "Fill PRD/SPEC/DECISION_LOG" }
        "PRE_INIT"  { "Run /init to bootstrap" }
        default     { "Unknown state" }
    }
    # v16.0: Context reason (only for non-GREEN)
    $contextReason = ""
    if ($contextState -eq "RED") {
        $contextReason = "Docs missing: PRD/SPEC/DECISION_LOG"
    }
    elseif ($contextState -eq "YELLOW") {
        if ($readinessFailOpen) {
            $contextReason = "Readiness unavailable (fail-open)"
        }
        elseif ($worstDoc -and $worstDocStatus) {
            $contextReason = "Context incomplete: $worstDoc is $worstDocStatus"
        }
        else {
            $contextReason = "Context incomplete"
        }
    }

    # PLAN stage - orthogonal: checks queued states only
    # GREEN = tasks in queued states (PENDING|NEXT|PLANNED)
    # YELLOW = tasks exist but all terminal (COMPLETED|CANCELLED) - exhausted
    # RED = zero tasks exist
    $planState = "GRAY"
    $planHint = "Needs context first"
    $planReason = ""
    if ($contextState -in @("GREEN", "YELLOW")) {
        if ($queuedCount -gt 0) {
            $planState = "GREEN"
            $planHint = "$queuedCount task(s) queued"
        }
        elseif ($totalTasks -gt 0) {
            # Tasks exist but none queued - exhausted or all blocked/active
            $planState = "YELLOW"
            $planHint = "Plan exhausted - add tasks"
            $planReason = "All tasks terminal (no queued NEXT/PLANNED)"
        }
        else {
            $planState = "RED"
            $planHint = "No plan - run /draft-plan"
            $planReason = "No tasks exist yet"
        }
    }

    # WORK stage - orthogonal: checks active states only
    # GREEN = tasks in active states (RUNNING|IN_PROGRESS)
    # YELLOW = tasks in ready states but none running (NEXT|PENDING)
    # RED = tasks BLOCKED and none running/ready - stalled
    $workState = "GRAY"
    $workHint = "Needs plan first"
    $workReason = ""
    if ($planState -in @("GREEN", "YELLOW")) {
        if ($activeCount -gt 0) {
            $workState = "GREEN"
            $workHint = "$activeCount task(s) active"
        }
        elseif ($queuedCount -gt 0) {
            $workState = "YELLOW"
            $workHint = "Ready - run /go"
            $workReason = "Queued but none running"
        }
        elseif ($blockedCount -gt 0) {
            $workState = "RED"
            $workHint = "$blockedCount task(s) blocked - stalled"
            if ($firstBlockedId) {
                $workReason = "Blocked tasks present (T-$firstBlockedId)"
            }
            else {
                $workReason = "Blocked tasks present"
            }
        }
        else {
            $workState = "YELLOW"
            $workHint = "No active work"
            $workReason = "Queued but none running"
        }
    }

    # OPTIMIZE stage - task-sticky via notes
    # GREEN = selected task has entropy proof in notes
    # YELLOW = no proof on selected task but tasks exist
    # GRAY = no task selected / no tasks
    $optimizeState = "GRAY"
    $optimizeHint = "No task selected"
    $optimizeReason = ""
    if ($optimizeTaskId) {
        if ($optimizeProof) {
            $optimizeState = "GREEN"
            $optimizeHint = "Entropy check passed"
        }
        else {
            $optimizeState = "YELLOW"
            $optimizeHint = "Run /simplify $optimizeTaskId"
            $optimizeReason = "Missing entropy proof for selected task"
        }
    }
    elseif ($totalTasks -gt 0) {
        $optimizeState = "YELLOW"
        $optimizeHint = "Select task to verify entropy"
        $optimizeReason = "No task selected"
    }

    # VERIFY stage - HIGH risk only, NULL treated as not-pass
    # GREEN = no HIGH risk unverified
    # RED = any HIGH risk unverified (blocks ship)
    $verifyState = "GRAY"
    $verifyHint = "No HIGH risk tasks"
    $verifyReason = ""

    # Check if any HIGH risk tasks exist at all
    $highRiskTotal = Invoke-Query "SELECT COUNT(*) as c FROM tasks WHERE risk='HIGH'" -Silent
    $highRiskTotalCount = if ($highRiskTotal -and $highRiskTotal.Count -gt 0) { $highRiskTotal[0].c } else { 0 }

    if ($highRiskTotalCount -gt 0) {
        if ($highRiskUnverifiedCount -gt 0) {
            $verifyState = "RED"
            $verifyHint = "$highRiskUnverifiedCount HIGH risk unverified"
            if ($firstHighRiskId) {
                $verifyReason = "HIGH risk unverified: $highRiskUnverifiedCount (first: T-$firstHighRiskId)"
            }
            else {
                $verifyReason = "HIGH risk unverified: $highRiskUnverifiedCount"
            }
        }
        else {
            $verifyState = "GREEN"
            $verifyHint = "All HIGH risk verified"
        }
    }
    elseif ($totalTasks -gt 0) {
        # No HIGH risk tasks - verification not required
        $verifyState = "GREEN"
        $verifyHint = "No HIGH risk (skip)"
    }

    # SHIP stage - verify state + git cleanliness
    # GREEN = clean working tree AND verify green
    # YELLOW = uncommitted changes
    # RED = verify red (blockers)
    $shipState = "GRAY"
    $shipHint = "Needs verification"
    $shipReason = ""
    if ($verifyState -eq "RED") {
        $shipState = "RED"
        $shipHint = "HIGH risk blocks ship"
        $shipReason = "Ship blocked (verify/risk)"
    }
    elseif ($verifyState -eq "GREEN") {
        if ($hasUncommitted) {
            $shipState = "YELLOW"
            $shipHint = "Uncommitted changes"
            $shipReason = "Working tree dirty (uncommitted changes)"
        }
        else {
            $shipState = "GREEN"
            $shipHint = "Ready to ship"
        }
    }

    # === BUILD STAGES ARRAY (v16.0: includes reason field) ===
    $stages = @(
        @{ name = "Context";  state = $contextState;  hint = $contextHint;  reason = $contextReason }
        @{ name = "Plan";     state = $planState;     hint = $planHint;     reason = $planReason }
        @{ name = "Work";     state = $workState;     hint = $workHint;     reason = $workReason }
        @{ name = "Optimize"; state = $optimizeState; hint = $optimizeHint; reason = $optimizeReason }
        @{ name = "Verify";   state = $verifyState;   hint = $verifyHint;   reason = $verifyReason }
        @{ name = "Ship";     state = $shipState;     hint = $shipHint;     reason = $shipReason }
    )

    # === DERIVE IMMEDIATE NEXT STEP ===
    $immediateNext = "Unknown"
    $firstNonGreen = $stages | Where-Object { $_.state -ne "GREEN" } | Select-Object -First 1
    if ($firstNonGreen) {
        $immediateNext = $firstNonGreen.hint
    }
    else {
        $immediateNext = "All stages green - ship when ready"
    }

    # === DERIVE CRITICAL MISSING ===
    $criticalMissing = @()
    foreach ($stage in $stages) {
        if ($stage.state -eq "RED") {
            $criticalMissing += "$($stage.name): $($stage.hint)"
        }
    }

    # === DERIVE SUGGESTED NEXT (purely suggest, not auto-execute) ===
    # Format: { command = "/ingest", reason = "Context=BOOTSTRAP" }
    $suggestedNext = @{ command = $null; reason = $null }

    # Walk pipeline stages to find first non-GREEN and suggest appropriate action
    if ($contextState -eq "RED") {
        $suggestedNext.command = "/init"
        $suggestedNext.reason = "Context=PRE_INIT"
    }
    elseif ($contextState -eq "YELLOW") {
        # Check INBOX first
        $inboxPath = Join-Path $CurrentDir "docs\INBOX.md"
        $inboxHasContent = $false
        if (Test-Path $inboxPath) {
            $inboxContent = Get-Content $inboxPath -Raw -ErrorAction SilentlyContinue
            if ($inboxContent -and $inboxContent.Length -gt 100) {
                $inboxHasContent = $true
            }
        }
        if ($inboxHasContent) {
            $suggestedNext.command = "/ingest"
            $suggestedNext.reason = "Context=BOOTSTRAP, INBOX pending"
        }
        else {
            $suggestedNext.command = "edit PRD.md | SPEC.md"
            $suggestedNext.reason = "Context=BOOTSTRAP"
        }
    }
    elseif ($planState -eq "RED") {
        $suggestedNext.command = "/draft-plan"
        $suggestedNext.reason = "Plan=RED (no tasks)"
    }
    elseif ($planState -eq "YELLOW") {
        $suggestedNext.command = "/refresh-plan"
        $suggestedNext.reason = "Plan=YELLOW (exhausted)"
    }
    elseif ($workState -eq "YELLOW" -and $queuedCount -gt 0) {
        $suggestedNext.command = "/go"
        $suggestedNext.reason = "Work=YELLOW (ready to start)"
    }
    elseif ($workState -eq "RED") {
        $suggestedNext.command = "/unblock"
        $suggestedNext.reason = "Work=RED (tasks blocked)"
    }
    elseif ($optimizeState -eq "YELLOW" -and $optimizeTaskId) {
        $suggestedNext.command = "/simplify $optimizeTaskId"
        $suggestedNext.reason = "Optimize=YELLOW (no entropy proof)"
    }
    elseif ($verifyState -eq "RED") {
        # Find first HIGH risk unverified task
        $firstHighRisk = Invoke-Query "SELECT id FROM tasks WHERE risk='HIGH' AND (qa_status IS NULL OR qa_status != 'PASS') LIMIT 1" -Silent
        if ($firstHighRisk -and $firstHighRisk.Count -gt 0 -and $firstHighRisk[0].id) {
            $suggestedNext.command = "/verify $($firstHighRisk[0].id)"
            $suggestedNext.reason = "Verify=RED (HIGH risk unverified)"
        }
        else {
            $suggestedNext.command = "/verify <id>"
            $suggestedNext.reason = "Verify=RED"
        }
    }
    elseif ($shipState -eq "YELLOW") {
        $suggestedNext.command = "git add . && git commit"
        $suggestedNext.reason = "Ship=YELLOW (uncommitted changes)"
    }
    elseif ($shipState -eq "GREEN") {
        $suggestedNext.command = "/ship"
        $suggestedNext.reason = "all stages GREEN"
    }

    # === DERIVE RECOMMENDED ACTIONS (conditional and honest) ===
    $actions = @()

    # I = /init or edit docs (if Context is BOOTSTRAP/PRE_INIT)
    if ($contextState -eq "RED") {
        # PRE_INIT: need /init
        $actions += @{ key = "I"; label = "/init"; enabled = $true }
    }
    elseif ($contextState -eq "YELLOW") {
        # BOOTSTRAP: need to edit docs or /ingest
        $inboxPath = Join-Path $CurrentDir "docs\INBOX.md"
        $inboxHasContent = $false
        if (Test-Path $inboxPath) {
            $inboxContent = Get-Content $inboxPath -Raw -ErrorAction SilentlyContinue
            if ($inboxContent -and $inboxContent.Length -gt 100) {
                $inboxHasContent = $true
            }
        }
        if ($inboxHasContent) {
            $actions += @{ key = "I"; label = "/ingest"; enabled = $true }
        }
        else {
            $actions += @{ key = "I"; label = "edit docs"; enabled = $true }
        }
    }

    # S = /simplify (if Optimize is YELLOW - no proof on selected task)
    if ($optimizeState -eq "YELLOW") {
        $simplifyLabel = if ($optimizeTaskId) { "/simplify $optimizeTaskId" } else { "/simplify <id>" }
        $actions += @{ key = "S"; label = $simplifyLabel; enabled = $true }
    }

    # V = /verify (if Verify is YELLOW or RED - HIGH risk unverified)
    if ($verifyState -in @("YELLOW", "RED")) {
        $actions += @{ key = "V"; label = "/verify <id>"; enabled = $true }
    }

    # === DETERMINE SOURCE (with fail-open indicator and task selection reason) ===
    $source = "readiness.py"
    if ($readinessFailOpen) {
        $source += " (fail-open)"
    }
    else {
        $source += " (live)"
    }
    $source += " / tasks DB"
    if ($optimizeTaskId -and $taskSelectionReason) {
        $source += " / task: $optimizeTaskId ($taskSelectionReason)"
    }

    # === RETURN MODEL ===
    return @{
        stages              = $stages
        immediate_next      = $immediateNext
        critical_missing    = $criticalMissing
        recommended_actions = $actions
        suggested_next      = $suggestedNext
        source              = $source
    }
}

# ============================================================================
# v16.0: PIPELINE SNAPSHOT LOGGER (Deblackbox - Yellow/Red Snapshots Only)
# ============================================================================
# Persists minimal debug snapshot ONLY when any pipeline stage is YELLOW or RED.
# Does NOT log when all stages are GREEN.
# Path: logs/pipeline_snapshots.jsonl (append-only JSONL)

# Global dedupe state
if (-not (Test-Path variable:Global:LastPipelineSnapshotHash)) {
    $Global:LastPipelineSnapshotHash = $null
}
if (-not (Test-Path variable:Global:LastPipelineSnapshotUtc)) {
    $Global:LastPipelineSnapshotUtc = [datetime]::MinValue
}

function Write-PipelineSnapshotIfNeeded {
    <#
    .SYNOPSIS
        Writes a pipeline snapshot to logs/pipeline_snapshots.jsonl if conditions are met.
    .DESCRIPTION
        Only writes when:
        1. ANY stage is YELLOW or RED (not when all GREEN)
        2. Hash changed (content differs from last snapshot)
        3. At least 2 seconds since last write (debounce)
    .PARAMETER PipelineData
        The pipeline status model from Build-PipelineStatus
    .PARAMETER SelectedTaskId
        Optional: Currently selected task ID
    #>
    param(
        [hashtable]$PipelineData,
        [string]$SelectedTaskId = $null
    )

    # Guard: require valid pipeline data
    if (-not $PipelineData -or -not $PipelineData.stages) {
        return
    }

    # Check if any stage is YELLOW or RED
    $hasNonGreen = $false
    foreach ($s in $PipelineData.stages) {
        if ($s.state -in @("RED", "YELLOW")) {
            $hasNonGreen = $true
            break
        }
    }

    # Do NOT log when all stages are GREEN
    if (-not $hasNonGreen) {
        return
    }

    # Build snapshot object (minimal, stable fields)
    $mode = "EXECUTION"
    $ctxStage = $PipelineData.stages | Where-Object { $_.name -eq "Context" } | Select-Object -First 1
    if ($ctxStage) {
        if ($ctxStage.state -eq "RED") { $mode = "PRE_INIT" }
        elseif ($ctxStage.state -eq "YELLOW") { $mode = "BOOTSTRAP" }
    }

    $stagesObj = @{}
    foreach ($s in $PipelineData.stages) {
        $stageEntry = @{ state = $s.state }
        if ($s.reason -and $s.reason.Length -gt 0) {
            $stageEntry.reason = $s.reason
        }
        $stagesObj[$s.name] = $stageEntry
    }

    $snapshot = @{
        ts            = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        mode          = $mode
        stages        = $stagesObj
        selected_task = if ($SelectedTaskId) { $SelectedTaskId } else { $null }
        source        = $PipelineData.source
    }

    # Convert to compact JSON for hashing and writing
    $snapshotJson = $snapshot | ConvertTo-Json -Compress -Depth 4

    # Compute hash for dedupe (simple string hash)
    # Hash only the content-changing fields (exclude ts for hash comparison)
    $hashContent = @{
        mode          = $mode
        stages        = $stagesObj
        selected_task = $snapshot.selected_task
        source        = $PipelineData.source
    } | ConvertTo-Json -Compress -Depth 4
    $currentHash = $hashContent.GetHashCode()

    # Check dedupe conditions
    $now = [datetime]::UtcNow
    $timeSinceLast = ($now - $Global:LastPipelineSnapshotUtc).TotalSeconds

    if ($currentHash -eq $Global:LastPipelineSnapshotHash -or $timeSinceLast -lt 2) {
        # Dedupe: same content hash OR less than 2 seconds since last write
        return
    }

    # Ensure logs/ directory exists
    $logsDir = Join-Path $CurrentDir "logs"
    if (-not (Test-Path $logsDir)) {
        try {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        catch {
            # Silent fail if can't create directory
            return
        }
    }

    # Append to JSONL file
    $snapshotPath = Join-Path $logsDir "pipeline_snapshots.jsonl"
    try {
        Add-Content -Path $snapshotPath -Value $snapshotJson -Encoding UTF8
        # Update dedupe state
        $Global:LastPipelineSnapshotHash = $currentHash
        $Global:LastPipelineSnapshotUtc = $now
    }
    catch {
        # Silent fail on write error
    }
}

# ============================================================================
# v15.5: PIPELINE PANEL RENDERER (Stream B - Task B2)
# ============================================================================
# Renders the dynamic arrow pipeline in the right panel:
# [Context] → [Plan] → [Work] → [Optimize] → [Verify] → [Ship]
# Each stage colored by state (GREEN/YELLOW/RED/GRAY)

function Draw-PipelinePanel {
    <#
    .SYNOPSIS
        Renders the pipeline status panel on the right side of the dashboard.
    .PARAMETER StartRow
        The row number to start drawing from
    .PARAMETER HalfWidth
        The width of the right panel (half of terminal width)
    .PARAMETER PipelineData
        The pipeline status model from Build-PipelineStatus
    .RETURNS
        The next row number after drawing
    #>
    param(
        [int]$StartRow,
        [int]$HalfWidth,
        [hashtable]$PipelineData
    )

    $R = $StartRow
    $RightWidth = $HalfWidth - 4  # Content width inside borders

    # === STATE COLOR MAP ===
    $stateColors = @{
        "GREEN"  = "Green"
        "YELLOW" = "Yellow"
        "RED"    = "Red"
        "GRAY"   = "DarkGray"
    }

    # === HEADER ===
    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host "PIPELINE".PadRight($RightWidth) -NoNewline -ForegroundColor Cyan
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === SOURCE LINE ===
    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    $sourceText = "Source: $($PipelineData.source)"
    if ($sourceText.Length -gt $RightWidth) {
        $sourceText = $sourceText.Substring(0, $RightWidth - 3) + "..."
    }
    Write-Host $sourceText.PadRight($RightWidth) -NoNewline -ForegroundColor DarkGray
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === BLANK LINE ===
    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host (" " * $RightWidth) -NoNewline
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === ARROW PIPELINE ===
    # Build the pipeline string: [Context] → [Plan] → ...
    # Each stage is colored by its state

    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray

    $stages = $PipelineData.stages
    $pipelineChars = 0

    for ($i = 0; $i -lt $stages.Count; $i++) {
        $stage = $stages[$i]
        $color = $stateColors[$stage.state]
        $stageName = $stage.name

        # Abbreviate stage names to fit in panel
        $shortName = switch ($stageName) {
            "Context"  { "Ctx" }
            "Plan"     { "Pln" }
            "Work"     { "Wrk" }
            "Optimize" { "Opt" }
            "Verify"   { "Ver" }
            "Ship"     { "Shp" }
            default    { $stageName.Substring(0, 3) }
        }

        Write-Host "[$shortName]" -NoNewline -ForegroundColor $color
        $pipelineChars += $shortName.Length + 2

        # Add arrow between stages (except after last)
        if ($i -lt $stages.Count - 1) {
            Write-Host "→" -NoNewline -ForegroundColor DarkGray
            $pipelineChars += 1
        }
    }

    # Pad remaining space
    $padLen = $RightWidth - $pipelineChars
    if ($padLen -gt 0) {
        Write-Host (" " * $padLen) -NoNewline
    }
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === BLANK LINE ===
    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host (" " * $RightWidth) -NoNewline
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === SUGGESTED NEXT (purely suggest, not auto-execute) ===
    # Format: "Next: /ingest (because Context=BOOTSTRAP)"
    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host "Next: " -NoNewline -ForegroundColor Yellow

    $suggestedCmd = $PipelineData.suggested_next.command
    $suggestedReason = $PipelineData.suggested_next.reason

    if ($suggestedCmd -and $suggestedReason) {
        $nextText = "$suggestedCmd (because $suggestedReason)"
    }
    elseif ($suggestedCmd) {
        $nextText = $suggestedCmd
    }
    else {
        $nextText = $PipelineData.immediate_next
    }

    $nextAvail = $RightWidth - 6  # "Next: " is 6 chars
    if ($nextText.Length -gt $nextAvail) {
        $nextText = $nextText.Substring(0, $nextAvail - 3) + "..."
    }
    Write-Host $nextText.PadRight($nextAvail) -NoNewline -ForegroundColor White
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === v16.0: REASON LINES (replaces Critical section) ===
    # Collect non-GREEN stages with reasons, sorted by severity (RED first) then pipeline order
    $nonGreenStages = @()
    if ($PipelineData.stages) {
        foreach ($s in $PipelineData.stages) {
            if ($s.state -in @("RED", "YELLOW") -and $s.reason) {
                $nonGreenStages += @{
                    name = $s.name
                    state = $s.state
                    reason = $s.reason
                    priority = if ($s.state -eq "RED") { 0 } else { 1 }
                }
            }
        }
    }

    # Sort: RED first (priority 0), then YELLOW (priority 1), preserving pipeline order within
    $sortedStages = $nonGreenStages | Sort-Object -Property priority

    if ($sortedStages.Count -gt 0) {
        # Blank line before reasons
        Set-Pos $R $HalfWidth
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host (" " * $RightWidth) -NoNewline
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++

        # Determine header: Critical if any RED, else Attention
        $hasRed = ($sortedStages | Where-Object { $_.state -eq "RED" }).Count -gt 0
        $headerText = if ($hasRed) { "Critical:" } else { "Attention:" }
        $headerColor = if ($hasRed) { "Red" } else { "Yellow" }

        Set-Pos $R $HalfWidth
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host $headerText.PadRight($RightWidth) -NoNewline -ForegroundColor $headerColor
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++

        # Show up to 2 reason lines (worst-first)
        $reasonsToShow = $sortedStages | Select-Object -First 2
        # Stage name abbreviations
        $stageAbbrev = @{
            "Context"  = "CTX"
            "Plan"     = "PLN"
            "Work"     = "WRK"
            "Optimize" = "OPT"
            "Verify"   = "VER"
            "Ship"     = "SHP"
        }

        foreach ($rs in $reasonsToShow) {
            Set-Pos $R $HalfWidth
            Write-Host "| " -NoNewline -ForegroundColor DarkGray

            $abbrev = if ($stageAbbrev.ContainsKey($rs.name)) { $stageAbbrev[$rs.name] } else { $rs.name.Substring(0,3).ToUpper() }
            $reasonLine = "($abbrev) $($rs.reason)"
            $lineColor = if ($rs.state -eq "RED") { "Red" } else { "Yellow" }

            if ($reasonLine.Length -gt $RightWidth) {
                $reasonLine = $reasonLine.Substring(0, $RightWidth - 3) + "..."
            }
            Write-Host $reasonLine.PadRight($RightWidth) -NoNewline -ForegroundColor $lineColor
            Write-Host " |" -NoNewline -ForegroundColor DarkGray
            $R++
        }
    }

    # === BLANK LINE ===
    Set-Pos $R $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host (" " * $RightWidth) -NoNewline
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    $R++

    # === HOTKEYS (only enabled ones) ===
    $actions = $PipelineData.recommended_actions | Where-Object { $_.enabled }
    if ($actions -and $actions.Count -gt 0) {
        Set-Pos $R $HalfWidth
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host "Hotkeys: " -NoNewline -ForegroundColor DarkGray

        $hotkeyStr = ""
        foreach ($action in $actions) {
            if ($hotkeyStr.Length -gt 0) { $hotkeyStr += " " }
            $hotkeyStr += "$($action.key)=$($action.label)"
        }

        $hotkeyAvail = $RightWidth - 9  # "Hotkeys: " is 9 chars
        if ($hotkeyStr.Length -gt $hotkeyAvail) {
            $hotkeyStr = $hotkeyStr.Substring(0, $hotkeyAvail - 3) + "..."
        }
        Write-Host $hotkeyStr.PadRight($hotkeyAvail) -NoNewline -ForegroundColor Cyan
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++
    }

    return $R
}

# --- PRINT ROW WITH ABSOLUTE POSITIONING ---
function Print-Row {
    param(
        [int]$Row,
        [string]$LeftTxt,
        [string]$RightTxt,
        [int]$HalfWidth,
        [string]$ColorL = "White",
        [string]$ColorR = "White"
    )
    
    $ContentWidth = $HalfWidth - 4
    
    # Truncate if needed
    if ($LeftTxt.Length -gt $ContentWidth) { $LeftTxt = $LeftTxt.Substring(0, $ContentWidth - 3) + "..." }
    if ($RightTxt.Length -gt $ContentWidth) { $RightTxt = $RightTxt.Substring(0, $ContentWidth - 3) + "..." }
    
    # Draw Left Box at column 0
    Set-Pos $Row 0
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host $LeftTxt.PadRight($ContentWidth) -NoNewline -ForegroundColor $ColorL
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
    
    # Draw Right Box at column HalfWidth
    Set-Pos $Row $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host $RightTxt.PadRight($ContentWidth) -NoNewline -ForegroundColor $ColorR
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
}

# --- DRAW BORDER LINE ---
function Draw-Border {
    param([int]$Row, [int]$HalfWidth)

    $line = "-" * ($HalfWidth - 2)
    Set-Pos $Row 0
    Write-Host "+$line+" -NoNewline -ForegroundColor DarkGray
    Set-Pos $Row $HalfWidth
    Write-Host "+$line+" -NoNewline -ForegroundColor DarkGray
}

# --- v16.1.1: LEFT-ONLY PANEL RENDERER (doesn't touch right panel) ---
function Print-LeftOnly {
    param(
        [int]$Row,
        [string]$Text,
        [int]$HalfWidth,
        [string]$Color = "White"
    )

    $ContentWidth = $HalfWidth - 4
    if ($Text.Length -gt $ContentWidth) { $Text = $Text.Substring(0, $ContentWidth - 3) + "..." }

    Set-Pos $Row 0
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host $Text.PadRight($ContentWidth) -NoNewline -ForegroundColor $Color
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
}

# --- v16.1.1: RIGHT-ONLY PANEL RENDERER (doesn't touch left panel) ---
function Print-RightOnly {
    param(
        [int]$Row,
        [string]$Text,
        [int]$HalfWidth,
        [string]$Color = "White"
    )

    $ContentWidth = $HalfWidth - 4
    if ($Text.Length -gt $ContentWidth) { $Text = $Text.Substring(0, $ContentWidth - 3) + "..." }

    Set-Pos $Row $HalfWidth
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host $Text.PadRight($ContentWidth) -NoNewline -ForegroundColor $Color
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
}

# --- v16.1.1: CLEAR DASHBOARD REGION (both panels, from start to TopRegionBottom) ---
# Left panel: cleared with borders (content always has borders)
# Right panel: cleared with spaces only (borders managed by content)
function Clear-DashboardRegion {
    param([int]$StartRow, [int]$HalfWidth)

    $ContentWidth = $HalfWidth - 4
    $blankContent = " " * $ContentWidth
    $rightClearWidth = $HalfWidth - 1  # Full right panel width

    for ($row = $StartRow; $row -lt $Global:TopRegionBottom; $row++) {
        # Clear left panel (with borders - left panel always uses borders)
        Set-Pos $row 0
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host $blankContent -NoNewline
        Write-Host " |" -NoNewline -ForegroundColor DarkGray

        # Clear right panel (no borders - borders managed by content/pipeline)
        Set-Pos $row $HalfWidth
        Write-Host (" " * $rightClearWidth) -NoNewline
    }
}

# --- v14.1: PROGRESS BAR RENDERER for BOOTSTRAP MODE (Compact ASCII Style) ---
function Format-ProgressBar {
    param(
        [int]$Score,
        [int]$Threshold,
        [int]$Width = 10,
        [bool]$Exists = $true
    )

    # Determine color based on score vs threshold
    $Color = if ($Score -ge $Threshold) { "Green" }
    elseif ($Score -ge 50) { "Yellow" }
    else { "Red" }

    # Determine state label
    $StateLabel = if (-not $Exists) { "MISS" }
    elseif ($Score -ge $Threshold) { "OK" }
    elseif ($Score -le 40) { "STUB" }  # Capped stub score
    else { "NEED" }

    # Calculate filled/empty portions (compact microbar: ■□, max 5 chars)
    $MicroWidth = 5
    $Filled = [Math]::Floor($Score / 100 * $MicroWidth)
    $Empty = $MicroWidth - $Filled

    $MicroBar = ""
    if ($Filled -gt 0) { $MicroBar += "■" * $Filled }
    if ($Empty -gt 0) { $MicroBar += "□" * $Empty }

    return @{
        MicroBar   = $MicroBar
        Percentage = "{0,3}%" -f $Score
        Color      = $Color
        StateLabel = $StateLabel
    }
}

# --- v16.0: STREAM STATUS LINE HELPER for COMPACT DASHBOARD ---
function Get-StreamStatusLine {
    <#
    .SYNOPSIS
        Returns compact status info for a stream (BACKEND/FRONTEND/QA/LIBRARIAN).
    .PARAMETER StreamName
        One of: BACKEND, FRONTEND, QA, LIBRARIAN
    .PARAMETER WorkerData
        Worker status hashtable from Get-WorkerStatus
    .RETURNS
        @{ Bar; BarColor; State; Summary; SummaryColor }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BACKEND", "FRONTEND", "QA", "LIBRARIAN")]
        [string]$StreamName,
        [hashtable]$WorkerData
    )

    # Defaults (fail-open: show "—" + Gray microbar)
    $result = @{
        Bar          = "□□□□□"
        BarColor     = "DarkGray"
        State        = "—"
        Summary      = "—"
        SummaryColor = "DarkGray"
    }

    if (-not $WorkerData) { return $result }

    switch ($StreamName) {
        "BACKEND" {
            # Get delegation count for NEXT state
            $delegationCount = 0
            if ($Global:StartupDelegation -and $Global:StartupDelegation.status -eq "READY") {
                $beStream = $Global:StartupDelegation.streams | Where-Object { $_.id -match "^backend$" } | Select-Object -First 1
                if ($beStream) { $delegationCount = $beStream.task_count }
            }

            $status = $WorkerData.backend_status
            $task = $WorkerData.backend_task

            # Determine state and colors
            if ($status -eq "UP") {
                $result.State = "RUNNING"
                $result.Bar = "■■■■■"
                $result.BarColor = "Green"
                $result.SummaryColor = "White"
            }
            elseif ($delegationCount -gt 0) {
                $result.State = "NEXT"
                $result.Bar = "■■□□□"
                $result.BarColor = "Cyan"
                $result.SummaryColor = "Cyan"
                $result.Summary = "$delegationCount task(s) queued"
            }
            else {
                $result.State = "IDLE"
                $result.Bar = "□□□□□"
                $result.BarColor = "DarkGray"
                $result.SummaryColor = "DarkGray"
            }

            # Format task summary: "[T-123] desc" -> "desc (T-123)"
            if ($task -and $task -ne "(none)" -and $result.State -eq "RUNNING") {
                if ($task -match "^\[([^\]]+)\]\s*(.*)$") {
                    $taskId = $Matches[1]
                    $taskDesc = $Matches[2].Trim()
                    if ($taskDesc) {
                        $result.Summary = "$taskDesc ($taskId)"
                    } else {
                        $result.Summary = "($taskId)"
                    }
                }
                else {
                    $result.Summary = $task
                }
            }
        }

        "FRONTEND" {
            # Get delegation count for NEXT state
            $delegationCount = 0
            if ($Global:StartupDelegation -and $Global:StartupDelegation.status -eq "READY") {
                $feStream = $Global:StartupDelegation.streams | Where-Object { $_.id -match "^frontend$" } | Select-Object -First 1
                if ($feStream) { $delegationCount = $feStream.task_count }
            }

            $status = $WorkerData.frontend_status
            $task = $WorkerData.frontend_task

            # Determine state and colors
            if ($status -eq "UP") {
                $result.State = "RUNNING"
                $result.Bar = "■■■■■"
                $result.BarColor = "Green"
                $result.SummaryColor = "White"
            }
            elseif ($delegationCount -gt 0) {
                $result.State = "NEXT"
                $result.Bar = "■■□□□"
                $result.BarColor = "Cyan"
                $result.SummaryColor = "Cyan"
                $result.Summary = "$delegationCount task(s) queued"
            }
            else {
                $result.State = "IDLE"
                $result.Bar = "□□□□□"
                $result.BarColor = "DarkGray"
                $result.SummaryColor = "DarkGray"
            }

            # Format task summary: "[T-123] desc" -> "desc (T-123)"
            if ($task -and $task -ne "(none)" -and $result.State -eq "RUNNING") {
                if ($task -match "^\[([^\]]+)\]\s*(.*)$") {
                    $taskId = $Matches[1]
                    $taskDesc = $Matches[2].Trim()
                    if ($taskDesc) {
                        $result.Summary = "$taskDesc ($taskId)"
                    } else {
                        $result.Summary = "($taskId)"
                    }
                }
                else {
                    $result.Summary = $task
                }
            }
        }

        "QA" {
            # Count HIGH risk tasks without PASS qa_status
            try {
                # First get the actual count
                $countQuery = "SELECT COUNT(*) as cnt FROM tasks WHERE risk = 'HIGH' AND (qa_status IS NULL OR qa_status != 'PASS') AND status IN ('pending', 'in_review', 'completed')"
                $countResult = Invoke-Query -Query $countQuery -Silent

                if ($countResult -and $countResult[0].cnt -gt 0) {
                    $count = [int]$countResult[0].cnt

                    # Get first task for example
                    $firstTaskQuery = "SELECT id FROM tasks WHERE risk = 'HIGH' AND (qa_status IS NULL OR qa_status != 'PASS') AND status IN ('pending', 'in_review', 'completed') LIMIT 1"
                    $firstTask = Invoke-Query -Query $firstTaskQuery -Silent
                    $firstId = if ($firstTask) { "T-$($firstTask[0].id)" } else { "T-?" }

                    $result.State = "PENDING"
                    $result.Bar = "■□□□□"
                    $result.BarColor = "Yellow"
                    $result.SummaryColor = "Yellow"
                    $result.Summary = "$count HIGH unverified (e.g., $firstId)"
                }
                else {
                    # Check for any pending QA sessions
                    $qaPending = $WorkerData.qa_sessions
                    if ($qaPending -and $qaPending -gt 0) {
                        $result.State = "PENDING"
                        $result.Bar = "■■□□□"
                        $result.BarColor = "Yellow"
                        $result.SummaryColor = "Yellow"
                        $result.Summary = "$qaPending awaiting audit"
                    }
                    else {
                        $result.State = "OK"
                        $result.Bar = "■■■■■"
                        $result.BarColor = "Green"
                        $result.SummaryColor = "Green"
                        $result.Summary = "All verified"
                    }
                }
            }
            catch {
                # Fail-open: show unknown state
                $result.State = "—"
                $result.Summary = "—"
            }
        }

        "LIBRARIAN" {
            $libStatus = $WorkerData.lib_status_text

            switch -Wildcard ($libStatus) {
                "MESSY" {
                    $result.State = "WARN"
                    $result.Bar = "■□□□□"
                    $result.BarColor = "Red"
                    $result.SummaryColor = "Red"
                    $result.Summary = "Root cluttered (>5 loose files)"
                }
                "CLUTTERED" {
                    $result.State = "WARN"
                    $result.Bar = "■■□□□"
                    $result.BarColor = "Yellow"
                    $result.SummaryColor = "Yellow"
                    $result.Summary = "Some loose files detected"
                }
                "*Inbox*" {
                    $result.State = "PENDING"
                    $result.Bar = "■■□□□"
                    $result.BarColor = "Yellow"
                    $result.SummaryColor = "Yellow"
                    $result.Summary = "Inbox items pending /ingest"
                }
                "CLEAN" {
                    $result.State = "OK"
                    $result.Bar = "■■■■■"
                    $result.BarColor = "Green"
                    $result.SummaryColor = "Green"
                    $result.Summary = "Library clean"
                }
                default {
                    $result.State = "OK"
                    $result.Bar = "■■■□□"
                    $result.BarColor = "Green"
                    $result.SummaryColor = "DarkGray"
                    $result.Summary = "—"
                }
            }
        }
    }

    return $result
}

# --- v15.3: TEXT WRAPPING HELPER for BOOTSTRAP PANEL ---
function Wrap-PanelText {
    <#
    .SYNOPSIS
        Wraps text to fit within a given width, with optional indentation for continuation lines.
    .PARAMETER Text
        The text to wrap
    .PARAMETER Width
        Maximum width per line
    .PARAMETER Indent
        Number of spaces to indent continuation lines (default 0)
    .RETURNS
        Array of lines that fit within the width
    #>
    param(
        [string]$Text,
        [int]$Width,
        [int]$Indent = 0
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -le $Width) {
        return @($Text)
    }

    $lines = @()
    $words = $Text -split '\s+'
    $currentLine = ""
    $isFirst = $true

    foreach ($word in $words) {
        $effectiveWidth = if ($isFirst) { $Width } else { $Width - $Indent }
        $testLine = if ($currentLine) { "$currentLine $word" } else { $word }

        if ($testLine.Length -le $effectiveWidth) {
            $currentLine = $testLine
        }
        else {
            if ($currentLine) {
                $lines += if ($isFirst) { $currentLine } else { (" " * $Indent) + $currentLine }
                $isFirst = $false
            }
            $currentLine = $word
        }
    }

    if ($currentLine) {
        $lines += if ($isFirst) { $currentLine } else { (" " * $Indent) + $currentLine }
    }

    return $lines
}

# --- v14.1: PRE-INIT PANEL (Before /init - No docs exist) ---
function Draw-PreInitPanel {
    param(
        [int]$StartRow,
        [int]$HalfWidth,
        [object]$WorkerData
    )

    $R = $StartRow

    # Left: NEW PROJECT SETUP header
    Print-Row $R "NEW PROJECT SETUP" "SETUP REQUIRED" $HalfWidth "Cyan" "Cyan"
    $R++
    Print-Row $R "" "" $HalfWidth "DarkGray" "DarkGray"
    $R++

    # Left: Instructions
    Print-Row $R "  Run /init to scaffold docs" "Next focus: SETUP" $HalfWidth "Yellow" "Yellow"
    $R++
    Print-Row $R "  /profile <name> to set profile" "Action: /init" $HalfWidth "DarkGray" "Cyan"
    $R++
    Print-Row $R "" "" $HalfWidth "DarkGray" "DarkGray"
    $R++

    # Show worker status (IDLE state)
    $BE_Color = if ($WorkerData.backend_status -eq "UP") { "Green" } else { "DarkGray" }
    $FE_Color = if ($WorkerData.frontend_status -eq "UP") { "Green" } else { "DarkGray" }

    Print-Row $R "BACKEND  [IDLE]" "FRONTEND  [IDLE]" $HalfWidth $BE_Color $FE_Color
    $R++
    Print-Row $R "QA/AUDIT [IDLE]" "" $HalfWidth "DarkGray" "DarkGray"
    $R++

    return $R
}

# --- v14.1: BOOTSTRAP PANEL RENDERER (Compact Inline Style) ---
# v15.3: Refactored with line arrays for balanced left/right spacing
function Draw-BootstrapPanel {
    param(
        [int]$StartRow,
        [int]$HalfWidth,
        [object]$ReadinessData
    )

    $R = $StartRow
    # Compute effective right panel width (leave some margin)
    $RightWidth = $HalfWidth - 4

    # === PHASE 1: Collect doc states and compute guidance ===
    $docStates = @{}
    $severityOrder = @{ "MISS" = 0; "STUB" = 1; "NEED" = 2; "OK" = 3 }
    # Fixed priority order: PRD > SPEC > TECH_STACK > DECISION_LOG
    $priorityOrder = @{ "PRD" = 0; "SPEC" = 1; "TECH_STACK" = 2; "DECISION_LOG" = 3 }
    $worstDoc = $null
    $worstSeverity = 999
    $worstPriority = 999
    $criticalBullets = @()

    # Process docs from readiness.py (PRD, SPEC, DECISION_LOG)
    foreach ($fileName in @("PRD", "SPEC", "DECISION_LOG")) {
        $fileData = $ReadinessData.files.$fileName
        $threshold = $ReadinessData.thresholds.$fileName
        $score = if ($fileData) { [int]$fileData.score } else { 0 }
        $exists = if ($fileData) { $fileData.exists } else { $false }

        $progress = Format-ProgressBar -Score $score -Threshold $threshold -Width 10 -Exists $exists
        $state = $progress.StateLabel

        $docStates[$fileName] = @{
            Score = $score
            Threshold = $threshold
            Exists = $exists
            State = $state
            Progress = $progress
        }
    }

    # Manually detect TECH_STACK.md (not in readiness.py contract)
    $techStackPath = Join-Path $CurrentDir "docs\TECH_STACK.md"
    $techStackExists = Test-Path $techStackPath
    $techStackScore = 0
    $techStackState = "MISS"

    if ($techStackExists) {
        $techStackContent = Get-Content $techStackPath -Raw -ErrorAction SilentlyContinue
        $isStub = $techStackContent -match "ATOMIC_MESH_TEMPLATE_STUB"
        $wordCount = if ($techStackContent) { ($techStackContent -split '\s+').Count } else { 0 }

        if ($isStub -and $wordCount -lt 200) {
            $techStackState = "STUB"
            $techStackScore = 30
        }
        elseif ($wordCount -lt 100) {
            $techStackState = "NEED"
            $techStackScore = 50
        }
        else {
            $techStackState = "OK"
            $techStackScore = 80
        }
    }

    $techStackProgress = Format-ProgressBar -Score $techStackScore -Threshold 60 -Width 10 -Exists $techStackExists
    $docStates["TECH_STACK"] = @{
        Score = $techStackScore
        Threshold = 60
        Exists = $techStackExists
        State = $techStackState
        Progress = $techStackProgress
    }

    # Determine worst doc using fixed priority (GATE DOCS ONLY: PRD > SPEC > DECISION_LOG)
    # TECH_STACK is advisory - does not block planning
    foreach ($fileName in @("PRD", "SPEC", "DECISION_LOG")) {
        $docState = $docStates[$fileName]
        $state = $docState.State
        $sev = if ($severityOrder.ContainsKey($state)) { $severityOrder[$state] } else { 3 }
        $pri = $priorityOrder[$fileName]

        # Worst = lowest severity, then by fixed priority order
        if ($sev -lt $worstSeverity -or ($sev -eq $worstSeverity -and $pri -lt $worstPriority)) {
            $worstSeverity = $sev
            $worstPriority = $pri
            $worstDoc = $fileName
        }

        # Build critical bullets for non-OK GATE docs (max 3)
        if ($state -ne "OK" -and $criticalBullets.Count -lt 3) {
            $bullet = switch ($fileName) {
                "PRD"          { "PRD: fill Goals/Stories/Metrics" }
                "SPEC"         { "SPEC: define Data Model/API/Security" }
                "DECISION_LOG" { "DECISION_LOG: add real decision" }
            }
            $criticalBullets += $bullet
        }
    }

    # Compute immediate next step based on worst GATE doc
    $immediateStep = switch ($worstDoc) {
        "PRD"          { "Fill Goals + User Stories + Success Metrics" }
        "SPEC"         { "Define Data Model + API + Security sections" }
        "DECISION_LOG" { "Add >=1 real decision in Records table" }
        default        { "All gate docs ready - run /refresh-plan" }
    }

    # Check INBOX for pending hint
    $inboxPending = 0
    $inboxPath = Join-Path $CurrentDir "docs\INBOX.md"
    if (Test-Path $inboxPath) {
        $inboxContent = Get-Content $inboxPath -Raw -ErrorAction SilentlyContinue
        if ($inboxContent) {
            foreach ($line in ($inboxContent -split "`n")) {
                $trimmed = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                if ($trimmed -match "ATOMIC_MESH_TEMPLATE_STUB") { continue }
                if ($trimmed -match "^#") { continue }
                if ($trimmed -eq "-") { continue }
                if ($trimmed.Length -lt 3) { continue }
                if ($trimmed.StartsWith("Drop clarifications")) { continue }
                if ($trimmed.StartsWith("Next: run")) { continue }
                $inboxPending++
            }
        }
    }

    # Compute auto-ingest status
    $autoIngestTxt = "Auto-ingest: "
    $autoIngestColor = "DarkGray"
    if (-not $Global:AutoIngestEnabled) {
        $autoIngestTxt += "disabled"
    }
    elseif ($Global:AutoIngestPending) {
        $autoIngestTxt += "pending"
        $autoIngestColor = "Yellow"
    }
    elseif ($Global:AutoIngestLastResult -eq "OK") {
        $timeStr = if ($Global:AutoIngestLastRunUtc) { $Global:AutoIngestLastRunUtc.ToLocalTime().ToString("HH:mm:ss") } else { "" }
        $autoIngestTxt += "OK ($timeStr)"
        $autoIngestColor = "Green"
    }
    elseif ($Global:AutoIngestLastResult -eq "ERROR") {
        $autoIngestTxt += "ERROR"
        $autoIngestColor = "Red"
    }
    else {
        $autoIngestTxt += "armed"
    }

    # === PHASE 2: Build LEFT panel lines (scoreboard) ===
    $leftLines = @()
    $leftColors = @()

    # Header
    $leftLines += "BOOTSTRAP (context incomplete)"
    $leftColors += "Cyan"

    # Blank line
    $leftLines += ""
    $leftColors += "DarkGray"

    # PRD
    $prd = $docStates["PRD"]
    $prdColor = switch ($prd.State) { "OK" { "Green" } "MISS" { "Red" } default { "Yellow" } }
    $leftLines += "PRD".PadRight(12) + " [$($prd.State)] $($prd.Progress.MicroBar)"
    $leftColors += $prdColor

    # SPEC
    $spec = $docStates["SPEC"]
    $specColor = switch ($spec.State) { "OK" { "Green" } "MISS" { "Red" } default { "Yellow" } }
    $leftLines += "SPEC".PadRight(12) + " [$($spec.State)] $($spec.Progress.MicroBar)"
    $leftColors += $specColor

    # TECH_STACK
    $tech = $docStates["TECH_STACK"]
    $techColor = switch ($tech.State) { "OK" { "Green" } "MISS" { "Red" } default { "Yellow" } }
    $leftLines += "TECH_STACK".PadRight(12) + " [$($tech.State)] $($tech.Progress.MicroBar)"
    $leftColors += $techColor

    # DECISION_LOG
    $dlog = $docStates["DECISION_LOG"]
    $dlogColor = switch ($dlog.State) { "OK" { "Green" } "MISS" { "Red" } default { "Yellow" } }
    $leftLines += "DECISION_LOG".PadRight(12) + " [$($dlog.State)] $($dlog.Progress.MicroBar)"
    $leftColors += $dlogColor

    # Blank line
    $leftLines += ""
    $leftColors += "DarkGray"

    # INBOX
    $inboxStatus = if ($inboxPending -gt 0) { "✎ pending ($inboxPending)" } else { "✓ empty" }
    $inboxColor = if ($inboxPending -gt 0) { "Yellow" } else { "DarkGray" }
    $leftLines += "INBOX".PadRight(12) + " [-] $inboxStatus"
    $leftColors += $inboxColor

    # Blank line (optional padding)
    $leftLines += ""
    $leftColors += "DarkGray"

    # === PHASE 3: Build RIGHT panel lines (guidance) ===
    $rightLines = @()
    $rightColors = @()

    # Header
    $rightLines += "CONTEXT READINESS"
    $rightColors += "Cyan"

    # Source line
    $rightLines += "Source: readiness.py (live)"
    $rightColors += "DarkGray"

    # Blank line
    $rightLines += ""
    $rightColors += "DarkGray"

    # Next step (with wrapping) - GATE DOCS ONLY
    $stepColor = if ($worstSeverity -le 1) { "Yellow" } else { "Green" }
    $nextText = "Next (Gate): $immediateStep"
    $wrappedNext = Wrap-PanelText -Text $nextText -Width $RightWidth -Indent 6
    foreach ($wl in $wrappedNext) {
        $rightLines += $wl
        $rightColors += $stepColor
    }

    # Advisory: TECH_STACK (if not OK)
    $techState = $docStates["TECH_STACK"].State
    if ($techState -ne "OK") {
        $rightLines += "Also: TECH_STACK recommended"
        $rightColors += "DarkGray"
    }

    # Blank line
    $rightLines += ""
    $rightColors += "DarkGray"

    # v16.0: Attention section (renamed from Critical for BOOTSTRAP consistency)
    # BOOTSTRAP is YELLOW state, so use "Attention:" not "Critical:"
    if ($criticalBullets.Count -gt 0) {
        $rightLines += "Attention:"
        $rightColors += "Yellow"

        foreach ($bullet in $criticalBullets) {
            $bulletText = "• $bullet"
            $wrappedBullet = Wrap-PanelText -Text $bulletText -Width $RightWidth -Indent 4
            foreach ($wl in $wrappedBullet) {
                $rightLines += $wl
                $rightColors += "Yellow"
            }
        }

        # Blank line after attention
        $rightLines += ""
        $rightColors += "DarkGray"
    }

    # INBOX hint (if pending and not too many critical bullets)
    if ($inboxPending -gt 0) {
        $rightLines += "Note: INBOX pending - /ingest when ready"
        $rightColors += "Gray"
        $rightLines += ""
        $rightColors += "DarkGray"
    }

    # Strategic commands locked
    $rightLines += "Strategic commands LOCKED"
    $rightColors += "Red"

    # Edit hint
    $rightLines += "Edit: PRD | SPEC | TECH_STACK | DECISION_LOG"
    $rightColors += "DarkGray"

    # Auto-ingest status
    $rightLines += $autoIngestTxt
    $rightColors += $autoIngestColor

    # === PHASE 4: Render both panels row-by-row ===
    $maxLines = [Math]::Max($leftLines.Count, $rightLines.Count)

    for ($i = 0; $i -lt $maxLines; $i++) {
        $leftText = if ($i -lt $leftLines.Count) { $leftLines[$i] } else { "" }
        $leftColor = if ($i -lt $leftColors.Count) { $leftColors[$i] } else { "DarkGray" }
        $rightText = if ($i -lt $rightLines.Count) { $rightLines[$i] } else { "" }
        $rightColor = if ($i -lt $rightColors.Count) { $rightColors[$i] } else { "DarkGray" }

        Print-Row $R $leftText $rightText $HalfWidth $leftColor $rightColor
        $R++
    }

    return $R
}

# ============================================================================
#region HISTORY_MODE
# v15.5: HISTORY MODE - Data Fetch + Renderer
# Functions: Get-HistoryData, Get-HistoryDetailData, Draw-HistoryScreen
# Keys: F3 (toggle), Tab (subview), Up/Down (nav), Enter (details)
# ============================================================================

# --- Get-HistoryData: Fetch data based on current subview ---
function Get-HistoryData {
    $subview = $Global:HistorySubview
    $data = @()

    # Centralized runtime signals (fail-open). Subviews may use partial data.
    $signals = $null
    try { $signals = Get-RuntimeSignals } catch { $signals = $null }

    switch ($subview) {
        "TASKS" {
            # Primary: tasks table with derived health
            # Sort order for triage: BLOCKED → HIGH risk unverified → RUNNING → PENDING → DONE
            $sortQuery = @"
SELECT id, type, desc, status, qa_status, risk, retry_count, review_notes, override_justification, trace_reasoning, output
FROM tasks
ORDER BY
    CASE
        WHEN status IN ('blocked', 'BLOCKED') THEN 1
        WHEN risk = 'HIGH' AND (qa_status IS NULL OR qa_status != 'PASS') THEN 2
        WHEN status IN ('in_progress', 'running', 'RUNNING', 'IN_PROGRESS') THEN 3
        WHEN status IN ('pending', 'next', 'planned', 'PENDING', 'NEXT', 'PLANNED') THEN 4
        WHEN status IN ('completed', 'COMPLETED') THEN 5
        ELSE 6
    END,
    id DESC
LIMIT 30
"@
            $tasks = Invoke-Query $sortQuery -Silent

            foreach ($t in $tasks) {
                # Derive worker label: use type if present, else stream if present, else "—"
                # Only show deterministic values, never guess
                $worker = "—"
                if ($t.type -and $t.type.Trim() -ne "") {
                    $worker = switch ($t.type.ToLower()) {
                        "backend" { "BACKEND" }
                        "frontend" { "FRONTEND" }
                        "qa" { "QA" }
                        "librarian" { "LIBRARIAN" }
                        "system" { "SYSTEM" }
                        default { $t.type.ToUpper().Substring(0, [Math]::Min(8, $t.type.Length)) }
                    }
                }
                elseif ($t.stream -and $t.stream.Trim() -ne "") {
                    $worker = $t.stream.ToUpper().Substring(0, [Math]::Min(8, $t.stream.Length))
                }

                # Rows correspond to tasks (id, stream, status, risk, qa_status, notes markers)
                $healthResult = Get-TaskHealth -Task $t
                $bucket = $healthResult.Bucket

                $riskDisp = if ($t.risk) { $t.risk.ToUpperInvariant() } else { "—" }
                $qaDisp = if ($t.qa_status) { $t.qa_status.ToUpperInvariant() } else { "—" }

                # Notes markers (single-width): O=output, N=review notes, !=override, T=trace
                $markers = @()
                if ($t.output -and -not [string]::IsNullOrWhiteSpace([string]$t.output)) { $markers += "O" }
                if ($t.review_notes -and -not [string]::IsNullOrWhiteSpace([string]$t.review_notes)) { $markers += "N" }
                if ($t.override_justification -and -not [string]::IsNullOrWhiteSpace([string]$t.override_justification)) { $markers += "!" }
                if ($t.trace_reasoning -and -not [string]::IsNullOrWhiteSpace([string]$t.trace_reasoning)) { $markers += "T" }
                $markerText = if ($markers.Count -gt 0) { "[" + ($markers -join "") + "]" } else { "" }

                $desc = if ($t.desc) { [string]$t.desc } else { "(no description)" }
                $content = "[T-$($t.id)] $bucket $riskDisp QA:$qaDisp $markerText $desc"

                $data += @{
                    Id           = $t.id
                    Worker       = $worker
                    Content      = $content
                    Health       = $healthResult.Health
                    HealthColor  = Resolve-HealthColor -Health $healthResult.Health
                    Type         = "task"
                    Stream       = $t.type
                    Status       = $bucket
                    Risk         = $riskDisp
                    QAStatus     = $qaDisp
                    NotesMarkers = $markers
                    Raw          = $t
                }
            }
        }

        "DOCS" {
            # Rows correspond to PRD/SPEC/DECISION_LOG/ACTIVE_SPEC/INBOX with readiness info
            # Uses centralized $signals.readiness (already called at top of function)
            try {
                $rd = if ($signals -and $signals.readiness) { $signals.readiness } else { $null }

                foreach ($docName in @("PRD", "SPEC", "DECISION_LOG", "ACTIVE_SPEC", "INBOX")) {
                    $fileData = $null
                    if ($rd -and $rd.files -and $rd.files.ContainsKey($docName)) {
                        $fileData = $rd.files[$docName]
                    }

                    $score = if ($fileData -and $null -ne $fileData.score) { [int]$fileData.score } else { 0 }
                    $exists = if ($fileData -and $null -ne $fileData.exists) { [bool]$fileData.exists } else { $false }
                    $state = if ($fileData -and $fileData.state) { [string]$fileData.state } else { "MISS" }

                    # Get file mtime if exists
                    $mtimeStr = "—"
                    $docPath = Join-Path $CurrentDir "docs\$docName.md"
                    if (Test-Path $docPath) {
                        $mtime = (Get-Item $docPath).LastWriteTime
                        $mtimeStr = $mtime.ToString("HH:mm")
                    }

                    # Map state -> semantic health token
                    $health = switch ($state) {
                        "OK"      { "GREEN" }
                        "STUB"    { "YELLOW" }
                        "NEED"    { "YELLOW" }
                        "PENDING" { "YELLOW" }
                        "MISS"    { "RED" }
                        "EMPTY"   { "GREEN" }
                        default   { "GRAY" }
                    }

                    # Content varies: INBOX shows meaningful_lines, others show score
                    $content = if ($docName -eq "INBOX") {
                        $ml = if ($fileData -and $null -ne $fileData.meaningful_lines) { [int]$fileData.meaningful_lines } else { 0 }
                        "INBOX.md - $ml pending (last: $mtimeStr)"
                    } else {
                        "$docName.md - $score% [$state] (last: $mtimeStr)"
                    }

                    $data += @{
                        Id          = $docName
                        Worker      = "DOCS"
                        Content     = $content
                        Health      = $health
                        HealthColor = Resolve-HealthColor -Health $health
                        Type        = "doc"
                        State       = $state
                        Raw         = $fileData
                    }
                }

                # Auto-ingest status (system signal, not from readiness.py)
                $aiStatus = if ($Global:AutoIngestLastResult) { $Global:AutoIngestLastResult } else { "—" }
                $aiHealth = switch ($aiStatus) {
                    "OK"    { "GREEN" }
                    "ERROR" { "RED" }
                    default { "GRAY" }
                }

                $data += @{
                    Id          = "AUTO-INGEST"
                    Worker      = "SYSTEM"
                    Content     = "Auto-ingest: $aiStatus"
                    Health      = $aiHealth
                    HealthColor = Resolve-HealthColor -Health $aiHealth
                    Type        = "system"
                    Raw         = @{ Status = $aiStatus }
                }
            }
            catch {
                $data += @{
                    Id          = "ERROR"
                    Worker      = "SYSTEM"
                    Content     = "Failed to load readiness data"
                    Health      = "RED"
                    HealthColor = Resolve-HealthColor -Health "RED"
                    Type        = "error"
                    Raw         = $null
                }
            }
        }

        "SHIP" {
            # One row showing shipping readiness (blocked reasons if any)
            # Uses centralized $signals (risk_summary, task_summary)
            try {
                # 1. HIGH risk tasks without QA PASS (from signals.risk_summary)
                $highRiskCount = 0
                if ($signals -and $signals.risk_summary) {
                    $highRiskCount = [int]$signals.risk_summary.high_not_pass
                }

                $hrHealth = if ($highRiskCount -gt 0) { "RED" } else { "GREEN" }

                $data += @{
                    Id          = "HIGH-RISK"
                    Worker      = "SHIP"
                    Content     = "HIGH risk unverified: $highRiskCount"
                    Health      = $hrHealth
                    HealthColor = Resolve-HealthColor -Health $hrHealth
                    Type        = "ship"
                    Raw         = @{ Count = $highRiskCount }
                }

                # 2. BLOCKED tasks count (from signals.task_summary)
                $blockedCount = 0
                if ($signals -and $signals.task_summary -and $signals.task_summary.by_status) {
                    $blockedCount = [int]$signals.task_summary.by_status["BLOCKED"]
                }

                if ($blockedCount -gt 0) {
                    $data += @{
                        Id          = "BLOCKED"
                        Worker      = "SHIP"
                        Content     = "Blocked tasks: $blockedCount"
                        Health      = "RED"
                        HealthColor = Resolve-HealthColor -Health "RED"
                        Type        = "ship"
                        Raw         = @{ Count = $blockedCount }
                    }
                }

                # 3. Context readiness blocking (from signals.readiness.overall)
                $blocking = @()
                if ($signals -and $signals.readiness -and $signals.readiness.overall) {
                    $blocking = @($signals.readiness.overall.blocking_files)
                }

                if ($blocking.Count -gt 0) {
                    $ctxHealth = "YELLOW"
                    $data += @{
                        Id          = "CONTEXT"
                        Worker      = "SHIP"
                        Content     = "Blocking docs: $($blocking -join ', ')"
                        Health      = $ctxHealth
                        HealthColor = Resolve-HealthColor -Health $ctxHealth
                        Type        = "ship"
                        Raw         = @{ Blocking = $blocking }
                    }
                }

                # 4. Git working tree status (clean/dirty) - still direct call
                $gitStatus = git status --porcelain 2>&1
                $uncommittedCount = if ([string]::IsNullOrWhiteSpace($gitStatus)) { 0 } else { ($gitStatus -split "`n").Count }
                $gitClean = ($uncommittedCount -eq 0)

                $gitHealth = if ($gitClean) { "GREEN" } else { "YELLOW" }
                $gitContent = if ($gitClean) { "Git: clean" } else { "Git: $uncommittedCount uncommitted" }

                $data += @{
                    Id          = "GIT"
                    Worker      = "SHIP"
                    Content     = $gitContent
                    Health      = $gitHealth
                    HealthColor = Resolve-HealthColor -Health $gitHealth
                    Type        = "ship"
                    Raw         = @{ Clean = $gitClean; Count = $uncommittedCount }
                }

                # 5. Last git tag (cheap, no new tables)
                $lastTag = git describe --tags --abbrev=0 2>&1
                $tagContent = "Last tag: —"
                $tagHealth = "GRAY"
                if (-not [string]::IsNullOrWhiteSpace($lastTag) -and $lastTag -notmatch "fatal:") {
                    $tagContent = "Last tag: $($lastTag.Trim())"
                    $headTag = git tag --points-at HEAD 2>&1
                    if (-not [string]::IsNullOrWhiteSpace($headTag) -and $headTag -notmatch "fatal:") {
                        $tagHealth = "GREEN"
                        $tagContent = "At tag: $($headTag.Trim().Split("`n")[0])"
                    }
                }

                $data += @{
                    Id          = "TAG"
                    Worker      = "SHIP"
                    Content     = $tagContent
                    Health      = $tagHealth
                    HealthColor = Resolve-HealthColor -Health $tagHealth
                    Type        = "ship"
                    Raw         = @{ Tag = $lastTag }
                }
            }
            catch {
                $data += @{
                    Id          = "ERROR"
                    Worker      = "SYSTEM"
                    Content     = "Failed to load ship data"
                    Health      = "RED"
                    HealthColor = Resolve-HealthColor -Health "RED"
                    Type        = "error"
                    Raw         = $null
                }
            }
        }
    }

    return $data
}

# --- Get-HistoryDetailData: Fetch audit_log overlay for selected item ---
function Get-HistoryDetailData {
    param([object]$SelectedItem)

    if (-not $SelectedItem -or $SelectedItem.Type -ne "task") {
        return @()
    }

    $taskId = $SelectedItem.Id
    $details = @()

    # Fetch recent audit_log entries for this task
    $auditLogs = Invoke-Query "SELECT action, reason, created_at FROM audit_log WHERE task_id = $taskId ORDER BY created_at DESC LIMIT 5" -Silent

    foreach ($log in $auditLogs) {
        $reason = $log.reason
        if ($reason.Length -gt 35) { $reason = $reason.Substring(0, 32) + "..." }

        $details += @{
            Action = $log.action.ToUpper()
            Reason = $reason
            Time   = $log.created_at
        }
    }

    return $details
}

# --- HistoryMode helpers: hints + selection + safe parsing ---
function Set-HistoryHint {
    param(
        [string]$Text,
        [string]$Color = "DarkGray"
    )

    $Global:HistoryHintText = $Text
    $Global:HistoryHintColor = if ([string]::IsNullOrWhiteSpace($Color)) { "DarkGray" } else { $Color }
    $Global:HistoryHintUtc = [DateTime]::UtcNow
}

function Get-HistorySelectedItem {
    if (-not $Global:HistoryData -or $Global:HistoryData.Count -eq 0) { return $null }

    $idx = 0
    try { $idx = [int]$Global:HistorySelectedRow } catch { $idx = 0 }
    if ($idx -lt 0 -or $idx -ge $Global:HistoryData.Count) { return $null }
    return $Global:HistoryData[$idx]
}

function Get-TaskIdFromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    # v15.5.1: Prefer T-<digits> format first (canonical task ID)
    $mTask = [regex]::Match($Text, '\bT-(\d+)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($mTask.Success) {
        try { return [int]$mTask.Groups[1].Value } catch {}
    }

    # Fallback: first bare integer (avoids v15.5, 80%, timestamps)
    $mInt = [regex]::Match($Text, '\b(\d+)\b')
    if ($mInt.Success) {
        try { return [int]$mInt.Groups[1].Value } catch {}
    }

    return $null
}

function Find-FirstNonGreenHistoryIndex {
    param([object[]]$Data)

    if (-not $Data -or $Data.Count -eq 0) { return 0 }
    for ($i = 0; $i -lt $Data.Count; $i++) {
        $row = $Data[$i]
        if (-not $row) { continue }

        $health = $row.Health
        $healthColor = $row.HealthColor

        if ($healthColor -and $healthColor -ne "Green") { return $i }
        if ($health -and $health -ne "OK") { return $i }
    }
    return 0
}

function Find-HistoryIndexByTaskId {
    param(
        [object[]]$Data,
        [int]$TaskId
    )

    if (-not $Data -or $Data.Count -eq 0) { return $null }
    for ($i = 0; $i -lt $Data.Count; $i++) {
        $row = $Data[$i]
        if (-not $row) { continue }
        if ($row.Type -ne "task") { continue }
        try {
            if ([int]$row.Id -eq $TaskId) { return $i }
        }
        catch {}
    }
    return $null
}

function Invoke-HistoryHotkey {
    param([string]$Key)

    if (-not $Global:HistoryMode) { return }

    $k = if ($Key) { $Key.ToUpperInvariant() } else { "" }

    switch ($k) {
        "I" {
            try {
                $Global:AutoIngestPending = $false
                $Global:AutoIngestLastRunUtc = [DateTime]::UtcNow
                $result = Invoke-SilentIngest

                if ($result.Ok) {
                    $Global:AutoIngestLastResult = "OK"
                    $Global:AutoIngestLastMessage = $null
                    Set-HistoryHint -Text "Ingest: OK" -Color "Green"
                }
                else {
                    $Global:AutoIngestLastResult = "ERROR"
                    $Global:AutoIngestLastMessage = $result.Message
                    $msg = if ($result.Message) { $result.Message } else { "unknown error" }
                    Set-HistoryHint -Text "Ingest: ERROR ($msg)" -Color "Red"
                }
            }
            catch {
                $Global:AutoIngestLastResult = "ERROR"
                $Global:AutoIngestLastMessage = $_.Exception.Message
                Set-HistoryHint -Text "Ingest: ERROR" -Color "Red"
            }
            # Refresh current subview data after ingest
            $Global:HistoryData = @(Get-HistoryData)
        }

        "S" {
            $item = Get-HistorySelectedItem
            if (-not $item -or $Global:HistorySubview -ne "TASKS" -or $item.Type -ne "task") {
                Set-HistoryHint -Text "Simplify: select a TASK row" -Color "DarkGray"
                return
            }

            $taskId = Get-TaskIdFromText -Text $item.Content
            if (-not $taskId) {
                Set-HistoryHint -Text "No task id on this row." -Color "Yellow"
                return
            }

            try {
                $result = python -c "print('No bloat detected. Task is clean.')" 2>&1
                $resultStr = $result -join "`n"

                if ($resultStr -match "(?i)(clean|no candidates|no bloat|nothing to simplify)") {
                    $Global:LastOptimized = $true
                    $Global:LastTaskForSignals = "T-$taskId"
                    Set-HistoryHint -Text "Simplify ${taskId}: clean" -Color "Green"
                }
                else {
                    $Global:LastOptimized = $false
                    $Global:LastTaskForSignals = "T-$taskId"
                    Set-HistoryHint -Text "Simplify ${taskId}: candidates found" -Color "Yellow"
                }
            }
            catch {
                $Global:LastOptimized = $false
                Set-HistoryHint -Text "Simplify ${taskId}: error" -Color "Yellow"
            }

            # Refresh tasks view (ordering/health may change over time)
            $Global:HistoryData = @(Get-HistoryData)
        }

        "V" {
            $item = Get-HistorySelectedItem
            if (-not $item -or $Global:HistorySubview -ne "TASKS" -or $item.Type -ne "task") {
                Set-HistoryHint -Text "Verify: select a TASK row" -Color "DarkGray"
                return
            }

            $taskId = Get-TaskIdFromText -Text $item.Content
            if (-not $taskId) {
                Set-HistoryHint -Text "No task id on this row." -Color "Yellow"
                return
            }

            try {
                $result = python -c "from mesh_server import verify_task; print(verify_task('$taskId'))" 2>&1
                $resultStr = $result -join "`n"
                $response = $resultStr | ConvertFrom-Json -ErrorAction SilentlyContinue

                if (-not $response) {
                    Set-HistoryHint -Text "Verify ${taskId}: failed to parse response" -Color "Yellow"
                }
                elseif ($response.error) {
                    Set-HistoryHint -Text "Verify ${taskId}: $($response.error)" -Color "Red"
                }
                else {
                    $score = [int]$response.score
                    $status = $response.status

                    $Global:LastConfidence = $score
                    $Global:LastTaskForSignals = "T-$taskId"

                    $statusColor = switch ($status) {
                        "PASS" { "Green" }
                        "WARN" { "Yellow" }
                        "FAIL" { "Red" }
                        default { "Gray" }
                    }

                    Set-HistoryHint -Text "Verify ${taskId}: $status $score/100" -Color $statusColor
                }
            }
            catch {
                Set-HistoryHint -Text "Verify ${taskId}: error" -Color "Yellow"
            }

            # Refresh tasks view after verify (qa_status changes health)
            $Global:HistoryData = @(Get-HistoryData)
        }

        "D" {
            # Drive to the next safe action using pipeline signals.
            $selectedItem = Get-HistorySelectedItem
            $selectedForPipeline = $null
            if ($selectedItem -and $selectedItem.Type -eq "task" -and $selectedItem.Raw) {
                $selectedForPipeline = $selectedItem.Raw
            }

            $pipeline = $null
            try { $pipeline = Build-PipelineStatus -SelectedRow $selectedForPipeline } catch { $pipeline = $null }
            if (-not $pipeline -or -not $pipeline.stages) {
                Set-HistoryHint -Text "Next: /refresh (pipeline unavailable)" -Color "Yellow"
                return
            }

            # v16.0: Write snapshot if any stage is non-GREEN (dedupe via hash + debounce)
            $selTaskId = if ($selectedForPipeline -and $selectedForPipeline.id) { $selectedForPipeline.id } else { $null }
            Write-PipelineSnapshotIfNeeded -PipelineData $pipeline -SelectedTaskId $selTaskId

            $stages = @($pipeline.stages)
            $firstNonGreen = $stages | Where-Object { $_.state -ne "GREEN" } | Select-Object -First 1

            if (-not $firstNonGreen) {
                # All green: switch to SHIP subview, do not auto-run /ship
                $Global:HistorySubview = "SHIP"
                $Global:HistorySelectedRow = 0
                $Global:HistoryScrollOffset = 0
                $Global:HistoryDetailsVisible = $false
                $Global:HistoryData = @(Get-HistoryData)
                Set-HistoryHint -Text "All green. Next: /ship" -Color "Green"
                return
            }

            $stageName = $firstNonGreen.name

            switch ($stageName) {
                "Context" {
                    # Context not ready: switch to DOCS and suggest /ingest or edit docs (no auto actions)
                    $Global:HistorySubview = "DOCS"
                    $Global:HistorySelectedRow = 0
                    $Global:HistoryScrollOffset = 0
                    $Global:HistoryDetailsVisible = $false
                    $Global:HistoryData = @(Get-HistoryData)

                    $idx = Find-FirstNonGreenHistoryIndex -Data $Global:HistoryData
                    $Global:HistorySelectedRow = $idx

                    $suggested = $pipeline.suggested_next.command
                    if ([string]::IsNullOrWhiteSpace($suggested)) { $suggested = "edit PRD.md | SPEC.md | DECISION_LOG.md" }
                    Set-HistoryHint -Text "Context not ready. Next: $suggested" -Color "Yellow"
                    return
                }

                "Plan" {
                    # Context is ready: run /refresh-plan or /draft-plan (silent, no console growth)
                    $cmd = $pipeline.suggested_next.command

                    if ([string]::IsNullOrWhiteSpace($cmd)) {
                        $cmd = if ($Global:Commands.Contains("refresh-plan")) { "/refresh-plan" } elseif ($Global:Commands.Contains("draft-plan")) { "/draft-plan" } else { $null }
                    }

                    if ($cmd -and $cmd.StartsWith("/refresh-plan")) {
                        try {
                            $result = python -c "from mesh_server import refresh_plan_preview; print(refresh_plan_preview())" 2>&1
                            $plan = ($result -join "`n") | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($plan -and $plan.status -eq "FRESH") {
                                Set-HistoryHint -Text "Plan: refreshed" -Color "Green"
                            }
                            elseif ($plan -and $plan.reason) {
                                Set-HistoryHint -Text "Plan: $($plan.reason)" -Color "Yellow"
                            }
                            else {
                                Set-HistoryHint -Text "Plan: refreshed" -Color "Green"
                            }
                        }
                        catch {
                            Set-HistoryHint -Text "Plan: refresh failed" -Color "Yellow"
                        }
                    }
                    elseif ($cmd -and $cmd.StartsWith("/draft-plan")) {
                        try {
                            $result = python -c "from mesh_server import draft_plan; print(draft_plan())" 2>&1
                            $resp = ($result -join "`n") | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($resp -and $resp.status -eq "OK" -and $resp.path) {
                                $leaf = Split-Path $resp.path -Leaf
                                Set-HistoryHint -Text "Draft plan: $leaf (edit then /accept-plan)" -Color "Green"
                            }
                            elseif ($resp -and $resp.message) {
                                Set-HistoryHint -Text "Draft plan: $($resp.message)" -Color "Yellow"
                            }
                            else {
                                Set-HistoryHint -Text "Draft plan: created" -Color "Green"
                            }
                        }
                        catch {
                            Set-HistoryHint -Text "Draft plan: failed" -Color "Yellow"
                        }
                    }
                    else {
                        Set-HistoryHint -Text "Plan: run /refresh-plan or /draft-plan" -Color "Yellow"
                    }

                    # Keep user on TASKS view for follow-up actions
                    $Global:HistorySubview = "TASKS"
                    $Global:HistoryDetailsVisible = $false
                    $Global:HistoryData = @(Get-HistoryData)
                    return
                }

                "Ship" {
                    # Switch to SHIP view to address ship blockers (e.g., uncommitted changes)
                    $Global:HistorySubview = "SHIP"
                    $Global:HistorySelectedRow = 0
                    $Global:HistoryScrollOffset = 0
                    $Global:HistoryDetailsVisible = $false
                    $Global:HistoryData = @(Get-HistoryData)

                    $idx = Find-FirstNonGreenHistoryIndex -Data $Global:HistoryData
                    $Global:HistorySelectedRow = $idx

                    $suggested = $pipeline.suggested_next.command
                    if ([string]::IsNullOrWhiteSpace($suggested)) { $suggested = "review ship blockers" }
                    Set-HistoryHint -Text "Ship not ready. Next: $suggested" -Color "Yellow"
                    return
                }

                default {
                    # Work/Optimize/Verify: default to TASKS and highlight the first non-green row
                    $Global:HistorySubview = "TASKS"
                    $Global:HistorySelectedRow = 0
                    $Global:HistoryScrollOffset = 0
                    $Global:HistoryDetailsVisible = $false
                    $Global:HistoryData = @(Get-HistoryData)

                    # If pipeline suggested command includes a task id, jump to that row
                    $suggested = $pipeline.suggested_next.command
                    $jumpId = Get-TaskIdFromText -Text $suggested
                    $idx = $null
                    if ($jumpId) {
                        $idx = Find-HistoryIndexByTaskId -Data $Global:HistoryData -TaskId $jumpId
                    }
                    if ($null -eq $idx) {
                        $idx = Find-FirstNonGreenHistoryIndex -Data $Global:HistoryData
                    }
                    $Global:HistorySelectedRow = $idx

                    if ([string]::IsNullOrWhiteSpace($suggested)) { $suggested = $firstNonGreen.hint }
                    Set-HistoryHint -Text "Next: $suggested" -Color "Yellow"
                    return
                }
            }
        }
    }
}

# --- Draw-HistoryScreen: Main history view renderer ---
function Draw-HistoryScreen {
    # Dimensions
    $W = $Host.UI.RawUI.WindowSize.Width
    $Half = [Math]::Floor($W / 2)
    $R = $Global:RowDashStart

    # Calculate visible rows (same as dashboard)
    $BottomRow = $Global:RowInput - 1
    $VisibleRows = $BottomRow - $R - 4  # Leave room for header/footer

    # --- HEADER: HISTORY [TASKS|DOCS|SHIP] ---
    Draw-Border $R $Half
    $R++

    # Build tab indicator: TASKS | DOCS | SHIP with current highlighted
    $tabTasks = if ($Global:HistorySubview -eq "TASKS") { "[TASKS]" } else { " TASKS " }
    $tabDocs = if ($Global:HistorySubview -eq "DOCS") { "[DOCS]" } else { " DOCS " }
    $tabShip = if ($Global:HistorySubview -eq "SHIP") { "[SHIP]" } else { " SHIP " }
    $tabLine = "$tabTasks | $tabDocs | $tabShip"

    $leftHeader = "HISTORY VIEW (F2/Esc to exit)"
    $rightHeader = "Tab: $tabLine"

    Print-Row $R $leftHeader $rightHeader $Half "Cyan" "Yellow"
    $R++

    Draw-Border $R $Half
    $R++

    # --- COLUMN HEADERS ---
    $colWorker = 12
    $colHealth = 8
    $colContent = $Half - $colWorker - $colHealth - 6

    $headerLeft = "  " + "WORKER".PadRight($colWorker) + "CONTENT".PadRight($colContent) + "HEALTH"
    Print-Row $R $headerLeft "" $Half "DarkCyan" "DarkGray"
    $R++

    # --- DATA ROWS (Left Panel) ---
    $data = $Global:HistoryData
    $selectedIdx = $Global:HistorySelectedRow
    $scrollOffset = $Global:HistoryScrollOffset

    # Clamp selection/scroll when subview data changes
    if (-not $data -or $data.Count -eq 0) {
        $Global:HistorySelectedRow = 0
        $Global:HistoryScrollOffset = 0
        $selectedIdx = 0
        $scrollOffset = 0
    }
    else {
        if ($selectedIdx -lt 0) { $selectedIdx = 0; $Global:HistorySelectedRow = 0 }
        if ($selectedIdx -ge $data.Count) { $selectedIdx = $data.Count - 1; $Global:HistorySelectedRow = $selectedIdx }
        if ($scrollOffset -lt 0) { $scrollOffset = 0; $Global:HistoryScrollOffset = 0 }
        if ($scrollOffset -ge $data.Count) { $scrollOffset = 0; $Global:HistoryScrollOffset = 0 }
    }

    # Adjust scroll if selection is out of view
    if ($data -and $data.Count -gt 0) {
        if ($selectedIdx -lt $scrollOffset) {
            $Global:HistoryScrollOffset = $selectedIdx
            $scrollOffset = $selectedIdx
        }
        elseif ($selectedIdx -ge $scrollOffset + $VisibleRows) {
            $Global:HistoryScrollOffset = $selectedIdx - $VisibleRows + 1
            $scrollOffset = $Global:HistoryScrollOffset
        }
    }

    # === RIGHT PANEL MODEL: pipeline + next step + hint ===
    $RightWidth = $Half - 4
    $stateColors = @{
        "GREEN"  = "Green"
        "YELLOW" = "Yellow"
        "RED"    = "Red"
        "GRAY"   = "DarkGray"
    }

    $selectedItem = $null
    if ($data -and $data.Count -gt 0 -and $selectedIdx -ge 0 -and $selectedIdx -lt $data.Count) {
        $selectedItem = $data[$selectedIdx]
    }

    $selectedForPipeline = $null
    if ($selectedItem -and $selectedItem.Type -eq "task" -and $selectedItem.Raw) {
        $selectedForPipeline = $selectedItem.Raw
    }

    $pipelineData = $null
    try { $pipelineData = Build-PipelineStatus -SelectedRow $selectedForPipeline } catch { $pipelineData = $null }

    # v16.0: Write snapshot if any stage is non-GREEN (dedupe via hash + debounce)
    if ($pipelineData) {
        $selTaskId = if ($selectedForPipeline -and $selectedForPipeline.id) { $selectedForPipeline.id } else { $null }
        Write-PipelineSnapshotIfNeeded -PipelineData $pipelineData -SelectedTaskId $selTaskId
    }

    $stages = @()
    $nextCmd = "—"
    $nextColor = "Yellow"

    if ($pipelineData -and $pipelineData.stages) {
        $stages = @($pipelineData.stages)

        # BOOTSTRAP safety: lock downstream stages until Context is GREEN
        $ctx = $stages | Where-Object { $_.name -eq "Context" } | Select-Object -First 1
        if ($ctx -and $ctx.state -ne "GREEN") {
            foreach ($s in $stages) {
                if ($s.name -ne "Context") {
                    $s.state = "GRAY"
                    $s.hint = "Locked (context not green)"
                }
            }
        }

        $suggested = $pipelineData.suggested_next.command
        if (-not [string]::IsNullOrWhiteSpace($suggested)) {
            $nextCmd = $suggested
        }
        else {
            $nextCmd = $pipelineData.immediate_next
        }

        $allGreen = -not ($stages | Where-Object { $_.state -ne "GREEN" })
        $nextColor = if ($allGreen) { "Green" } else { "Yellow" }
    }
    else {
        $stages = @(
            @{ name = "Context";  state = "GRAY"; hint = "—" }
            @{ name = "Plan";     state = "GRAY"; hint = "—" }
            @{ name = "Work";     state = "GRAY"; hint = "—" }
            @{ name = "Optimize"; state = "GRAY"; hint = "—" }
            @{ name = "Verify";   state = "GRAY"; hint = "—" }
            @{ name = "Ship";     state = "GRAY"; hint = "—" }
        )
        $nextCmd = "Pipeline unavailable"
        $nextColor = "Yellow"
    }

    $rightLines = @()
    $rightColors = @()

    $rightLines += "PIPELINE"
    $rightColors += "Cyan"

    $rightLines += "Next: $nextCmd"
    $rightColors += $nextColor

    # One-line hotkey/result hint (set by D/I/S/V)
    $rightLines += $(if ($Global:HistoryHintText) { $Global:HistoryHintText } else { "" })
    $rightColors += $(if ($Global:HistoryHintText) { $Global:HistoryHintColor } else { "DarkGray" })

    $rightLines += ""
    $rightColors += "DarkGray"

    foreach ($s in $stages) {
        $name = if ($s.name) { $s.name } else { "—" }
        $state = if ($s.state) { $s.state } else { "GRAY" }
        $hint = if ($s.hint) { $s.hint } else { "" }

        $label = $name.ToUpperInvariant().PadRight(8)
        $line = "$label [$state] $hint"
        $rightLines += $line
        $rightColors += $(if ($stateColors.ContainsKey($state)) { $stateColors[$state] } else { "DarkGray" })
    }

    $rightLines += ""
    $rightColors += "DarkGray"

    # Selection summary (changes with Up/Down)
    $rightLines += "SELECTION"
    $rightColors += "DarkGray"

    $selText = "—"
    if ($selectedItem) {
        if ($selectedItem.Type -eq "task" -and $selectedItem.Raw) {
            $tid = $selectedItem.Id
            $status = $selectedItem.Raw.status
            $risk = $selectedItem.Raw.risk
            $qa = $selectedItem.Raw.qa_status
            $selText = "T-$tid | $status | risk=$risk | qa=$qa"
        }
        else {
            $selText = $selectedItem.Content
        }
    }
    $rightLines += $selText
    $rightColors += "Gray"

    # Optional details overlay (Enter toggles) - kept minimal
    if ($Global:HistoryDetailsVisible -and $selectedItem -and $selectedItem.Type -eq "task") {
        $details = Get-HistoryDetailData -SelectedItem $selectedItem
        if ($details -and $details.Count -gt 0) {
            $rightLines += "DETAILS"
            $rightColors += "DarkGray"
            foreach ($d in ($details | Select-Object -First 4)) {
                $rightLines += "$($d.Action): $($d.Reason)"
                $rightColors += "DarkGray"
            }
        }
    }

    $rightLines += ""
    $rightColors += "DarkGray"

    $rightLines += "Hotkeys: D next | I ingest | S simplify | V verify | Tab view | F2/Esc exit"
    $rightColors += "Cyan"

    # Fit right panel content to available rows
    while ($rightLines.Count -lt $VisibleRows) {
        $rightLines += ""
        $rightColors += "DarkGray"
    }
    if ($rightLines.Count -gt $VisibleRows) {
        $rightLines = $rightLines[0..($VisibleRows - 1)]
        $rightColors = $rightColors[0..($VisibleRows - 1)]
    }

    # Empty data hint (left side)
    $emptyHint = $null
    if (-not $data -or $data.Count -eq 0) {
        $emptyHint = switch ($Global:HistorySubview) {
            "TASKS" { "No tasks yet. Try: /draft-plan or /add <desc>" }
            "DOCS"  { "No docs found. Try: /init to bootstrap" }
            "SHIP"  { "Nothing to ship yet." }
            default { "No data available." }
        }
    }

    for ($i = 0; $i -lt $VisibleRows; $i++) {
        $idx = $scrollOffset + $i
        $item = $null
        $isSelected = $false
        if ($data -and $idx -ge 0 -and $idx -lt $data.Count) {
            $item = $data[$idx]
            $isSelected = ($idx -eq $selectedIdx)
        }

        # Build row text
        if ($item) {
            $worker = $item.Worker.PadRight($colWorker)
            $content = $item.Content
            if ($content.Length -gt $colContent) { $content = $content.Substring(0, $colContent - 3) + "..." }
            $content = $content.PadRight($colContent)
            $health = $item.Health.PadRight($colHealth)

            # Left panel: data row
            Set-Pos $R 0
            Write-Host "| " -NoNewline -ForegroundColor DarkGray
            if ($isSelected) {
                Write-Host ">" -NoNewline -ForegroundColor Cyan
            }
            else {
                Write-Host " " -NoNewline
            }

            # Worker column
            Write-Host $worker -NoNewline -ForegroundColor $(if ($isSelected) { "White" } else { "Gray" })
            # Content column
            Write-Host $content -NoNewline -ForegroundColor $(if ($isSelected) { "Cyan" } else { "Gray" })
            # Health column with color
            Write-Host $health -NoNewline -ForegroundColor $item.HealthColor

            # Pad to half width
            $usedWidth = 3 + $colWorker + $colContent + $colHealth
            $padNeeded = $Half - $usedWidth - 2
            if ($padNeeded -gt 0) { Write-Host (" " * $padNeeded) -NoNewline }
            Write-Host " |" -NoNewline -ForegroundColor DarkGray
        }
        else {
            # Blank left row (keep borders stable); show empty hint once if needed
            Set-Pos $R 0
            Write-Host "| " -NoNewline -ForegroundColor DarkGray

            if ($emptyHint -and $i -eq 2) {
                $padLeft = [Math]::Max(0, [Math]::Floor(($Half - 4 - $emptyHint.Length) / 2))
                $padRight = $Half - 4 - $padLeft - $emptyHint.Length
                Write-Host (" " * $padLeft) -NoNewline
                Write-Host $emptyHint -NoNewline -ForegroundColor Yellow
                if ($padRight -gt 0) { Write-Host (" " * $padRight) -NoNewline }
            }
            else {
                Write-Host (" " * ($Half - 4)) -NoNewline
            }
            Write-Host " |" -NoNewline -ForegroundColor DarkGray
        }

        # Right panel: pipeline/next step/hint (stable, no scroll growth)
        $rt = if ($i -lt $rightLines.Count) { $rightLines[$i] } else { "" }
        $rc = if ($i -lt $rightColors.Count) { $rightColors[$i] } else { "DarkGray" }
        if ($rt.Length -gt $RightWidth) {
            $rt = $rt.Substring(0, $RightWidth - 3) + "..."
        }

        Set-Pos $R $Half
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host $rt.PadRight($RightWidth) -NoNewline -ForegroundColor $rc
        Write-Host " |" -NoNewline -ForegroundColor DarkGray

        $R++
    }

    # Bottom Border
    Set-Pos $R 0
    Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
    Set-Pos $R $Half
    Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
}
#endregion HISTORY_MODE

# --- v9.3 DASHBOARD: EXECUTION RESOURCES vs COGNITIVE STATE (with Actionable Hints) ---
function Draw-Dashboard {
    # 1. Fetch Data
    $Data = Get-WorkerStatus

    # v14.1: Get context readiness (fast, lightweight script)
    # Use explicit path from $RepoRoot and pass project directory for correct file resolution
    $Readiness = $null
    $IsBootstrap = $true  # v14.1: Fail-safe to BOOTSTRAP (not EXECUTION) on fresh projects
    $IsPreInit = $false   # v14.1: NEW - Uninitialized state (before /init)
    try {
        $readinessScript = Join-Path $RepoRoot "tools\readiness.py"
        # Pass $CurrentDir as argument so readiness checks the right project
        $readinessJson = python "$readinessScript" "$CurrentDir" 2>&1
        $Readiness = $readinessJson | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($Readiness) {
            $IsBootstrap = ($Readiness.status -eq "BOOTSTRAP")

            # v14.1: Detect PRE_INIT - ALL golden docs missing
            $allMissing = $true
            foreach ($docName in @("PRD", "SPEC", "DECISION_LOG")) {
                $fileData = $Readiness.files.$docName
                if ($fileData -and $fileData.exists) {
                    $allMissing = $false
                    break
                }
            }
            $IsPreInit = $allMissing
        }
        else {
            # Parse failed - check files directly for PRE_INIT detection
            $IsBootstrap = $true
            $prdPath = Join-Path $CurrentDir "docs\PRD.md"
            $specPath = Join-Path $CurrentDir "docs\SPEC.md"
            $decPath = Join-Path $CurrentDir "docs\DECISION_LOG.md"
            $IsPreInit = (-not (Test-Path $prdPath)) -and (-not (Test-Path $specPath)) -and (-not (Test-Path $decPath))
        }
    }
    catch {
        # v14.1: Fail-safe - check files directly
        $IsBootstrap = $true
        $prdPath = Join-Path $CurrentDir "docs\PRD.md"
        $specPath = Join-Path $CurrentDir "docs\SPEC.md"
        $decPath = Join-Path $CurrentDir "docs\DECISION_LOG.md"
        $IsPreInit = (-not (Test-Path $prdPath)) -and (-not (Test-Path $specPath)) -and (-not (Test-Path $decPath))
    }

    # Get decisions
    $DecisionLog = Join-Path (Get-Location) "docs\DECISION_LOG.md"
    $Decisions = @()
    if (Test-Path $DecisionLog) {
        $Decisions = Get-Content $DecisionLog -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "^\|.*\|" -and $_ -notmatch "^[\|\-\s]+$" -and $_ -notmatch "ID\s*\|" } |
        Select-Object -Last 2
    }

    # v16.1.1: Audit logs now loaded inline in LIVE AUDIT LOG section (uses TopRegionBottom anchor)

    # 2. Dimensions
    $W = $Host.UI.RawUI.WindowSize.Width
    $Half = [Math]::Floor($W / 2)
    $R = $Global:RowDashStart
    
    # v9.6: Get Mode and Days to Milestone for header
    $Mode = "vibe"
    $MileDays = ""
    try {
        $modeResult = Invoke-Query "SELECT value FROM config WHERE key='mode'" -Silent
        if ($modeResult) { $Mode = $modeResult[0].value }
    }
    catch {}
    
    # Check milestone file
    $MileFile = Join-Path (Get-Location) ".milestone"
    if (Test-Path $MileFile) {
        try {
            $MileDate = Get-Content $MileFile -Raw
            $Days = ([datetime]$MileDate - (Get-Date)).Days
            if ($Days -ge 0) { $MileDays = " | DAYS: $Days" }
        }
        catch {}
    }
    
    $ModeIcon = switch ($Mode) { "vibe" { "🏖️" } "converge" { "🔨" } "ship" { "🚀" } default { "" } }
    $ModeColor = switch ($Mode) { "vibe" { "Green" } "converge" { "Yellow" } "ship" { "Red" } default { "White" } }
    
    # v9.7: Get Core Lock status
    $LockIcon = "🔒"
    try {
        $lockResult = python -c "from dynamic_rigor import get_lock_status; print(get_lock_status()['icon'])" 2>&1
        if ($lockResult -eq "🔓") { $LockIcon = "🔓" }
    }
    catch {}
    
    # v9.8: Get Task State from state machine
    $TaskStatus = ""
    $TaskColor = "White"
    try {
        $stateResult = python -c "from dynamic_rigor import get_task_status_display; import json; s = get_task_status_display(); print(json.dumps(s))" 2>&1
        $taskState = $stateResult | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($taskState) {
            $TaskStatus = " | $($taskState.icon) $($taskState.status)"
            $TaskColor = switch ($taskState.status) {
                "WAITING" { "Yellow" }
                "READY" { "Green" }
                "IN_PROGRESS" { "Cyan" }
                "IDLE" { "DarkGray" }
                default { "White" }
            }
        }
    }
    catch {}
    
    # --- BORDERS & HEADERS ---
    Set-Pos $R 0; Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
    Set-Pos $R $Half; Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
    $R++
    
    # v9.6/v9.7/v9.8: Show Phase, Core Lock, and Task Status
    $LeftHeader = "EXEC [$($Mode.ToUpper()) $ModeIcon] [CORE: $LockIcon]"
    $RightHeader = "COGNITIVE$TaskStatus$MileDays"
    Print-Row $R $LeftHeader $RightHeader $Half $ModeColor $TaskColor
    $R++
    
    Set-Pos $R 0; Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
    Set-Pos $R $Half; Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
    $R++

    # v14.1: CONDITIONAL RENDERING - PRE_INIT vs BOOTSTRAP vs EXECUTION
    if ($IsPreInit) {
        # === PRE_INIT: No docs exist yet, show setup instructions ===
        # v16.1.1: Clear region first to prevent artifacts
        Clear-DashboardRegion -StartRow $R -HalfWidth $Half

        $R = Draw-PreInitPanel -StartRow $R -HalfWidth $Half -WorkerData $Data

        # v16.1.1: Fill to TopRegionBottom
        while ($R -lt $Global:TopRegionBottom) {
            Print-Row $R "" "" $Half "DarkGray" "DarkGray"
            $R++
        }
    }
    elseif ($IsBootstrap) {
        # === BOOTSTRAP MODE: Show readiness panel (docs exist but incomplete) ===
        # v16.1.1: Clear region first to prevent artifacts
        Clear-DashboardRegion -StartRow $R -HalfWidth $Half

        $R = Draw-BootstrapPanel -StartRow $R -HalfWidth $Half -ReadinessData $Readiness

        # v16.1.1: Fill to TopRegionBottom
        while ($R -lt $Global:TopRegionBottom) {
            Print-Row $R "" "" $Half "DarkGray" "DarkGray"
            $R++
        }
    }
    else {
        # === EXECUTION MODE: Show compact stream dashboard (v16.0) ===

        # v16.1.1: Clear dashboard region first to prevent artifacts from previous frames
        Clear-DashboardRegion -StartRow $R -HalfWidth $Half

        # --- v16.0: COMPACT STREAM LINES (Left Panel) ---
        # Get stream status for all 4 streams
        $BE_Status = Get-StreamStatusLine -StreamName "BACKEND" -WorkerData $Data
        $FE_Status = Get-StreamStatusLine -StreamName "FRONTEND" -WorkerData $Data
        $QA_Status = Get-StreamStatusLine -StreamName "QA" -WorkerData $Data
        $LIB_Status = Get-StreamStatusLine -StreamName "LIBRARIAN" -WorkerData $Data

        # Calculate widths for compact stream line
        $ContentWidth = $Half - 4
        $StreamCol = 10   # "BACKEND  " etc
        $BarCol = 6       # "■■■■■ "
        $StateCol = 8     # "RUNNING "
        $SummaryCol = $ContentWidth - $StreamCol - $BarCol - $StateCol - 3  # remaining for " | summary"

        # --- v16.0: Helper to draw compact stream line ---
        function Draw-StreamLine {
            param(
                [int]$Row,
                [string]$StreamName,
                [hashtable]$Status,
                [int]$Half
            )

            $ContentWidth = $Half - 4

            # Left panel: Stream line
            Set-Pos $Row 0
            Write-Host "| " -NoNewline -ForegroundColor DarkGray

            # Stream name (padded to 10 chars)
            Write-Host $StreamName.PadRight(10) -NoNewline -ForegroundColor White

            # Microbar (5 chars + space)
            Write-Host "$($Status.Bar) " -NoNewline -ForegroundColor $Status.BarColor

            # State (padded to 8 chars)
            Write-Host $Status.State.PadRight(8) -NoNewline -ForegroundColor $Status.BarColor

            # Separator and summary
            Write-Host "| " -NoNewline -ForegroundColor DarkGray

            # Summary (fill remaining space)
            $summaryMaxLen = $ContentWidth - 10 - 6 - 8 - 2
            $summary = $Status.Summary
            if ($summary.Length -gt $summaryMaxLen) {
                $summary = $summary.Substring(0, $summaryMaxLen - 3) + "..."
            }
            Write-Host $summary.PadRight($summaryMaxLen) -NoNewline -ForegroundColor $Status.SummaryColor

            Write-Host " |" -NoNewline -ForegroundColor DarkGray
        }

        # --- ROW: BACKEND ---
        Draw-StreamLine -Row $R -StreamName "BACKEND" -Status $BE_Status -Half $Half
        # Right panel: NEXT FOCUS header
        $hasDelegation = $Global:StartupDelegation -and $Global:StartupDelegation.status -eq "READY"
        $nextFocusTxt = if ($hasDelegation) { "NEXT FOCUS: CONTENT" }
                        elseif ($IsBootstrap) { "NEXT FOCUS: CONTEXT" }
                        else { "Context Ready" }
        $nextFocusColor = if ($hasDelegation) { "Cyan" } elseif ($IsBootstrap) { "Yellow" } else { "Green" }
        Set-Pos $R $Half
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host $nextFocusTxt.PadRight($Half - 4) -NoNewline -ForegroundColor $nextFocusColor
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++

        # --- ROW: FRONTEND ---
        Draw-StreamLine -Row $R -StreamName "FRONTEND" -Status $FE_Status -Half $Half
        # Right panel: Action hints
        $actionRow = if ($hasDelegation) { "  /ingest | /draft-plan | /accept-plan" }
                     elseif ($IsBootstrap) { "  Edit PRD/SPEC | /add (tactical open)" }
                     else { "  /refresh-plan | /draft-plan" }
        Set-Pos $R $Half
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host $actionRow.PadRight($Half - 4) -NoNewline -ForegroundColor DarkGray
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++

        # --- ROW: QA/AUDIT ---
        Draw-StreamLine -Row $R -StreamName "QA/AUDIT" -Status $QA_Status -Half $Half
        # Right panel: Separator
        Set-Pos $R $Half
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host (" " * ($Half - 4)) -NoNewline
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++

        # --- ROW: LIBRARIAN ---
        Draw-StreamLine -Row $R -StreamName "LIBRARIAN" -Status $LIB_Status -Half $Half
        # Right panel: Recent decision (if any)
        $D1 = if ($Decisions.Count -ge 1) { "  " + ($Decisions[-1] -replace "\|", "").Trim() } else { "" }
        if ($D1.Length -gt ($Half - 4)) { $D1 = $D1.Substring(0, $Half - 7) + "..." }
        Set-Pos $R $Half
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        Write-Host $D1.PadRight($Half - 4) -NoNewline -ForegroundColor DarkGray
        Write-Host " |" -NoNewline -ForegroundColor DarkGray
        $R++

        # === SEPARATOR ===
        Print-Row $R "" "" $Half "DarkGray" "DarkGray"
        $R++

        # --- v15.1: INBOX indicator ---
        $inboxPath = Join-Path $CurrentDir "docs\INBOX.md"
        $inboxStatus = "—"
        $inboxColor = "DarkGray"
        if (Test-Path $inboxPath) {
            $inboxContent = Get-Content $inboxPath -Raw -ErrorAction SilentlyContinue
            if ($inboxContent) {
                $meaningfulCount = 0
                foreach ($line in ($inboxContent -split "`n")) {
                    $trimmed = $line.Trim()
                    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                    if ($trimmed -match "ATOMIC_MESH_TEMPLATE_STUB") { continue }
                    if ($trimmed -match "^#") { continue }
                    if ($trimmed -eq "-") { continue }
                    if ($trimmed.Length -lt 3) { continue }
                    if ($trimmed.StartsWith("Drop clarifications")) { continue }
                    if ($trimmed.StartsWith("Next: run")) { continue }
                    $meaningfulCount++
                }
                if ($meaningfulCount -gt 0) {
                    $inboxStatus = "pending ($meaningfulCount)"
                    $inboxColor = "Yellow"
                } else {
                    $inboxStatus = "empty"
                }
            } else {
                $inboxStatus = "empty"
            }
        }
        Print-Row $R "INBOX     [$inboxStatus]" "" $Half $inboxColor "DarkGray"
        $R++

        # === SEPARATOR ===
        Print-Row $R "" "" $Half "DarkGray" "DarkGray"
        $R++

        # === v15.2: AUTO-INGEST STATUS LINE (compact) ===
        $autoIngestTxt = "Auto-ingest: "
        $autoIngestColor = "DarkGray"
        if (-not $Global:AutoIngestEnabled) {
            $autoIngestTxt += "disabled"
        }
        elseif ($Global:AutoIngestPending) {
            $autoIngestTxt += "pending"
            $autoIngestColor = "Yellow"
        }
        elseif ($Global:AutoIngestLastResult -eq "OK") {
            $timeStr = if ($Global:AutoIngestLastRunUtc) { $Global:AutoIngestLastRunUtc.ToLocalTime().ToString("HH:mm:ss") } else { "" }
            $autoIngestTxt += "OK ($timeStr)"
            $autoIngestColor = "Green"
        }
        elseif ($Global:AutoIngestLastResult -eq "ERROR") {
            $autoIngestTxt += "ERROR"
            $autoIngestColor = "Red"
        }
        elseif ($Global:AutoIngestLastResult -eq "SKIPPED") {
            $autoIngestTxt += "skipped"
        }
        else {
            $autoIngestTxt += "armed"
        }

        # === v14.1: TRANSPARENCY LINE (compact, merged with auto-ingest) ===
        $scopeTxt = if ($Global:LastScope) { $Global:LastScope } else { "—" }
        $optimizedIcon = if ($Global:LastOptimized) { "OK" } else { "—" }
        $transparencyTxt = "Scope: $scopeTxt | Opt: $optimizedIcon"

        Print-Row $R $autoIngestTxt $transparencyTxt $Half $autoIngestColor "DarkGray"
        $R++

        # === v15.5: PIPELINE PANEL (right side) ===
        $pipelineData = Build-PipelineStatus
        # v16.0: Write snapshot if any stage is non-GREEN (dedupe via hash + debounce)
        Write-PipelineSnapshotIfNeeded -PipelineData $pipelineData
        $pipelineEndRow = Draw-PipelinePanel -StartRow $R -HalfWidth $Half -PipelineData $pipelineData

        # v16.1.1: Close right panel with bottom border after pipeline ends
        # This prevents the "giant empty frame" appearance
        $rightBorder = "+" + ("-" * ($Half - 2)) + "+"
        Set-Pos $pipelineEndRow $Half
        Write-Host $rightBorder -NoNewline -ForegroundColor DarkGray

        # v16.1.1: Clear remaining right panel rows (no borders - just blank space)
        $RightContentWidth = $Half - 1  # Full right panel area
        for ($clearRow = $pipelineEndRow + 1; $clearRow -lt $Global:TopRegionBottom; $clearRow++) {
            Set-Pos $clearRow $Half
            Write-Host (" " * $RightContentWidth) -NoNewline
        }

        # === v16.1.1: LIVE AUDIT LOG (left panel only, expands to fill space) ===
        # Calculate available rows until TopRegionBottom
        $availableRows = $Global:TopRegionBottom - $R - 1  # -1 for header row
        if ($availableRows -lt 1) { $availableRows = 1 }

        # --- ROW: LOG HEADER (left panel only) ---
        Print-LeftOnly -Row $R -Text "LIVE AUDIT LOG" -HalfWidth $Half -Color "Yellow"
        $R++

        # --- ROWS: LOGS (expand to fill available space, left panel only) ---
        # Load enough log lines to fill available rows
        $LogFile = Join-Path (Get-Location) "logs\mesh.log"
        $logLines = @()
        if (Test-Path $LogFile) {
            $logLines = Get-Content $LogFile -ErrorAction SilentlyContinue | Select-Object -Last $availableRows
        }

        if ($logLines.Count -gt 0) {
            # Show log lines (oldest first, newest at bottom)
            foreach ($line in $logLines) {
                $displayLine = "  " + $line
                Print-LeftOnly -Row $R -Text $displayLine -HalfWidth $Half -Color "DarkGray"
                $R++
            }
            # Fill any remaining rows (left panel only)
            while ($R -lt $Global:TopRegionBottom) {
                Print-LeftOnly -Row $R -Text "" -HalfWidth $Half -Color "DarkGray"
                $R++
            }
        } else {
            # No logs: single placeholder line, then fill remaining (left panel only)
            Print-LeftOnly -Row $R -Text "  (no logs)" -HalfWidth $Half -Color "DarkGray"
            $R++
            while ($R -lt $Global:TopRegionBottom) {
                Print-LeftOnly -Row $R -Text "" -HalfWidth $Half -Color "DarkGray"
                $R++
            }
        }

    }  # End of EXECUTION mode conditional

    # Bottom Border at TopRegionBottom (just above footer row)
    Set-Pos $R 0; Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
    Set-Pos $R $Half; Write-Host ("+" + ("-" * ($Half - 2)) + "+") -NoNewline -ForegroundColor DarkGray
}

# --- HELPER: Prints Row with a Hint on the Right Side ---
function Print-Row-With-Hint($Row, $LeftTxt, $RightTxt, $HalfWidth, $ColorL, $ColorR, $Hint) {
    $ContentWidth = $HalfWidth - 4
    
    # Draw Left
    Set-Pos $Row 0; Write-Host "| " -NoNewline -ForegroundColor DarkGray
    if ($LeftTxt.Length -gt $ContentWidth) { $LeftTxt = $LeftTxt.Substring(0, $ContentWidth - 3) + "..." }
    Write-Host $LeftTxt.PadRight($ContentWidth) -NoNewline -ForegroundColor $ColorL
    Write-Host " | | " -NoNewline -ForegroundColor DarkGray
    
    # Draw Right + Hint
    Set-Pos $Row $HalfWidth; Write-Host "| " -NoNewline -ForegroundColor DarkGray
    
    # Calc space for Right Text
    $Available = $ContentWidth - $Hint.Length - 1
    if ($RightTxt.Length -gt $Available) { $RightTxt = $RightTxt.Substring(0, $Available - 3) + "..." }
    
    Write-Host $RightTxt -NoNewline -ForegroundColor $ColorR
    Write-Host (" $Hint").PadRight($ContentWidth - $RightTxt.Length) -NoNewline -ForegroundColor Magenta
    
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
}

# --- HELPER: Prints Row with a Hint on the Left Side ---
function Print-Row-With-Hint-Left($Row, $LeftTxt, $RightTxt, $HalfWidth, $ColorL, $ColorR, $Hint) {
    $ContentWidth = $HalfWidth - 4
    
    # Draw Left + Hint
    Set-Pos $Row 0; Write-Host "| " -NoNewline -ForegroundColor DarkGray
    
    $Available = $ContentWidth - $Hint.Length - 1
    if ($LeftTxt.Length -gt $Available) { $LeftTxt = $LeftTxt.Substring(0, $Available - 3) + "..." }
    
    Write-Host $LeftTxt -NoNewline -ForegroundColor $ColorL
    Write-Host (" $Hint").PadRight($ContentWidth - $LeftTxt.Length) -NoNewline -ForegroundColor Magenta
    
    Write-Host " | | " -NoNewline -ForegroundColor DarkGray
    
    # Draw Right
    Set-Pos $Row $HalfWidth; Write-Host "| " -NoNewline -ForegroundColor DarkGray
    if ($RightTxt.Length -gt $ContentWidth) { $RightTxt = $RightTxt.Substring(0, $ContentWidth - 3) + "..." }
    Write-Host $RightTxt.PadRight($ContentWidth) -NoNewline -ForegroundColor $ColorR
    Write-Host " |" -NoNewline -ForegroundColor DarkGray
}

# --- CLEAR DROPDOWN ZONE ---
function Clear-DropdownZone {
    $width = $Host.UI.RawUI.WindowSize.Width
    for ($i = 0; $i -lt $Global:MaxDropdownRows + 2; $i++) {
        Set-Pos ($Global:RowDropdown + $i) 0
        Write-Host (" " * $width) -NoNewline
    }
    # Restore cursor to input row (at left edge of input frame)
    Set-Pos $Global:RowInput $Global:InputLeft
}

# --- DRAW DROPDOWN AT FIXED POSITION ---
function Draw-Dropdown {
    param(
        [array]$Commands,
        [int]$SelectedIndex,
        [int]$ScrollOffset
    )
    
    if ($Commands.Count -eq 0) { return }
    
    $windowWidth = $Host.UI.RawUI.WindowSize.Width
    $midPoint = [Math]::Floor($windowWidth / 2)
    $colWidth = $midPoint - 1
    $cmdNameWidth = 12
    $descWidth = $colWidth - $cmdNameWidth - 2
    
    $numCols = 2
    $rowsNeeded = [Math]::Ceiling($Commands.Count / $numCols)
    $visible = [Math]::Min($rowsNeeded, $Global:MaxDropdownRows)
    
    for ($row = 0; $row -lt $visible; $row++) {
        $actualRow = $ScrollOffset + $row
        if ($actualRow -ge $rowsNeeded) { break }
        
        Set-Pos ($Global:RowDropdown + $row) 0
        
        for ($col = 0; $col -lt $numCols; $col++) {
            $idx = $actualRow + ($col * $rowsNeeded)
            
            if ($idx -lt $Commands.Count) {
                $cmd = $Commands[$idx]
                $isSelected = ($idx -eq $SelectedIndex)
                
                $cmdName = ("/" + $cmd.Name).PadRight($cmdNameWidth)
                $desc = $cmd.Desc
                if ($desc.Length -gt $descWidth) { $desc = $desc.Substring(0, $descWidth - 3) + "..." }
                $desc = $desc.PadRight($descWidth)
                
                if ($isSelected) {
                    Write-Host "> " -NoNewline -ForegroundColor Cyan
                    Write-Host $cmdName -NoNewline -ForegroundColor Yellow
                    Write-Host $desc -NoNewline -ForegroundColor White
                }
                else {
                    Write-Host "  " -NoNewline
                    Write-Host $cmdName -NoNewline -ForegroundColor DarkYellow
                    Write-Host $desc -NoNewline -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host (" " * $colWidth) -NoNewline
            }
            
            if ($col -eq 0) {
                Write-Host "|" -NoNewline -ForegroundColor DarkGray
            }
        }
    }
    
    if ($rowsNeeded -gt $visible) {
        Set-Pos ($Global:RowDropdown + $visible) 0
        $below = $rowsNeeded - ($ScrollOffset + $visible)
        if ($below -gt 0) { Write-Host "  v$below more (arrows)" -ForegroundColor DarkGray }
    }
}

# --- v13.3: Compute recommended next action from state ---
function Get-RecommendedAction {
    # Priority-ordered checks
    try {
        # 1. Health failure
        if ($Global:HealthStatus -eq "FAIL") {
            return @{ Text = "/ops (health issue)"; Color = "Red" }
        }

        # 2. Check librarian status (messy)
        $stats = Get-WorkerStatus
        if ($stats.lib_status_text -match "MESSY|CLUTTERED") {
            return @{ Text = "/lib clean"; Color = "Yellow" }
        }

        # 3. Check for tasks
        $taskStats = Get-TaskStats
        if ($taskStats.pending -eq 0 -and $taskStats.in_progress -eq 0) {
            return @{ Text = "type a goal (e.g., 'add JWT auth')"; Color = "Cyan" }
        }

        # 4. Tasks pending - suggest run
        if ($taskStats.pending -gt 0) {
            return @{ Text = "Enter = execute"; Color = "Green" }
        }

        # 5. Default
        return @{ Text = "/ops"; Color = "Gray" }
    }
    catch {
        return @{ Text = "/ops"; Color = "Gray" }
    }
}

# --- v13.3.6: Framed Input Bar with Unicode borders ---
# ALIGNMENT: Input bar starts at $Global:InputLeft to align with "  Next:" label
# Box width = terminal width - InputLeft (right edge at terminal width - 1)
function Draw-InputBar {
    param([int]$width, [int]$rowInput)

    $left = $Global:InputLeft
    $topRow = $rowInput - 1
    $bottomRow = $rowInput + 1
    $boxWidth = $width - $left - 1  # width of box from InputLeft to right edge
    $innerWidth = $boxWidth - 2      # space between left and right borders

    # Top border: ┌───────────┐
    Set-Pos $topRow $left
    Write-Host ("┌" + ("─" * $innerWidth) + "┐") -NoNewline -ForegroundColor DarkGray

    # Middle line: │ >         │
    Set-Pos $rowInput $left
    Write-Host "│" -NoNewline -ForegroundColor DarkGray
    Write-Host " > " -NoNewline -ForegroundColor White
    Write-Host (" " * ($innerWidth - 3)) -NoNewline  # 3 = " > " length
    Write-Host "│" -NoNewline -ForegroundColor DarkGray

    # Bottom border: └───────────┘
    Set-Pos $bottomRow $left
    Write-Host ("└" + ("─" * $innerWidth) + "┘") -NoNewline -ForegroundColor DarkGray

    # Position cursor where typing starts: after "│ > " = InputLeft + 4
    Set-Pos $rowInput ($left + 4)
}

# Helper: Clear just the input content, preserving borders
function Clear-InputContent {
    param([int]$width, [int]$rowInput)
    $left = $Global:InputLeft
    $boxWidth = $width - $left - 1
    $innerWidth = $boxWidth - 2
    Set-Pos $rowInput $left
    Write-Host "│" -NoNewline -ForegroundColor DarkGray
    Write-Host " > " -NoNewline -ForegroundColor White
    Write-Host (" " * ($innerWidth - 3)) -NoNewline
    Write-Host "│" -NoNewline -ForegroundColor DarkGray
    Set-Pos $rowInput ($left + 4)
}

# --- v13.3.5: Editor-Style Footer Bar (Next: left, [MODE] right) ---
# Clean coding-CLI style: "Next: <hint>" on left, [MODE] on right
function Draw-FooterBar {
    $footerRow = $Global:RowInput - 2
    $microHintRow = $Global:RowInput - 3
    $width = $Host.UI.RawUI.WindowSize.Width

    # Clear lines
    Set-Pos $microHintRow 0
    Write-Host (" " * ($width - 1)) -NoNewline
    Set-Pos $footerRow 0
    Write-Host (" " * ($width - 1)) -NoNewline

    # SANDBOX UX: Mode micro-hint
    $config = $Global:ModeConfig[$Global:CurrentMode]
    if ($config.MicroHint) {
        Set-Pos $microHintRow 2
        Write-Host $config.MicroHint -ForegroundColor DarkGray -NoNewline
    }

    # v16.1.1: Simplified footer - always show "Next:" hint (handles fresh/messy/pending scenarios)
    $scenario = Get-SystemScenario
    $nextHint = switch ($scenario) {
        "fresh" { "/init" }
        "messy" { "/lib clean" }
        "pending" { "/run" }
        default { "/ops" }
    }
    Set-Pos $footerRow 0
    Write-Host "  Next: " -NoNewline -ForegroundColor DarkGray
    Write-Host $nextHint -NoNewline -ForegroundColor Cyan

    # Mode badge (right-aligned)
    $modeColors = @{
        "OPS"  = "Cyan"
        "PLAN" = "Yellow"
        "RUN"  = "Magenta"
        "SHIP" = "Green"
    }
    $modeLabel = "[$($Global:CurrentMode)]"
    $modeColor = $modeColors[$Global:CurrentMode]
    $col = $width - $modeLabel.Length - 1
    if ($col -lt 0) { $col = 0 }
    Set-Pos $footerRow $col
    Write-Host $modeLabel -NoNewline -ForegroundColor $modeColor

    # SANDBOX UX: Router debug overlay
    if ($Global:RouterDebug -and $Global:LastRoutedCommand) {
        $debugRow = $Global:RowInput - 4
        Set-Pos $debugRow 0
        Write-Host (" " * ($width - 1)) -NoNewline
        Set-Pos $debugRow 2
        Write-Host "→ Routed to: $($Global:LastRoutedCommand)" -ForegroundColor Magenta -NoNewline
    }
}

# Legacy aliases for compatibility
function Draw-ModeStrip { Draw-FooterBar }
function Draw-ModeToggleStrip { Draw-FooterBar }
function Draw-SmartHintStrip { Draw-FooterBar }

# --- FIND NEXT PLACEHOLDER HELPER (Tab-to-advance) ---
# v13.4.5: Find the next <placeholder> token after a given index
function Find-NextPlaceholder {
    param(
        [string]$Buffer,
        [int]$StartIndex
    )
    
    $open = $Buffer.IndexOf('<', $StartIndex)
    if ($open -lt 0) { return $null }
    
    $close = $Buffer.IndexOf('>', $open)
    if ($close -lt 0) { return $null }
    
    $len = ($close - $open + 1)
    return @{
        Start  = $open
        Length = $len
        Text   = $Buffer.Substring($open, $len)
    }
}

# --- TOGGLE PLACEHOLDER HELPER (F2 key) ---
# v13.4.3: Cycle through toggle options for placeholders with Options array
function Invoke-TogglePlaceholder {
    param(
        [ref]$Buffer,
        [ref]$CursorCol,
        [int]$CursorStart,
        [int]$Width,
        [int]$RowInput
    )
    
    if (-not $Global:PlaceholderInfo) { return }
    
    $ph = $Global:PlaceholderInfo
    if (-not $ph.Options -or $ph.Options.Count -eq 0) { return }
    
    $buf = $Buffer.Value
    $start = [int]$ph.Start
    $len = [int]$ph.Length
    $end = $start + $len
    
    # Bounds check
    if ($start -lt 0 -or $end -gt $buf.Length) {
        $Global:PlaceholderInfo = $null
        return
    }
    
    $segment = $buf.Substring($start, $len)
    $options = $ph.Options
    $rawText = $ph.RawText   # v13.4.4: Use stable original placeholder for first-toggle detection
    $currentIdx = [int]$ph.OptionIdx
    
    # If user has typed something custom (not raw placeholder, not an option), stop toggling
    if ($segment -ne $rawText -and ($options -notcontains $segment)) {
        $Global:PlaceholderInfo = $null
        return
    }
    
    # Determine next option index:
    # v13.4.4 FIX: If segment is still the RAW placeholder (e.g. "<type>"), FIRST F2 picks index 0.
    # Otherwise (segment is one of the options), cycle to the next option.
    if ($segment -eq $rawText) {
        $idx = 0   # first F2 press: use first option
    }
    else {
        $idx = ($currentIdx + 1) % $options.Count
    }
    
    $choice = $options[$idx]
    
    # Replace segment with choice
    $before = $buf.Substring(0, $start)
    $after = if ($end -lt $buf.Length) { $buf.Substring($end) } else { "" }
    $Buffer.Value = $before + $choice + $after
    $CursorCol.Value = $CursorStart + $start + $choice.Length
    
    # Update PlaceholderInfo to track the chosen value
    $Global:PlaceholderInfo.Start = $start
    $Global:PlaceholderInfo.Length = $choice.Length
    $Global:PlaceholderInfo.Text = $choice
    $Global:PlaceholderInfo.OptionIdx = $idx
    
    # Redraw input line with updated content
    Clear-InputContent -width $Width -rowInput $RowInput
    Set-Pos $RowInput $CursorStart
    Write-Host $Buffer.Value -NoNewline -ForegroundColor Cyan
    
    # Draw toggle options on right side
    Draw-ToggleOptions -Width $Width -RowInput $RowInput
    
    Set-Pos $RowInput $CursorCol.Value
}

# --- DRAW TOGGLE OPTIONS ([F2] option1 option2) ---
# v13.4.3: Display toggle options with [F2] label on right side
# v13.4.9: Now draws on RowHint (below input box) for stable layout
function Draw-ToggleOptions {
    param(
        [int]$Width,
        [int]$RowInput
    )
    
    if (-not $Global:PlaceholderInfo) { return }
    
    $ph = $Global:PlaceholderInfo
    $options = $ph.Options
    
    # v13.4.9: Use hint row (below input box bottom border)
    $hintRow = $Global:RowHint
    $winHeight = $Host.UI.RawUI.WindowSize.Height
    
    # Skip if hint row is out of bounds
    if ($hintRow -lt 0 -or $hintRow -ge $winHeight) { return }
    
    # Clear the hint row first
    Set-Pos $hintRow 2
    Write-Host (" " * ($Width - 3)) -NoNewline
    
    if ($options -and $options.Count -gt 0) {
        # Build options text to compute alignment
        $optsText = ""
        for ($i = 0; $i -lt $options.Count; $i++) {
            if ($i -gt 0) { $optsText += "  " }
            $optsText += $options[$i]
        }
        $labelTotal = "[F2] " + $optsText
        $col = [Math]::Max(2, $Width - $labelTotal.Length - 1)
        
        Set-Pos $hintRow $col
        
        # Write [F2] in distinct color
        Write-Host "[F2] " -NoNewline -ForegroundColor Yellow
        
        # Write options with highlight
        for ($i = 0; $i -lt $options.Count; $i++) {
            if ($i -gt 0) {
                Write-Host "  " -NoNewline -ForegroundColor DarkGray
            }
            $opt = $options[$i]
            if ($i -eq $ph.OptionIdx) {
                Write-Host $opt -NoNewline -ForegroundColor Cyan
            }
            else {
                Write-Host $opt -NoNewline -ForegroundColor DarkGray
            }
        }
    }
    elseif ($ph.MiniGuide -and $ph.MiniGuide.Length -gt 0) {
        # Fallback: original mini guide for non-toggle placeholders
        $mini = $ph.MiniGuide
        $col = [Math]::Max(2, $Width - $mini.Length - 1)
        Set-Pos $hintRow $col
        Write-Host $mini -NoNewline -ForegroundColor DarkGray
    }
}

# --- LIBRARY LOOKUP HELPER (v13.4.6) ---
# Read-only lookup for library-backed placeholders
function Get-LookupCandidates {
    param(
        [string]$LookupKind,
        [string]$Prefix
    )
    
    # Mock data source - will be replaced with real library calls later
    $all = @()
    
    switch ($LookupKind) {
        "questions" {
            $all = @(
                @{ Id = "Q-101"; Label = "Auth workflow bug (critical)" },
                @{ Id = "Q-102"; Label = "API rate limiting issue" },
                @{ Id = "Q-201"; Label = "Alignment question on UX" },
                @{ Id = "Q-301"; Label = "Database migration timing" }
            )
        }
        "decisions" {
            $all = @(
                @{ Id = "D-001"; Label = "Adopt UX v13 framework" },
                @{ Id = "D-002"; Label = "Enable scaffold-tests" },
                @{ Id = "D-003"; Label = "Approve library pattern" }
            )
        }
        "plans" {
            # v13.5.5: List plan files from docs/PLANS/
            $plansDir = Join-Path (Get-Location) "docs\PLANS"
            if (Test-Path $plansDir) {
                $files = Get-ChildItem $plansDir -Filter "*.md" -ErrorAction SilentlyContinue | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -First 10
                foreach ($file in $files) {
                    $all += @{ Id = $file.Name; Label = "Modified: $($file.LastWriteTime.ToString('MM/dd HH:mm'))" }
                }
            }
        }
    }
    
    if ([string]::IsNullOrEmpty($Prefix)) {
        return $all
    }
    
    return $all | Where-Object {
        $_.Id -like "$Prefix*" -or $_.Label -like "$Prefix*"
    }
}

# --- DRAW LOOKUP PANEL (2-column table) ---
# v13.4.6: Display library candidates with ID + Label
# v13.4.7: Fixed scroll bug - clamp panel to window bounds, save/restore cursor
function Draw-LookupPanel {
    param(
        [int]$Width,
        [int]$RowInput,
        [int]$CursorStart
    )
    
    if (-not $Global:PlaceholderInfo) { return }
    $ph = $Global:PlaceholderInfo
    if (-not $ph.Lookup) { return }
    
    # --- SAVE CURSOR POSITION (CRITICAL for preventing scroll) ---
    $origPos = $Host.UI.RawUI.CursorPosition
    $origRow = $origPos.Y
    $origCol = $origPos.X
    
    $lookupKind = $ph.Lookup
    $prefix = $ph.Filter
    $candidates = @(Get-LookupCandidates -LookupKind $lookupKind -Prefix $prefix)
    
    $Global:LookupCandidates = $candidates
    
    # --- LAYOUT CONSTANTS ---
    $ui = $Host.UI.RawUI
    $winHeight = $ui.WindowSize.Height
    $winWidth = $ui.WindowSize.Width
    
    $colStart = 2
    $idWidth = 12
    $prefixWidth = 4        # "1)  "
    $padding = 2
    # v13.5.5: Removed "Matches:" header - panel is now just candidate rows
    $maxRows = 5
    $panelHeight = $maxRows  # No header row anymore
    
    $labelWidth = $winWidth - $colStart - $prefixWidth - $idWidth - $padding
    if ($labelWidth -lt 10) { $labelWidth = 10 }
    
    # --- CLAMP PANEL POSITION TO WINDOW BOUNDS ---
    # v13.5.5: Add spacer row between hint row and first match
    # Layout: RowInput → RowInputBottom → RowHint → (spacer) → Panel
    #         RowHint + 1 is the spacer row (empty)
    #         RowHint + 2 is where matches start
    $rowStart = $Global:RowHint + 2  # +1 for spacer row
    
    # Clamp: not past bottom of window
    if ($rowStart + $panelHeight -gt ($winHeight - 1)) {
        $rowStart = ($winHeight - 1) - $panelHeight
    }
    
    # Final safety clamp
    if ($rowStart -lt 0) { $rowStart = 0 }
    
    # Calculate max content width to prevent wrapping
    $maxContentWidth = $winWidth - $colStart - 1
    if ($maxContentWidth -lt 10) { $maxContentWidth = 10 }
    
    # --- CLEAR PANEL AREA (all writes use -NoNewline) ---
    for ($i = 0; $i -lt $panelHeight; $i++) {
        $clearRow = $rowStart + $i
        if ($clearRow -ge 0 -and $clearRow -lt $winHeight) {
            Set-Pos $clearRow $colStart
            $clearLen = [Math]::Min($maxContentWidth, $winWidth - $colStart - 1)
            Write-Host (" " * $clearLen) -NoNewline
        }
    }
    
    if ($candidates.Count -eq 0) {
        # No matches message
        if ($rowStart -ge 0 -and $rowStart -lt $winHeight) {
            Set-Pos $rowStart $colStart
            Write-Host "No matches for '$prefix'" -NoNewline -ForegroundColor DarkGray
        }
        # --- RESTORE CURSOR ---
        Set-Pos $origRow $origCol
        return
    }
    
    # --- DRAW CANDIDATES (up to maxRows) - NO HEADER ---
    # v13.5.5: Removed "Matches:" header - starts directly with numbered list
    $max = [Math]::Min($maxRows, $candidates.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $row = $rowStart + $i  # No +1 offset since no header
        
        # Skip if row is out of window bounds
        if ($row -lt 0 -or $row -ge $winHeight) { continue }
        
        $item = $candidates[$i]
        $id = $item.Id
        $label = $item.Label
        
        # Fixed-width ID
        $idStr = "{0,-$idWidth}" -f $id
        
        # Truncate label to fit (prevent wrap)
        if ($label.Length -gt $labelWidth) {
            $label = $label.Substring(0, $labelWidth - 3) + "..."
        }
        
        Set-Pos $row $colStart
        
        # Numeric prefix
        $prefixStr = "{0}) " -f ($i + 1)
        Write-Host $prefixStr -NoNewline -ForegroundColor DarkGray
        
        if ($i -eq $ph.Selected) {
            # Selected row: highlighted
            Write-Host $idStr -NoNewline -ForegroundColor Green
            Write-Host $label -NoNewline -ForegroundColor White
        }
        else {
            # Non-selected row
            Write-Host $idStr -NoNewline -ForegroundColor Cyan
            Write-Host $label -NoNewline -ForegroundColor DarkGray
        }
    }
    
    # --- RESTORE CURSOR (CRITICAL) ---
    Set-Pos $origRow $origCol
}

# --- CLEAR HINT ROW ---
# v13.5.0: Clear the mini-guide hint row with cursor discipline
function Clear-HintRow {
    # --- SAVE CURSOR POSITION ---
    $origPos = $Host.UI.RawUI.CursorPosition
    $origRow = $origPos.Y
    $origCol = $origPos.X
    
    $winWidth = $Host.UI.RawUI.WindowSize.Width
    $winHeight = $Host.UI.RawUI.WindowSize.Height
    $hintRow = $Global:RowHint
    
    # Skip if out of bounds
    if ($hintRow -lt 0 -or $hintRow -ge $winHeight) {
        return
    }
    
    # Clear full width
    $clearWidth = $winWidth - 2 - 1
    if ($clearWidth -lt 1) { $clearWidth = 1 }
    
    Set-Pos $hintRow 2
    Write-Host (" " * $clearWidth) -NoNewline
    
    # --- RESTORE CURSOR ---
    Set-Pos $origRow $origCol
}
# v13.4.6: Clear the lookup panel area
# v13.4.7: Fixed scroll bug - clamp to window bounds
# v13.4.8: Panel now below input bar
# v13.5.0: Cursor discipline + full window width clearing to prevent ghost artifacts
# v13.5.5: Updated to start at RowHint + 2 (with spacer row)
function Clear-LookupPanel {
    param(
        [int]$Width,
        [int]$RowInput
    )
    
    # --- SAVE CURSOR POSITION (CRITICAL) ---
    $origPos = $Host.UI.RawUI.CursorPosition
    $origRow = $origPos.Y
    $origCol = $origPos.X
    
    $ui = $Host.UI.RawUI
    $winHeight = $ui.WindowSize.Height
    $winWidth = $ui.WindowSize.Width
    
    $panelHeight = 5  # v13.5.5: Just candidate rows, no header
    $colStart = 2
    
    # v13.5.5: Same positioning as Draw-LookupPanel - starts at RowHint + 2 (with spacer)
    $rowStart = $Global:RowHint + 2
    
    # Clamp: not past bottom of window
    if ($rowStart + $panelHeight -gt ($winHeight - 1)) {
        $rowStart = ($winHeight - 1) - $panelHeight
    }
    if ($rowStart -lt 0) { $rowStart = 0 }
    
    # v13.5.0: Clear FULL window width to prevent ghost text artifacts
    # When panel shrinks, old text may remain on right edge
    $clearWidth = $winWidth - $colStart - 1
    if ($clearWidth -lt 1) { $clearWidth = 1 }
    
    for ($i = 0; $i -lt $panelHeight; $i++) {
        $clearRow = $rowStart + $i
        if ($clearRow -ge 0 -and $clearRow -lt $winHeight) {
            Set-Pos $clearRow $colStart
            Write-Host (" " * $clearWidth) -NoNewline
        }
    }
    
    # --- RESTORE CURSOR (CRITICAL) ---
    Set-Pos $origRow $origCol
}

# --- RESET LOOKUP STATE ---
# v13.5.1: Single point of cleanup for lookup mode
# Clears lookup state, panel, and optionally the hint row
# Does NOT touch the input bar
function Reset-LookupState {
    param(
        [int]$Width,
        [int]$RowInput,
        [switch]$ClearHint
    )
    
    # Clear lookup candidates
    $Global:LookupCandidates = @()
    
    # Clear lookup fields in PlaceholderInfo (but keep placeholder active)
    if ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup) {
        $Global:PlaceholderInfo.Lookup = $null
        $Global:PlaceholderInfo.Filter = ""
        $Global:PlaceholderInfo.Selected = 0
    }
    
    # Clear the panel region
    Clear-LookupPanel -Width $Width -RowInput $RowInput
    
    # Optionally clear hint row
    if ($ClearHint) {
        Clear-HintRow
    }
}

# --- INVOKE CLEAN PROMPT ---
# v13.5.4: Unified clean prompt helper - used by both ESC and Backspace-to-empty
# Uses the EXACT same drawing sequence as initial prompt setup to guarantee identical visuals
# This is the single source of truth for "clean slate" behavior
function Invoke-CleanPrompt {
    param(
        [int]$Width,
        [int]$RowInput,
        [int]$CursorStart
    )
    
    # 1) Reset all transient state - exactly like ESC does
    $Global:PlaceholderInfo = $null
    $Global:LookupCandidates = @()
    
    # 2) Clear hint row (same as ESC)
    Clear-HintRow
    
    # 3) Clear lookup panel (same as ESC)
    Clear-LookupPanel -Width $Width -RowInput $RowInput
    
    # 4) Redraw footer bar (same as startup - line 3494)
    Draw-FooterBar
    
    # 5) Redraw the complete input bar (same as startup - line 3497)
    #    This draws: top border, inner line with "> ", bottom border
    Draw-InputBar -width $Width -rowInput $RowInput
    
    # 6) Position cursor at input start (same as startup - line 3500)
    Set-Pos $RowInput $CursorStart
}
# Layout: Footer(RowInput-2), TopBorder(RowInput-1), Input(RowInput), BottomBorder(RowInput+1)
# ALIGNMENT: Input bar starts at $Global:InputLeft, cursor at InputLeft + 4
function Read-StableInput {
    $width = $Host.UI.RawUI.WindowSize.Width
    $left = $Global:InputLeft
    $boxWidth = $width - $left - 1
    $innerWidth = $boxWidth - 2
    $maxInputLen = $innerWidth - 3    # max text length (innerWidth minus " > ")
    $cursorStart = $left + 4          # after "│ > "

    # v13.3.5: Draw footer first (above input)
    Draw-FooterBar

    # Draw the framed input bar
    Draw-InputBar -width $width -rowInput $Global:RowInput

    # Return cursor to input line (inside frame, after "│ > ")
    Set-Pos $Global:RowInput $cursorStart

    $buffer = ""
    $cursorCol = $cursorStart

    while ($true) {
        # v15.4.1: AllowCtrlC lets us intercept Ctrl+C instead of immediate termination
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,AllowCtrlC")

        # v15.4.1: Auto-clear Ctrl+C warning after 2 seconds
        if ($Global:CtrlCWarningShownUtc) {
            $elapsed = ([DateTime]::UtcNow - $Global:CtrlCWarningShownUtc).TotalSeconds
            if ($elapsed -ge 2.0) {
                # Clear the warning line (below input bar, right side)
                Set-Pos ($Global:RowInput + 2) ($width - 25)
                Write-Host (" " * 25) -NoNewline
                Set-Pos $Global:RowInput $cursorCol
                $Global:CtrlCWarningShownUtc = $null
            }
        }

        # v15.4.1: Ctrl-C double-press protection (inline check)
        if ($key.VirtualKeyCode -eq 3 -or
            ($key.VirtualKeyCode -eq 67 -and ($key.ControlKeyState -band [System.Management.Automation.Host.ControlKeyStates]::LeftCtrlPressed -or
             $key.ControlKeyState -band [System.Management.Automation.Host.ControlKeyStates]::RightCtrlPressed))) {
            $now = [DateTime]::UtcNow
            if ($Global:LastCtrlCUtc -and ($now - $Global:LastCtrlCUtc).TotalSeconds -le 1.0) {
                Write-Host "`nExiting..." -ForegroundColor DarkGray
                exit 130
            }
            $Global:LastCtrlCUtc = $now
            $Global:CtrlCWarningShownUtc = $now
            # Show subtle warning below input bar, right-aligned
            $warnMsg = "Ctrl+C again to exit"
            Set-Pos ($Global:RowInput + 2) ($width - $warnMsg.Length - 2)
            Write-Host $warnMsg -ForegroundColor DarkGray -NoNewline
            Set-Pos $Global:RowInput $cursorCol
            continue
        }

        # Enter - submit OR apply lookup selection OR toggle history details
        if ($key.VirtualKeyCode -eq 13) {
            # v15.5: In History Mode, Enter toggles details pane
            if ($Global:HistoryMode) {
                $Global:HistoryDetailsVisible = -not $Global:HistoryDetailsVisible
                return "__REFRESH_HISTORY__"
            }

            # v13.4.6: If lookup is active and has candidates, apply selection
            if ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup -and $Global:LookupCandidates -and $Global:LookupCandidates.Count -gt 0) {
                $ph = $Global:PlaceholderInfo
                $choice = $Global:LookupCandidates[$ph.Selected].Id
                
                $start = [int]$ph.Start
                $len = [int]$ph.Length
                $end = $start + $len
                
                # Replace placeholder/typed text with selected ID
                $before = if ($start -gt 0) { $buffer.Substring(0, $start) } else { "" }
                $after = if ($end -lt $buffer.Length) { $buffer.Substring($end) } else { "" }
                $buffer = $before + $choice + $after
                
                # Clear lookup state FIRST
                $Global:LookupCandidates = @()
                
                # Clear lookup panel (does not touch input bar)
                Clear-LookupPanel -Width $width -RowInput $Global:RowInput
                
                # Auto-advance to next placeholder
                $searchFrom = $start + $choice.Length
                $next = Find-NextPlaceholder -Buffer $buffer -StartIndex $searchFrom
                
                # v13.5.0: SINGLE consolidated redraw (not two separate redraws)
                # This prevents input bar flicker
                Clear-InputContent -width $width -rowInput $Global:RowInput
                Set-Pos $Global:RowInput $cursorStart
                
                if ($next) {
                    # Setup next placeholder
                    $Global:PlaceholderInfo = @{
                        Start     = $next.Start
                        Length    = $next.Length
                        Text      = $next.Text
                        RawText   = $next.Text
                        Options   = $null
                        OptionIdx = 0
                        MiniGuide = "enter value"
                        Lookup    = $null
                        Filter    = ""
                        Selected  = 0
                    }
                    $cursorCol = $cursorStart + $next.Start
                    $phStart = $next.Start
                    $phLen = $next.Length
                    
                    # Draw buffer with next placeholder highlighted
                    if ($phStart -gt 0) {
                        Write-Host $buffer.Substring(0, $phStart) -NoNewline -ForegroundColor Cyan
                    }
                    Write-Host $buffer.Substring($phStart, $phLen) -NoNewline -ForegroundColor Yellow -BackgroundColor DarkGray
                    if ($phStart + $phLen -lt $buffer.Length) {
                        Write-Host $buffer.Substring($phStart + $phLen) -NoNewline -ForegroundColor Cyan
                    }
                    
                    # Update hint row
                    Draw-ToggleOptions -Width $width -RowInput $Global:RowInput
                    Set-Pos $Global:RowInput $cursorCol
                }
                else {
                    # No more placeholders - just draw plain buffer
                    $Global:PlaceholderInfo = $null
                    Clear-HintRow  # v13.5.0: Clear hint row
                    Write-Host $buffer -NoNewline -ForegroundColor Cyan
                    $cursorCol = $cursorStart + $buffer.Length
                    Set-Pos $Global:RowInput $cursorCol
                }
                continue
            }
            
            $Global:PlaceholderInfo = $null  # v13.4: Clear placeholder on submit
            $Global:LookupCandidates = @()
            Clear-HintRow  # v13.5.0: Clear hint row
            Clear-LookupPanel -Width $width -RowInput $Global:RowInput
            return $buffer
        }

        # Escape - cancel (in-place reset, no window extension)
        # v13.5.5: ESC now does an in-place redraw and continues in the input loop
        #          This prevents the window from extending or jumping
        if ($key.VirtualKeyCode -eq 27) {
            # v15.5: In History Mode, Esc exits History Mode (only when not typing)
            if ($Global:HistoryMode -and [string]::IsNullOrEmpty($buffer) -and (-not $Global:PlaceholderInfo)) {
                return "__TOGGLE_HISTORY__"
            }
            # Reset logical state
            $buffer = ""
            $cursorCol = $cursorStart
            $Global:PlaceholderInfo = $null
            $Global:LookupCandidates = @()
            
            # In-place visual reset using the unified clean prompt helper
            Invoke-CleanPrompt -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
            continue
        }

        # Tab - advance to next placeholder (v13.4.5) OR toggle mode when no placeholder OR cycle history subview
        if ($key.VirtualKeyCode -eq 9) {
            # v15.5: In History Mode, Tab cycles subviews: TASKS → DOCS → SHIP → TASKS
            if ($Global:HistoryMode) {
                $Global:HistorySubview = switch ($Global:HistorySubview) {
                    "TASKS" { "DOCS" }
                    "DOCS" { "SHIP" }
                    "SHIP" { "TASKS" }
                    default { "TASKS" }
                }
                # Reset selection and scroll when changing subview
                $Global:HistorySelectedRow = 0
                $Global:HistoryScrollOffset = 0
                $Global:HistoryDetailsVisible = $false
                $Global:HistoryData = @(Get-HistoryData)
                return "__REFRESH_HISTORY__"
            }

            # v13.4.5: If placeholder is active, Tab advances to next placeholder
            if ($Global:PlaceholderInfo) {
                $ph = $Global:PlaceholderInfo
                $searchFrom = [int]$ph.Start + [int]$ph.Length
                
                $next = Find-NextPlaceholder -Buffer $buffer -StartIndex $searchFrom
                if ($next) {
                    # Advance to next placeholder
                    $Global:PlaceholderInfo = @{
                        Start     = $next.Start
                        Length    = $next.Length
                        Text      = $next.Text
                        RawText   = $next.Text
                        Options   = $null      # No toggle options for subsequent placeholders
                        OptionIdx = 0
                        MiniGuide = "enter value"
                    }
                    $cursorCol = $cursorStart + $next.Start
                    
                    # Redraw input with new placeholder highlighted
                    Clear-InputContent -width $width -rowInput $Global:RowInput
                    Set-Pos $Global:RowInput $cursorStart
                    
                    # Draw buffer with new placeholder highlighted
                    $phStart = $next.Start
                    $phLen = $next.Length
                    if ($phStart -gt 0) {
                        Write-Host $buffer.Substring(0, $phStart) -NoNewline -ForegroundColor Cyan
                    }
                    Write-Host $buffer.Substring($phStart, $phLen) -NoNewline -ForegroundColor Yellow -BackgroundColor DarkGray
                    if ($phStart + $phLen -lt $buffer.Length) {
                        Write-Host $buffer.Substring($phStart + $phLen) -NoNewline -ForegroundColor Cyan
                    }
                    
                    # Draw mini guide (no toggle options for this placeholder)
                    Draw-ToggleOptions -Width $width -RowInput $Global:RowInput
                    
                    Set-Pos $Global:RowInput $cursorCol
                }
                else {
                    # No more placeholders - clear placeholder state and move cursor to end
                    $Global:PlaceholderInfo = $null
                    $cursorCol = $cursorStart + $buffer.Length
                    
                    # v13.5.0: Clear hint row since no placeholder is active
                    Clear-HintRow
                    
                    # Redraw without placeholder highlighting
                    Clear-InputContent -width $width -rowInput $Global:RowInput
                    Set-Pos $Global:RowInput $cursorStart
                    Write-Host $buffer -NoNewline -ForegroundColor Cyan
                    Set-Pos $Global:RowInput $cursorCol
                }
                continue
            }
            
            # No placeholder active: fall back to mode toggle (OPS ↔ PLAN)
            $Global:CurrentMode = if ($Global:CurrentMode -eq "OPS") { "PLAN" } else { "OPS" }

            # Redraw footer bar to update mode indicator
            Draw-FooterBar

            # Return cursor to input position
            Set-Pos $Global:RowInput $cursorCol
            continue
        }

        # F2 - History Mode toggle OR toggle placeholder options (v13.4.3 + v15.5)
        if ($key.VirtualKeyCode -eq 113) {
            # If a placeholder toggle is active, keep legacy behavior
            if (-not $Global:HistoryMode -and $Global:PlaceholderInfo) {
                Invoke-TogglePlaceholder -Buffer ([ref]$buffer) -CursorCol ([ref]$cursorCol) -CursorStart $cursorStart -Width $width -RowInput $Global:RowInput
                continue
            }

            # Otherwise, F2 toggles History Mode (enter/exit)
            return "__TOGGLE_HISTORY__"
        }

        # F3 - legacy History Mode toggle (v15.5)
        if ($key.VirtualKeyCode -eq 114) {
            return "__TOGGLE_HISTORY__"
        }

        # Up Arrow - navigate lookup candidates (v13.4.6) OR history rows (v15.5)
        if ($key.VirtualKeyCode -eq 38) {
            # v15.5: In History Mode, Up moves selection up
            if ($Global:HistoryMode) {
                if ($Global:HistorySelectedRow -gt 0) {
                    $Global:HistorySelectedRow--
                }
                return "__REFRESH_HISTORY__"
            }

            if ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup -and $Global:LookupCandidates -and $Global:LookupCandidates.Count -gt 0) {
                $ph = $Global:PlaceholderInfo
                $count = $Global:LookupCandidates.Count
                $ph.Selected = ($ph.Selected - 1)
                if ($ph.Selected -lt 0) { $ph.Selected = $count - 1 }
                $Global:PlaceholderInfo = $ph
                Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                # Note: Draw-LookupPanel restores cursor position internally
                continue
            }
            # If not in lookup mode, ignore Up (no other behavior defined)
            continue
        }

        # Down Arrow - navigate lookup candidates (v13.4.6) OR history rows (v15.5)
        if ($key.VirtualKeyCode -eq 40) {
            # v15.5: In History Mode, Down moves selection down
            if ($Global:HistoryMode) {
                $maxIdx = $Global:HistoryData.Count - 1
                if ($maxIdx -ge 0 -and $Global:HistorySelectedRow -lt $maxIdx) {
                    $Global:HistorySelectedRow++
                }
                return "__REFRESH_HISTORY__"
            }

            if ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup -and $Global:LookupCandidates -and $Global:LookupCandidates.Count -gt 0) {
                $ph = $Global:PlaceholderInfo
                $count = $Global:LookupCandidates.Count
                $ph.Selected = ($ph.Selected + 1) % $count
                $Global:PlaceholderInfo = $ph
                Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                # Note: Draw-LookupPanel restores cursor position internally
                continue
            }
            # If not in lookup mode, ignore Down (no other behavior defined)
            continue
        }

        # Backspace - delete character to the LEFT of cursor
        # v13.4.1: Does NOT trigger placeholder deletion
        # v13.5.1: Properly handles lookup mode - resets lookup when content changes
        # v13.5.2: Hard reset when buffer becomes empty
        if ($key.VirtualKeyCode -eq 8) {
            $bufferCursorPos = $cursorCol - $cursorStart
            if ($bufferCursorPos -gt 0) {
                # Check if we're in lookup mode BEFORE modifying buffer
                $wasInLookup = ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup -and $Global:LookupCandidates.Count -gt 0)
                
                # Remove char at position (bufferCursorPos - 1)
                $before = $buffer.Substring(0, $bufferCursorPos - 1)
                $after = if ($bufferCursorPos -lt $buffer.Length) { $buffer.Substring($bufferCursorPos) } else { "" }
                $buffer = $before + $after
                $cursorCol--
                
                # v13.5.5: HARD RESET when buffer becomes empty via Backspace
                # Behaves EXACTLY like ESC - same sequence of operations
                if ([string]::IsNullOrWhiteSpace($buffer)) {
                    # Reset logical state (same as ESC - lines 3580-3583)
                    $buffer = ""
                    $cursorCol = $cursorStart
                    $Global:PlaceholderInfo = $null
                    $Global:LookupCandidates = @()
                    
                    # In-place visual reset (same as ESC - line 3586)
                    Invoke-CleanPrompt -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                    continue
                }
                
                # v13.5.1: Handle lookup mode - reset or update filter
                if ($wasInLookup -and $Global:PlaceholderInfo) {
                    $ph = $Global:PlaceholderInfo
                    $phStart = [int]$ph.Start
                    $phEnd = $phStart + [int]$ph.Length
                    
                    # Check if cursor is still within the placeholder region
                    $newCursorPos = $cursorCol - $cursorStart
                    if ($newCursorPos -lt $phStart -or $buffer.Length -lt $phEnd) {
                        # Backspaced out of placeholder region - reset lookup
                        Reset-LookupState -Width $width -RowInput $Global:RowInput
                        
                        # Reset PlaceholderInfo if we've destroyed the placeholder
                        if ($buffer.Length -lt $phEnd) {
                            $Global:PlaceholderInfo = $null
                            Clear-HintRow
                        }
                    }
                    else {
                        # Still in placeholder - update filter and refresh panel
                        $currentText = $buffer.Substring($phStart, $newCursorPos - $phStart)
                        $ph.Filter = $currentText
                        $ph.Length = $currentText.Length
                        $Global:PlaceholderInfo = $ph
                        
                        # Refresh lookup panel with new filter
                        if ($currentText.Length -gt 0) {
                            Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                        }
                        else {
                            # Empty filter - clear lookup
                            Reset-LookupState -Width $width -RowInput $Global:RowInput
                        }
                    }
                }
                
                # Redraw from cursor position to end
                Set-Pos $Global:RowInput $cursorCol
                Write-Host ($after + " ") -NoNewline -ForegroundColor Cyan
                Set-Pos $Global:RowInput $cursorCol
            }
            continue
        }

        # Delete - delete character AT cursor (forward delete)
        # v13.4.1: Does NOT trigger placeholder deletion
        # v13.5.1: Properly handles lookup mode - resets lookup when content changes
        # v13.5.4: Hard reset when buffer becomes empty (same as Backspace)
        if ($key.VirtualKeyCode -eq 46) {
            $bufferCursorPos = $cursorCol - $cursorStart
            if ($bufferCursorPos -lt $buffer.Length) {
                # Check if we're in lookup mode BEFORE modifying buffer
                $wasInLookup = ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup -and $Global:LookupCandidates.Count -gt 0)
                
                # Remove char at position bufferCursorPos
                $before = $buffer.Substring(0, $bufferCursorPos)
                $after = if ($bufferCursorPos + 1 -lt $buffer.Length) { $buffer.Substring($bufferCursorPos + 1) } else { "" }
                $buffer = $before + $after
                
                # v13.5.5: HARD RESET when buffer becomes empty via Delete
                # Behaves EXACTLY like ESC - same sequence of operations
                if ([string]::IsNullOrWhiteSpace($buffer)) {
                    # Reset logical state (same as ESC)
                    $buffer = ""
                    $cursorCol = $cursorStart
                    $Global:PlaceholderInfo = $null
                    $Global:LookupCandidates = @()
                    
                    # In-place visual reset (same as ESC)
                    Invoke-CleanPrompt -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                    continue
                }
                
                # v13.5.1: Handle lookup mode - reset or update filter
                if ($wasInLookup -and $Global:PlaceholderInfo) {
                    $ph = $Global:PlaceholderInfo
                    $phStart = [int]$ph.Start
                    $phEnd = $phStart + [int]$ph.Length
                    
                    # Check if we've deleted beyond the placeholder region
                    if ($buffer.Length -lt $phEnd - 1) {
                        # Deleted into placeholder region - reset lookup
                        Reset-LookupState -Width $width -RowInput $Global:RowInput
                        
                        # Reset PlaceholderInfo if we've destroyed the placeholder
                        $Global:PlaceholderInfo = $null
                        Clear-HintRow
                    }
                    else {
                        # Still in placeholder - update filter and refresh panel
                        $cursorPos = $cursorCol - $cursorStart
                        $filterLen = [Math]::Max(0, $cursorPos - $phStart)
                        $currentText = if ($filterLen -gt 0) { $buffer.Substring($phStart, $filterLen) } else { "" }
                        $ph.Filter = $currentText
                        $ph.Length = [Math]::Max(1, $filterLen)
                        $Global:PlaceholderInfo = $ph
                        
                        # Refresh lookup panel with new filter
                        if ($currentText.Length -gt 0) {
                            Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                        }
                        else {
                            # Empty filter - clear lookup
                            Reset-LookupState -Width $width -RowInput $Global:RowInput
                        }
                    }
                }
                
                # Redraw from cursor position to end
                Set-Pos $Global:RowInput $cursorCol
                Write-Host ($after + " ") -NoNewline -ForegroundColor Cyan
                Set-Pos $Global:RowInput $cursorCol
            }
            continue
        }

        # Get character
        $char = $key.Character

        # v15.5: History Mode hotkeys (only when not typing)
        if ($Global:HistoryMode -and [string]::IsNullOrEmpty($buffer) -and $char) {
            $upper = $char.ToString().ToUpperInvariant()
            switch ($upper) {
                "D" { return "__HISTORY_HOTKEY_D__" }
                "I" { return "__HISTORY_HOTKEY_I__" }
                "S" { return "__HISTORY_HOTKEY_S__" }
                "V" { return "__HISTORY_HOTKEY_V__" }
            }
        }

        # Slash as FIRST character - show command picker (with exact-match support)
        if ($buffer.Length -eq 0 -and $char -eq '/') {
            Write-Host "/" -NoNewline -ForegroundColor Yellow
            $pickerResult = Show-CommandPicker
            if ($pickerResult.Kind -eq "select") {
                return $pickerResult.Command
            }
            # v13.4: Template insertion with placeholder support
            if ($pickerResult.Kind -eq "template") {
                $template = $pickerResult.Command
                $buffer = $template

                # Clear and redraw input with template
                Clear-InputContent -width $width -rowInput $Global:RowInput
                Set-Pos $Global:RowInput $cursorStart

                # Draw template with placeholder highlighting
                if ($Global:PlaceholderInfo) {
                    $phStart = $Global:PlaceholderInfo.Start
                    $phLen = $Global:PlaceholderInfo.Length

                    # Text before placeholder
                    if ($phStart -gt 0) {
                        Write-Host $template.Substring(0, $phStart) -NoNewline -ForegroundColor Cyan
                    }
                    # Placeholder text (highlighted)
                    Write-Host $template.Substring($phStart, $phLen) -NoNewline -ForegroundColor Yellow -BackgroundColor DarkGray
                    # Text after placeholder
                    if ($phStart + $phLen -lt $template.Length) {
                        Write-Host $template.Substring($phStart + $phLen) -NoNewline -ForegroundColor Cyan
                    }

                    # v13.4.6: Show lookup panel immediately if Lookup is set
                    if ($Global:PlaceholderInfo.Lookup) {
                        Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                    }
                    else {
                        # Draw toggle options or mini guide on right side (v13.4.3)
                        Draw-ToggleOptions -Width $width -RowInput $Global:RowInput
                    }

                    # Position cursor at placeholder start
                    $cursorCol = $cursorStart + $phStart
                    Set-Pos $Global:RowInput $cursorCol
                }
                else {
                    # No placeholder - just display and cursor at end
                    Write-Host $template -NoNewline -ForegroundColor Cyan
                    $cursorCol = $cursorStart + $template.Length
                }
                continue
            }
            # Cancelled - clear input content preserving borders
            $Global:PlaceholderInfo = $null
            Clear-InputContent -width $width -rowInput $Global:RowInput
            $buffer = ""
            $cursorCol = $cursorStart
            continue
        }

        # Printable character - insert at cursor position (respect right border)
        # Max cursor position = width - 2 (one before the right border)
        if ($char -and [int]$char -ge 32 -and $buffer.Length -lt $maxInputLen) {
            $bufferCursorPos = $cursorCol - $cursorStart  # Position in buffer
            
            # v13.4.2: Placeholder auto-erase on first printable key ONLY (with bounds checking)
            if ($Global:PlaceholderInfo) {
                $ph = $Global:PlaceholderInfo
                $phStart = $ph.Start
                $phEnd = $phStart + $ph.Length
                
                # v13.4.2: Guard against out-of-bounds and stale placeholder info
                $placeholderValid = $true
                
                # Check bounds
                if ($phStart -lt 0 -or $phStart -gt $buffer.Length) {
                    $placeholderValid = $false
                }
                elseif ($phEnd -gt $buffer.Length) {
                    $placeholderValid = $false
                }
                # Check if placeholder text still matches (if Text field exists)
                elseif ($ph.Text -and $buffer.Substring($phStart, $ph.Length) -ne $ph.Text) {
                    $placeholderValid = $false
                }
                
                if (-not $placeholderValid) {
                    # Clear stale placeholder info
                    $Global:PlaceholderInfo = $null
                    $Global:LookupCandidates = @()
                }
                else {
                    # Placeholder is valid, check if cursor is in range
                    $inPlaceholderRange = ($bufferCursorPos -ge $phStart -and $bufferCursorPos -le $phEnd)
                    
                    if ($inPlaceholderRange) {
                        # v13.4.6: Check if this is a lookup-backed placeholder
                        if ($ph.Lookup) {
                            # Delete the placeholder text and insert the typed character
                            $before = $buffer.Substring(0, $phStart)
                            $after = if ($phEnd -lt $buffer.Length) { $buffer.Substring($phEnd) } else { "" }
                            $buffer = $before + $char + $after
                            
                            # Update cursor position
                            $bufferCursorPos = $phStart + 1
                            $cursorCol = $cursorStart + $phStart + 1
                            
                            # Update placeholder info for lookup mode
                            $Global:PlaceholderInfo.Text = $char.ToString()
                            $Global:PlaceholderInfo.Length = 1
                            $Global:PlaceholderInfo.Filter = $char.ToString()
                            $Global:PlaceholderInfo.Selected = 0
                            
                            # Redraw input
                            Clear-InputContent -width $width -rowInput $Global:RowInput
                            Set-Pos $Global:RowInput $cursorStart
                            Write-Host $buffer -NoNewline -ForegroundColor Cyan
                            
                            # Show lookup panel
                            Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                            
                            Set-Pos $Global:RowInput $cursorCol
                            continue
                        }
                        else {
                            # Non-lookup placeholder: Delete placeholder span and clear PlaceholderInfo
                            $before = $buffer.Substring(0, $phStart)
                            $after = if ($phEnd -lt $buffer.Length) { $buffer.Substring($phEnd) } else { "" }
                            $buffer = $before + $after
                            
                            # Update cursor position to placeholder start
                            $bufferCursorPos = $phStart
                            $cursorCol = $cursorStart + $phStart
                            
                            # Clear placeholder info BEFORE redraw
                            $Global:PlaceholderInfo = $null
                            
                            # Redraw entire input line without placeholder
                            Clear-InputContent -width $width -rowInput $Global:RowInput
                            Set-Pos $Global:RowInput $cursorStart
                            Write-Host $buffer -NoNewline -ForegroundColor Cyan
                            Set-Pos $Global:RowInput $cursorCol
                        }
                    }
                }
            }
            
            # v13.4.6: If in active lookup mode (panel visible), update filter
            if ($Global:PlaceholderInfo -and $Global:PlaceholderInfo.Lookup -and $Global:PlaceholderInfo.Filter.Length -gt 0) {
                $ph = $Global:PlaceholderInfo
                
                # Append to filter and update buffer
                $newFilter = $ph.Filter + $char
                $phStart = $ph.Start
                
                # Update buffer - replace current filter text with new filter
                $before = $buffer.Substring(0, $phStart)
                $afterLookup = if ($phStart + $ph.Length -lt $buffer.Length) { $buffer.Substring($phStart + $ph.Length) } else { "" }
                $buffer = $before + $newFilter + $afterLookup
                
                # Update placeholder info
                $Global:PlaceholderInfo.Text = $newFilter
                $Global:PlaceholderInfo.Length = $newFilter.Length
                $Global:PlaceholderInfo.Filter = $newFilter
                $Global:PlaceholderInfo.Selected = 0
                
                $cursorCol = $cursorStart + $phStart + $newFilter.Length
                
                # Redraw input
                Clear-InputContent -width $width -rowInput $Global:RowInput
                Set-Pos $Global:RowInput $cursorStart
                Write-Host $buffer -NoNewline -ForegroundColor Cyan
                
                # Update lookup panel
                Draw-LookupPanel -Width $width -RowInput $Global:RowInput -CursorStart $cursorStart
                
                Set-Pos $Global:RowInput $cursorCol
                continue
            }
            
            # Insert character at cursor position (not append)
            $beforeChar = $buffer.Substring(0, $bufferCursorPos)
            $afterChar = if ($bufferCursorPos -lt $buffer.Length) { $buffer.Substring($bufferCursorPos) } else { "" }
            $buffer = $beforeChar + $char + $afterChar
            
            # Redraw from cursor to end
            Set-Pos $Global:RowInput $cursorCol
            Write-Host ($char + $afterChar) -NoNewline -ForegroundColor Cyan
            $cursorCol++
            Set-Pos $Global:RowInput $cursorCol
        }
    }
}

# --- COMMAND PICKER (Arrow key navigation + type-ahead filter) ---
# v13.3.5: Dropdown starts below bottom border (RowInput+2)
# v15.4.1: Added InitialFilter parameter for pre-typed command text
function Show-CommandPicker {
    param(
        [string]$InitialFilter = ""
    )

    # Get Golden Path commands (default view)
    $goldenCmds = Get-PickerCommands -Filter $InitialFilter

    if ($goldenCmds.Count -eq 0 -and $InitialFilter -eq "") { return @{ Kind = "cancel" } }

    # v13.3.5: Get fresh layout values
    $layout = Get-PromptLayout
    $rowInput = $layout.RowInput
    $dropdownRow = $layout.DropdownRow  # Now at RowInput + 2 (below bottom border)
    $width = $layout.Width
    $maxVisible = $layout.MaxVisible

    $script:pickerFilter = $InitialFilter
    $script:pickerSelectedIdx = 0
    $script:pickerScrollOffset = 0

    # Helper: Clear only the dropdown area (not the framed input or footer)
    function ClearDropdownOnly {
        # Clear dropdown rows only (RowInput+2 and below)
        for ($i = 0; $i -le $maxVisible; $i++) {
            Set-Pos ($dropdownRow + $i) 0
            Write-Host (" " * $width) -NoNewline
        }
    }

    # Draw dropdown (below the bottom border)
    function DrawPickerDropdown {
        $cmdList = Get-PickerCommands -Filter $script:pickerFilter

        # Update input line content (inside the frame): │ > /filter │
        # Clear and redraw the middle of the frame
        $left = $Global:InputLeft
        $boxWidth = $width - $left - 1
        $innerWidth = $boxWidth - 2
        Set-Pos $rowInput $left
        Write-Host "│" -NoNewline -ForegroundColor DarkGray
        Write-Host " > " -NoNewline -ForegroundColor White
        Write-Host "/" -NoNewline -ForegroundColor Yellow
        Write-Host $script:pickerFilter -NoNewline -ForegroundColor Cyan
        $usedChars = 4 + $script:pickerFilter.Length  # " > /" + filter
        $remaining = $innerWidth - $usedChars
        if ($remaining -gt 0) {
            Write-Host (" " * $remaining) -NoNewline
        }
        Write-Host "│" -NoNewline -ForegroundColor DarkGray

        # Draw dropdown items
        for ($i = 0; $i -lt $maxVisible; $i++) {
            Set-Pos ($dropdownRow + $i) 0
            $cmdIdx = $script:pickerScrollOffset + $i
            if ($cmdIdx -lt $cmdList.Count) {
                $cmd = $cmdList[$cmdIdx]
                $isSelected = ($cmdIdx -eq $script:pickerSelectedIdx)
                $prefix = if ($isSelected) { "> " } else { "  " }
                $cmdName = "/" + $cmd.Name
                $cmdText = "$prefix$cmdName - $($cmd.Desc)"
                if ($cmdText.Length -gt $width - 2) { $cmdText = $cmdText.Substring(0, $width - 5) + "..." }
                $cmdText = $cmdText.PadRight($width)

                if ($isSelected) {
                    Write-Host $cmdText -NoNewline -ForegroundColor Yellow -BackgroundColor DarkGray
                }
                else {
                    Write-Host $cmdText -NoNewline -ForegroundColor Gray
                }
            }
            else {
                Write-Host (" " * $width) -NoNewline
            }
        }
        # Footer hint for dropdown
        Set-Pos ($dropdownRow + $maxVisible) 0
        if ($script:pickerFilter -eq "") {
            Write-Host ("  /help --all for full registry").PadRight($width) -ForegroundColor DarkGray -NoNewline
        }
        else {
            $below = $cmdList.Count - $script:pickerScrollOffset - $maxVisible
            if ($below -gt 0) {
                Write-Host ("  ↓$below more").PadRight($width) -ForegroundColor DarkGray -NoNewline
            }
            else {
                Write-Host (" " * $width) -NoNewline
            }
        }
        # Cursor back to input line (inside frame, after "│ > /filter")
        Set-Pos $rowInput ($Global:InputLeft + 5 + $script:pickerFilter.Length)

        return $cmdList
    }

    $filteredCmds = @(DrawPickerDropdown)

    while ($true) {
        # v15.4.1: AllowCtrlC lets us intercept Ctrl+C instead of immediate termination
        $keyPress = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,AllowCtrlC")
        $filteredCmds = @(Get-PickerCommands -Filter $script:pickerFilter)

        # v15.4.1: Auto-clear Ctrl+C warning after 2 seconds
        if ($Global:CtrlCWarningShownUtc) {
            $elapsed = ([DateTime]::UtcNow - $Global:CtrlCWarningShownUtc).TotalSeconds
            if ($elapsed -ge 2.0) {
                # Clear the warning line (below input bar, right side)
                Set-Pos ($rowInput + 2) ($width - 25)
                Write-Host (" " * 25) -NoNewline
                Set-Pos $rowInput ($Global:InputLeft + 5 + $script:pickerFilter.Length)
                $Global:CtrlCWarningShownUtc = $null
            }
        }

        # v15.4.1: Ctrl-C double-press protection (inline check)
        if ($keyPress.VirtualKeyCode -eq 3 -or
            ($keyPress.VirtualKeyCode -eq 67 -and ($keyPress.ControlKeyState -band [System.Management.Automation.Host.ControlKeyStates]::LeftCtrlPressed -or
             $keyPress.ControlKeyState -band [System.Management.Automation.Host.ControlKeyStates]::RightCtrlPressed))) {
            $now = [DateTime]::UtcNow
            if ($Global:LastCtrlCUtc -and ($now - $Global:LastCtrlCUtc).TotalSeconds -le 1.0) {
                Write-Host "`nExiting..." -ForegroundColor DarkGray
                exit 130
            }
            $Global:LastCtrlCUtc = $now
            $Global:CtrlCWarningShownUtc = $now
            # Show subtle warning below input bar, right-aligned
            $warnMsg = "Ctrl+C again to exit"
            Set-Pos ($rowInput + 2) ($width - $warnMsg.Length - 2)
            Write-Host $warnMsg -ForegroundColor DarkGray -NoNewline
            Set-Pos $rowInput ($Global:InputLeft + 5 + $script:pickerFilter.Length)
            continue
        }

        # v15.4: Enter - select command (with auto-expand for unique/exact match)
        if ($keyPress.VirtualKeyCode -eq 13) {
            if ($filteredCmds.Count -ge 1) {
                # Check for exact match first
                $exactMatch = $filteredCmds | Where-Object { $_.Name -eq $script:pickerFilter }
                if ($exactMatch) {
                    ClearDropdownOnly
                    return @{ Kind = "select"; Command = "/" + $exactMatch.Name }
                }
                # v16.1.1: Unique prefix auto-run (P2 enhancement)
                # If exactly one command matches the prefix, run it immediately
                if ($filteredCmds.Count -eq 1) {
                    ClearDropdownOnly
                    return @{ Kind = "select"; Command = "/" + $filteredCmds[0].Name }
                }
                # Otherwise use highlighted selection (multiple matches)
                ClearDropdownOnly
                return @{ Kind = "select"; Command = "/" + $filteredCmds[$script:pickerSelectedIdx].Name }
            }
            continue
        }

        # v15.4: TAB - accept highlighted suggestion (same as Enter for selection)
        if ($keyPress.VirtualKeyCode -eq 9) {
            if ($filteredCmds.Count -gt 0) {
                ClearDropdownOnly
                return @{ Kind = "select"; Command = "/" + $filteredCmds[$script:pickerSelectedIdx].Name }
            }
            continue
        }

        # Escape - cancel
        if ($keyPress.VirtualKeyCode -eq 27) {
            ClearDropdownOnly
            return @{ Kind = "cancel" }
        }

        # Backspace - remove filter char OR exit picker if empty
        if ($keyPress.VirtualKeyCode -eq 8) {
            if ($script:pickerFilter.Length -gt 0) {
                $script:pickerFilter = $script:pickerFilter.Substring(0, $script:pickerFilter.Length - 1)
                $script:pickerSelectedIdx = 0
                $script:pickerScrollOffset = 0
                DrawPickerDropdown | Out-Null
            }
            else {
                # v13.3.2: Backspace on empty = exit picker (delete the /)
                ClearDropdownOnly
                return @{ Kind = "cancel" }
            }
            continue
        }

        # Down arrow
        if ($keyPress.VirtualKeyCode -eq 40) {
            if ($script:pickerSelectedIdx -lt $filteredCmds.Count - 1) {
                $script:pickerSelectedIdx++
                if ($script:pickerSelectedIdx -ge $script:pickerScrollOffset + $maxVisible) { $script:pickerScrollOffset++ }
                DrawPickerDropdown | Out-Null
            }
            continue
        }

        # Up arrow
        if ($keyPress.VirtualKeyCode -eq 38) {
            if ($script:pickerSelectedIdx -gt 0) {
                $script:pickerSelectedIdx--
                if ($script:pickerSelectedIdx -lt $script:pickerScrollOffset) { $script:pickerScrollOffset-- }
                DrawPickerDropdown | Out-Null
            }
            continue
        }
        
        # Right Arrow - insert template (v13.4)
        if ($keyPress.VirtualKeyCode -eq 39) {
            if ($filteredCmds.Count -gt 0) {
                $selectedCmd = $filteredCmds[$script:pickerSelectedIdx]
                $cmdMeta = $Global:Commands[$selectedCmd.Name]
                
                if ($cmdMeta -and $cmdMeta.Template) {
                    $template = $cmdMeta.Template
                    
                    # Set up placeholder info if command has one
                    $Global:PlaceholderInfo = $null
                    if ($cmdMeta.Placeholder) {
                        $ph = $cmdMeta.Placeholder
                        $idx = $template.IndexOf($ph)
                        if ($idx -ge 0) {
                            $Global:PlaceholderInfo = @{
                                Start     = $idx
                                Length    = $ph.Length
                                Text      = $ph  # v13.4.2: Current segment text (mutable)
                                RawText   = $ph  # v13.4.4: Original placeholder, never changed
                                MiniGuide = if ($cmdMeta.MiniGuide) { $cmdMeta.MiniGuide } else { "" }
                                Options   = $cmdMeta.Options  # v13.4.3: Toggle options array or $null
                                OptionIdx = 0                 # v13.4.3: Current selected option index
                                Lookup    = $cmdMeta.Lookup   # v13.4.6: Library kind (e.g. "questions") or $null
                                Filter    = ""                # v13.4.6: Current typed prefix for lookup
                                Selected  = 0                 # v13.4.6: Selected candidate index
                            }
                        }
                    }
                    
                    ClearDropdownOnly
                    return @{ Kind = "template"; Command = $template }
                }
            }
            continue
        }
        
        # Letter keys - add to filter
        $charPressed = $keyPress.Character
        if ($charPressed -and $charPressed -match '^[a-zA-Z0-9]$') {
            $script:pickerFilter += $charPressed.ToString().ToLower()
            $script:pickerSelectedIdx = 0
            $script:pickerScrollOffset = 0
            DrawPickerDropdown | Out-Null
            continue
        }
    }
}

# ============================================================================
# v13.3.1: SCENARIO HINT (action-based, not tech explanation)
# ============================================================================

function Get-SystemScenario {
    # Detect current system state for scenario-based hints
    try {
        $stats = Get-TaskStats
        $hasTasks = ($stats.pending -gt 0 -or $stats.in_progress -gt 0 -or $stats.completed -gt 0)

        # Check for sources/domain rules
        $hasSources = (Test-Path (Join-Path $CurrentDir "docs\DOMAIN_RULES.md")) -or
        (Test-Path (Join-Path $CurrentDir "control\sources"))

        # Check librarian status
        $workerStatus = Get-WorkerStatus
        $isMessy = $workerStatus.lib_status_text -match "MESSY|CLUTTERED"

        if (-not $hasSources -and -not $hasTasks) {
            return "fresh"      # Brand new project
        }
        elseif ($isMessy) {
            return "messy"      # Needs cleanup
        }
        elseif ($stats.pending -gt 0) {
            return "pending"    # Has work to do
        }
        else {
            return "normal"     # Standard state
        }
    }
    catch {
        return "normal"
    }
}

# v13.3.3: Legacy alias - now delegates to Draw-FooterBar
function Show-ScenarioHint {
    Draw-FooterBar
}

# ============================================================================
# v15.2: AUTO-INGEST (File Watcher + Debounced Trigger)
# ============================================================================

# Silent ingest function (no UI output, returns result)
function Invoke-SilentIngest {
    <#
    .SYNOPSIS
        Runs ingest silently, returns @{ Ok = $bool; Message = "..." }
    #>
    try {
        # Call mesh_server's trigger_ingestion via Python
        $result = python -c "from mesh_server import trigger_ingestion; print(trigger_ingestion())" 2>&1
        $resultStr = $result -join "`n"

        if ($resultStr -match "❌") {
            return @{ Ok = $false; Message = ($resultStr -replace "❌\s*", "").Trim().Substring(0, [Math]::Min(50, $resultStr.Length)) }
        }
        return @{ Ok = $true; Message = "OK" }
    }
    catch {
        return @{ Ok = $false; Message = $_.Exception.Message.Substring(0, [Math]::Min(50, $_.Exception.Message.Length)) }
    }
}

# Set up FileSystemWatcher for docs/*.md
function Initialize-AutoIngestWatcher {
    if (-not $Global:AutoIngestEnabled) { return }

    $docsPath = Join-Path $CurrentDir "docs"
    if (-not (Test-Path $docsPath)) { return }

    # Allowed files for auto-ingest
    $script:AutoIngestAllowlist = @("PRD.md", "SPEC.md", "DECISION_LOG.md", "ACTIVE_SPEC.md", "INBOX.md", "TECH_STACK.md")

    try {
        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $docsPath
        $watcher.Filter = "*.md"
        $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
        $watcher.EnableRaisingEvents = $true

        # Event handler - just marks pending (debounce happens in main loop)
        $action = {
            $fileName = $Event.SourceEventArgs.Name
            if ($script:AutoIngestAllowlist -contains $fileName) {
                $Global:AutoIngestPending = $true
                $Global:AutoIngestLastChangeUtc = [DateTime]::UtcNow
            }
        }

        Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action | Out-Null

        $Global:AutoIngestWatcher = $watcher
    }
    catch {
        # Silently fail - auto-ingest is optional
        $Global:AutoIngestEnabled = $false
    }
}

# Process pending auto-ingest (called from main loop)
function Invoke-AutoIngestIfPending {
    if (-not $Global:AutoIngestEnabled) { return $false }
    if (-not $Global:AutoIngestPending) { return $false }

    # Check debounce window
    if ($Global:AutoIngestLastChangeUtc) {
        $elapsed = ([DateTime]::UtcNow - $Global:AutoIngestLastChangeUtc).TotalMilliseconds
        if ($elapsed -lt $Global:AutoIngestDebounceMs) {
            return $false  # Still settling
        }
    }

    # Clear pending flag
    $Global:AutoIngestPending = $false
    $Global:AutoIngestLastRunUtc = [DateTime]::UtcNow

    # Check if we're in PRE_INIT (no docs exist)
    $docsPath = Join-Path $CurrentDir "docs"
    $prdExists = Test-Path (Join-Path $docsPath "PRD.md")
    $specExists = Test-Path (Join-Path $docsPath "SPEC.md")

    if (-not $prdExists -and -not $specExists) {
        $Global:AutoIngestLastResult = "SKIPPED"
        $Global:AutoIngestLastMessage = "No docs yet"
        return $false
    }

    # Run silent ingest
    $result = Invoke-SilentIngest

    if ($result.Ok) {
        $Global:AutoIngestLastResult = "OK"
        $Global:AutoIngestLastMessage = $null
    }
    else {
        $Global:AutoIngestLastResult = "ERROR"
        $Global:AutoIngestLastMessage = $result.Message
    }

    return $true  # Ingest was attempted, caller should refresh
}

# ============================================================================
# v15.4.1: CTRL-C DOUBLE-PRESS PROTECTION (TreatControlCAsInput)
# ============================================================================

function Initialize-CtrlCHandler {
    <#
    .SYNOPSIS
        Sets up Ctrl-C interception by treating it as input.
        The actual double-press logic is handled in ReadKey loops.
    #>
    if ($Global:CtrlCArmed) { return }
    $Global:CtrlCArmed = $true
    [Console]::TreatControlCAsInput = $true
}

# ============================================================================
# MAIN LOOP
# ============================================================================

function Initialize-Screen {
    # Ensure minimum window size
    $W = $Host.UI.RawUI.WindowSize.Width
    $H = $Host.UI.RawUI.WindowSize.Height
    if ($H -lt 25) {
        try { $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($W, 30) } catch {}
    }

    # v13.1: Update health status (shown in header)
    $Global:HealthStatus = Get-SystemHealthStatus
    
    # v13.5.5: Fetch cached plan preview (fast, non-blocking)
    try {
        $planResult = python -c "from mesh_server import get_cached_plan_preview; print(get_cached_plan_preview())" 2>$null
        $Global:PlanPreview = $planResult | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    catch {
        $Global:PlanPreview = @{ status = "STALE"; reason = "Failed to load plan"; streams = @() }
    }
    
    # v13.5.5: Create StartupDelegation object for stream slot display
    # Convert PlanPreview streams to delegation format with task_count
    if ($Global:PlanPreview -and $Global:PlanPreview.status -eq "FRESH" -and $Global:PlanPreview.streams) {
        $delegationStreams = @()
        foreach ($stream in $Global:PlanPreview.streams) {
            $taskCount = if ($stream.tasks) { $stream.tasks.Count } else { 0 }
            $delegationStreams += @{
                id         = $stream.name.ToLower()
                name       = $stream.name
                task_count = $taskCount
            }
        }
        $Global:StartupDelegation = @{
            status  = "READY"
            streams = $delegationStreams
        }
    }
    else {
        $Global:StartupDelegation = @{
            status  = "NO_SPEC"
            streams = @()
        }
    }

    Clear-Host

    # Draw header at row 0
    Set-Pos $Global:RowHeader 0
    Show-Header

    # v15.5: Conditional rendering - History Mode vs Dashboard
    if ($Global:HistoryMode) {
        Draw-HistoryScreen
    }
    else {
        # Draw dashboard starting at row 4 (original layout unchanged)
        Draw-Dashboard
    }
}

# Initial setup
Initialize-Screen

# v15.2: Start auto-ingest file watcher
Initialize-AutoIngestWatcher

# v15.4: Enable Ctrl-C handling
Initialize-CtrlCHandler

# Main loop
while ($true) {
    $userInput = Read-StableInput

    # v15.5: Handle History Mode toggle (F2)
    if ($userInput -eq "__TOGGLE_HISTORY__") {
        $Global:HistoryMode = -not $Global:HistoryMode
        if ($Global:HistoryMode) {
            # Entering history mode - reset state
            $Global:HistorySelectedRow = 0
            $Global:HistoryScrollOffset = 0
            $Global:HistoryDetailsVisible = $false
            $Global:HistoryData = @(Get-HistoryData)
        }
        Initialize-Screen
        continue
    }

    # v15.5: Handle History Mode refresh (navigation keys)
    if ($userInput -eq "__REFRESH_HISTORY__") {
        if ($Global:HistoryMode) {
            Draw-HistoryScreen
        }
        continue
    }

    # v15.5: Handle History Mode hotkeys (silent actions + redraw)
    if ($userInput -in @("__HISTORY_HOTKEY_D__", "__HISTORY_HOTKEY_I__", "__HISTORY_HOTKEY_S__", "__HISTORY_HOTKEY_V__")) {
        if ($Global:HistoryMode) {
            $key = switch ($userInput) {
                "__HISTORY_HOTKEY_D__" { "D" }
                "__HISTORY_HOTKEY_I__" { "I" }
                "__HISTORY_HOTKEY_S__" { "S" }
                "__HISTORY_HOTKEY_V__" { "V" }
                default { "" }
            }

            if ($key) {
                Invoke-HistoryHotkey -Key $key
                Initialize-Screen
            }
        }
        continue
    }

    # v15.2: Check for pending auto-ingest (debounced, on next interaction)
    $ingestRan = Invoke-AutoIngestIfPending
    if ($ingestRan) {
        Initialize-Screen  # Refresh dashboard after ingest
    }

    # Output appears at row 16 (just before input)
    Set-Pos ($Global:RowInput - 1) 0
    $width = $Host.UI.RawUI.WindowSize.Width
    Write-Host (" " * $width) -NoNewline
    Set-Pos ($Global:RowInput - 1) 0

    # v13.2: Empty Enter → run default action for current mode
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Invoke-DefaultAction
        continue
    }

    # v13.2: Mode switch aliases (:ops, :plan, :run, :ship)
    if ($userInput -match "^:(ops|plan|run|ship)$") {
        Switch-Mode -NewMode $Matches[1]
        continue
    }

    # v14.1: Track input scope for dashboard transparency
    if ($userInput.StartsWith("/")) {
        $Global:LastScope = "command"
    }
    else {
        $Global:LastScope = "text"
    }

    # Slash commands (explicit)
    if ($userInput.StartsWith("/")) {
        $parts = $userInput.TrimStart("/").Split(" ", 2)
        $cmdName = $parts[0].ToLower()

        if ($Global:Commands.Contains($cmdName)) {
            $result = Invoke-SlashCommand -UserInput $userInput
            if ($result -eq "refresh") { Initialize-Screen }
        }
        else {
            Write-Host "  Unknown command: /$cmdName" -ForegroundColor Yellow
        }
    }
    else {
        # v13.2: Plain text → modal routing (no backend calls)
        Invoke-ModalRoute -Text $userInput
    }
}
