# C:\Tools\atomic-mesh\control_panel.ps1
# ATOMIC MESH COMMANDER v7.1 - Self-Correcting Execution Engine
# FEATURES: Auditor integration, Mode toggle, Continue command, Security Tripwire

param()

$CurrentDir = (Get-Location).Path
$DB_FILE = "$CurrentDir\mesh.db"
$LogDir = "$CurrentDir\logs"
$DocsDir = "$CurrentDir\docs"
$MilestoneFile = "$CurrentDir\.milestone_date"
$SpecFile = "$DocsDir\ACTIVE_SPEC.md"
$TuningFile = "$DocsDir\TUNING.md"

$host.UI.RawUI.WindowTitle = "AtomicCommander"

# Ensure directories exist
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
if (!(Test-Path $DocsDir)) { New-Item -ItemType Directory -Path $DocsDir | Out-Null }

# Layout constants
$BoxWidth = 37
$TotalWidth = 77

# Mode toggle: TEXT (AI input) or PS (PowerShell execution)
$script:CurrentMode = "TEXT"

# --- SQLITE QUERY HELPER (FIX #10, #11) ---
# WARNING: Only pass queries from trusted sources (internal code).
# Never interpolate user input directly into $Query.
function Invoke-Query {
    param(
        [string]$Query,
        [switch]$Silent  # If true, suppress error output
    )
    
    # FIX #10: Basic validation - reject obvious SQL injection attempts
    $dangerousPatterns = @("DROP TABLE", "DELETE FROM tasks", "--", ";--")
    foreach ($pattern in $dangerousPatterns) {
        if ($Query -match [regex]::Escape($pattern)) {
            if (-not $Silent) {
                Write-Host "🔴 Query rejected: Contains dangerous pattern" -ForegroundColor Red
            }
            return @()
        }
    }
    
    $script = @"
import sqlite3, json, sys
try:
    conn = sqlite3.connect('$DB_FILE')
    conn.row_factory = sqlite3.Row
    rows = conn.execute('''$Query''').fetchall()
    print(json.dumps([dict(r) for r in rows]))
    conn.close()
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    print('[]')
"@
    try {
        $result = $script | python 2>$null
        if ($result) { 
            $parsed = $result | ConvertFrom-Json
            # FIX #11: Check for error response
            if ($parsed.error) {
                if (-not $Silent) {
                    Write-Host "⚠️ Query warning: $($parsed.error)" -ForegroundColor Yellow
                }
                return @()
            }
            return $parsed
        }
    }
    catch {
        # FIX #11: Report the error instead of silent catch
        if (-not $Silent) {
            Write-Host "🔴 Database Query Failed: $_" -ForegroundColor Red
        }
    }
    return @()
}

# --- GET PROJECT MODE ---
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

# --- GET WORKER STATUS ---
function Get-WorkerStatus {
    param([string]$Type)
    
    $logFiles = Get-ChildItem "$LogDir\*-$Type.log" -ErrorAction SilentlyContinue
    if (-not $logFiles) { return @{ Status = "DOWN"; Color = "Red"; Icon = "🔴" } }
    
    $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $age = (Get-Date) - $latestLog.LastWriteTime
    
    if ($age.TotalSeconds -lt 60) {
        return @{ Status = "UP (polling)"; Color = "Green"; Icon = "🟢" }
    }
    elseif ($age.TotalMinutes -lt 5) {
        return @{ Status = "WAITING"; Color = "Yellow"; Icon = "🟡" }
    }
    else {
        return @{ Status = "DOWN"; Color = "Red"; Icon = "🔴" }
    }
}

# --- OPEN FILE ---
function Open-DocFile {
    param([string]$Path)
    if (!(Test-Path $Path)) { "" | Out-File $Path -Encoding UTF8 }
    $vscode = "C:\Users\$env:USERNAME\AppData\Local\Programs\Microsoft VS Code\Code.exe"
    if (Test-Path $vscode) { Start-Process $vscode -ArgumentList $Path }
    else { Start-Process notepad.exe -ArgumentList $Path }
}

# --- PAD STRING TO WIDTH ---
function Format-Cell {
    param([string]$Text, [int]$Width)
    if ($Text.Length -gt $Width) { return $Text.Substring(0, $Width) }
    return $Text.PadRight($Width)
}

# --- MODE TOGGLE ---
function Switch-Mode {
    if ($script:CurrentMode -eq "TEXT") {
        $script:CurrentMode = "PS"
        Write-Host "  Switched to [PS>] PowerShell Mode" -ForegroundColor Blue
    }
    else {
        $script:CurrentMode = "TEXT"
        Write-Host "  Switched to [TEXT] Input Mode" -ForegroundColor Green
    }
    Start-Sleep -Milliseconds 500
}

# --- CONTINUE COMMAND ---
function Invoke-Continue {
    # 1. Check for RED decisions (blockers)
    $redDecisions = Invoke-Query "SELECT id, question FROM decisions WHERE status='pending' AND priority='red' LIMIT 1"
    if ($redDecisions.Count -gt 0) {
        $dec = $redDecisions[0]
        Write-Host "  🔴 BLOCKED: Decision required" -ForegroundColor Red
        Write-Host "     [$($dec.id)] $($dec.question)" -ForegroundColor Yellow
        return
    }
    
    # 2. Check for stuck tasks (3 strikes)
    $stuckTasks = Invoke-Query "SELECT id, desc FROM tasks WHERE auditor_status='escalated' OR retry_count >= 3 LIMIT 1"
    if ($stuckTasks.Count -gt 0) {
        $stuck = $stuckTasks[0]
        Write-Host "  🔴 STUCK: Auditor gave up on task" -ForegroundColor Red
        Write-Host "     [$($stuck.id)] $($stuck.desc)" -ForegroundColor Yellow
        Write-Host "     Type 'reset $($stuck.id)' after fixing manually" -ForegroundColor Gray
        return
    }
    
    # 3. Check if auditor is currently reviewing
    $inReview = Invoke-Query "SELECT id, desc, retry_count FROM tasks WHERE auditor_status='rejected' LIMIT 1"
    if ($inReview.Count -gt 0) {
        $task = $inReview[0]
        Write-Host "  ⏳ Auditor loop active: [$($task.id)] Retry $($task.retry_count)/3" -ForegroundColor Yellow
        return
    }
    
    # 4. Get next pending task
    $nextTask = Invoke-Query "SELECT id, type, desc, strictness FROM tasks WHERE status='pending' ORDER BY priority DESC, id LIMIT 1"
    if ($nextTask.Count -eq 0) {
        Write-Host "  ✅ Queue empty. All done!" -ForegroundColor Green
        return
    }
    
    $task = $nextTask[0]
    $strictness = if ($task.strictness) { $task.strictness.ToUpper() } else { "NORMAL" }
    $icon = switch ($strictness) { "CRITICAL" { "🔴" } "RELAXED" { "🟢" } default { "🟡" } }
    
    # 5. Dispatch
    Write-Host "  ▶ Resuming [$icon $strictness]: [$($task.id)] $($task.desc)" -ForegroundColor Cyan
    Invoke-Query "UPDATE tasks SET status='in_progress', updated_at=strftime('%s','now') WHERE id=$($task.id)" | Out-Null
}

# --- RESET TASK AUDITOR ---
function Invoke-Reset {
    param([int]$TaskId)
    if ($TaskId -le 0) {
        Write-Host "  Usage: reset <task_id>" -ForegroundColor Yellow
        return
    }
    # Patch 2: Full context flush - reset retry count AND clear auditor cache
    Invoke-Query "UPDATE tasks SET retry_count=0, auditor_status='pending', auditor_feedback='[]', status='pending' WHERE id=$TaskId" | Out-Null
    # Log the context flush
    $now = [int](Get-Date -UFormat %s)
    Invoke-Query "INSERT INTO audit_log (task_id, action, strictness, reason, retry_count, created_at) VALUES ($TaskId, 'context_flush', 'N/A', 'User reset - context cleared', 0, $now)" | Out-Null
    Write-Host "  ✅ Task $TaskId reset + context flushed. Auditor will re-read from disk." -ForegroundColor Green
}

# --- GET AUDIT LOG ---
function Get-AuditLog {
    $logs = Invoke-Query "SELECT task_id, action, strictness, reason, created_at FROM audit_log ORDER BY created_at DESC LIMIT 4"
    return $logs
}

# --- LIBRARIAN FUNCTIONS ---
function Get-LibrarianStatus {
    $pending = Invoke-Query "SELECT manifest_id, COUNT(*) as c FROM librarian_ops WHERE status='pending' GROUP BY manifest_id LIMIT 1"
    $blocked = Invoke-Query "SELECT COUNT(*) as c FROM librarian_ops WHERE status='blocked'"
    $recent = Invoke-Query "SELECT manifest_id FROM librarian_ops WHERE status='executed' ORDER BY executed_at DESC LIMIT 1"
    
    return @{
        Pending      = if ($pending.Count -gt 0) { $pending[0].c } else { 0 }
        Blocked      = if ($blocked.Count -gt 0) { $blocked[0].c } else { 0 }
        LastManifest = if ($recent.Count -gt 0) { $recent[0].manifest_id } else { "none" }
    }
}

function Invoke-LibrarianScan {
    Write-Host "  📚 Scanning project..." -ForegroundColor Cyan
    # This would call the MCP tool - for now show placeholder
    Write-Host "  Use 'lib scan' command to initiate full scan" -ForegroundColor Gray
}

function Show-LibrarianPanel {
    Clear-Host
    Write-Host ("=" * $TotalWidth) -ForegroundColor Cyan
    Write-Host "  📚 THE LIBRARIAN - File System Architect" -ForegroundColor White
    Write-Host ("=" * $TotalWidth) -ForegroundColor Cyan
    
    $status = Get-LibrarianStatus
    Write-Host ""
    Write-Host "  Status:" -ForegroundColor Yellow
    Write-Host "    Pending Operations: $($status.Pending)" -ForegroundColor Gray
    Write-Host "    Blocked (Secrets): $($status.Blocked)" -ForegroundColor $(if ($status.Blocked -gt 0) { "Red" } else { "Gray" })
    Write-Host "    Last Manifest: $($status.LastManifest)" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor Yellow
    Write-Host "    lib scan     - Scan project for cleanup opportunities"
    Write-Host "    lib status   - Show pending operations"
    Write-Host "    lib approve  - Approve pending manifest"
    Write-Host "    lib execute  - Execute approved manifest"
    Write-Host "    lib restore  - Restore from last manifest"
    
    Write-Host ""
    Write-Host ("-" * $TotalWidth) -ForegroundColor DarkGray
    Write-Host "  Press Q to return..." -ForegroundColor Yellow
    
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).KeyChar
            if ($key -eq 'q' -or $key -eq 'Q') { return }
        }
        Start-Sleep -Milliseconds 200
    }
}

# --- DRAW DASHBOARD ---
function Show-Dashboard {
    Clear-Host
    
    # Get data
    $proj = Get-ProjectMode
    $beStatus = Get-WorkerStatus "backend"
    $feStatus = Get-WorkerStatus "frontend"
    
    # Get stats
    $stats = Invoke-Query "SELECT status, COUNT(*) as c FROM tasks GROUP BY status"
    $pending = 0; $working = 0; $done = 0; $failed = 0; $blocked = 0
    foreach ($s in $stats) {
        switch ($s.status) { 
            'pending' { $pending = $s.c } 
            'in_progress' { $working = $s.c } 
            'completed' { $done = $s.c } 
            'failed' { $failed = $s.c } 
            'blocked' { $blocked = $s.c } 
        }
    }
    
    # Get active tasks
    $beActive = Invoke-Query "SELECT id, substr(desc,1,25) as d FROM tasks WHERE type='backend' AND status='in_progress' LIMIT 1"
    $feActive = Invoke-Query "SELECT id, substr(desc,1,25) as d FROM tasks WHERE type='frontend' AND status='in_progress' LIMIT 1"
    
    # Get roadmap (pending tasks)
    $beRoadmap = Invoke-Query "SELECT id, substr(desc,1,28) as d FROM tasks WHERE type='backend' AND status='pending' ORDER BY priority DESC, id LIMIT 2"
    $feRoadmap = Invoke-Query "SELECT id, substr(desc,1,28) as d FROM tasks WHERE type='frontend' AND status='pending' ORDER BY priority DESC, id LIMIT 2"
    
    # Get decisions
    $decisions = Invoke-Query "SELECT id, priority, substr(question,1,28) as q FROM decisions WHERE status='pending' ORDER BY CASE priority WHEN 'red' THEN 1 WHEN 'yellow' THEN 2 ELSE 3 END LIMIT 4"
    
    # Get COT stream
    $cotLines = @()
    $combinedLog = "$LogDir\combined.log"
    if (Test-Path $combinedLog) { $cotLines = Get-Content $combinedLog -Tail 4 -ErrorAction SilentlyContinue }
    
    # === HEADER ===
    $headerLine = "=" * $TotalWidth
    Write-Host $headerLine -ForegroundColor Cyan
    
    $modeStr = "$($proj.Icon) $($proj.Mode)"
    if ($null -ne $proj.Days) { $modeStr += " ($($proj.Days)d)" }
    $modeIndicator = if ($script:CurrentMode -eq "TEXT") { "[TEXT]" } else { "[PS>]" }
    $modeColor = if ($script:CurrentMode -eq "TEXT") { "Green" } else { "Blue" }
    $title = "  ATOMIC MESH COMMANDER v7.1"
    $rightPad = $TotalWidth - $title.Length - $modeStr.Length - $modeIndicator.Length - 4
    Write-Host "$title$(' ' * $rightPad)$modeStr " -NoNewline -ForegroundColor White
    Write-Host $modeIndicator -ForegroundColor $modeColor
    
    Write-Host $headerLine -ForegroundColor Cyan
    
    # === TOP ROW: BACKEND | FRONTEND ===
    $topBorder = "+" + ("-" * ($BoxWidth - 2)) + "+" + " " + "+" + ("-" * ($BoxWidth - 2)) + "+"
    Write-Host $topBorder -ForegroundColor DarkGray
    
    # Row 1: Titles
    $beTitle = Format-Cell " BACKEND" ($BoxWidth - 2)
    $feTitle = Format-Cell " FRONTEND" ($BoxWidth - 2)
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $beTitle -NoNewline -ForegroundColor Cyan
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $feTitle -NoNewline -ForegroundColor Cyan
    Write-Host "|" -ForegroundColor DarkGray
    
    # Row 2: Status
    $beStatusLine = Format-Cell " Status: $($beStatus.Icon) $($beStatus.Status)" ($BoxWidth - 2)
    $feStatusLine = Format-Cell " Status: $($feStatus.Icon) $($feStatus.Status)" ($BoxWidth - 2)
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $beStatusLine -NoNewline -ForegroundColor $beStatus.Color
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $feStatusLine -NoNewline -ForegroundColor $feStatus.Color
    Write-Host "|" -ForegroundColor DarkGray
    
    # Row 3: Working on
    $beWork = if ($beActive.Count -gt 0) { " Working: [$($beActive[0].id)] $($beActive[0].d)" } else { " Working: (idle)" }
    $feWork = if ($feActive.Count -gt 0) { " Working: [$($feActive[0].id)] $($feActive[0].d)" } else { " Working: (idle)" }
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host (Format-Cell $beWork ($BoxWidth - 2)) -NoNewline -ForegroundColor White
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host (Format-Cell $feWork ($BoxWidth - 2)) -NoNewline -ForegroundColor White
    Write-Host "|" -ForegroundColor DarkGray
    
    # Row 4: Empty
    $empty = Format-Cell "" ($BoxWidth - 2)
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $empty -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $empty -NoNewline
    Write-Host "|" -ForegroundColor DarkGray
    
    # Row 5: Roadmap header
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host (Format-Cell " Roadmap:" ($BoxWidth - 2)) -NoNewline -ForegroundColor Yellow
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host (Format-Cell " Roadmap:" ($BoxWidth - 2)) -NoNewline -ForegroundColor Yellow
    Write-Host "|" -ForegroundColor DarkGray
    
    # Row 6-7: Roadmap items
    for ($i = 0; $i -lt 2; $i++) {
        $beItem = if ($i -lt $beRoadmap.Count) { "   -> [$($beRoadmap[$i].id)] $($beRoadmap[$i].d)" } else { "" }
        $feItem = if ($i -lt $feRoadmap.Count) { "   -> [$($feRoadmap[$i].id)] $($feRoadmap[$i].d)" } else { "" }
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-Cell $beItem ($BoxWidth - 2)) -NoNewline -ForegroundColor Gray
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host " " -NoNewline
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-Cell $feItem ($BoxWidth - 2)) -NoNewline -ForegroundColor Gray
        Write-Host "|" -ForegroundColor DarkGray
    }
    
    # Top row bottom border
    Write-Host $topBorder -ForegroundColor DarkGray
    
    # === BOTTOM ROW: DECISIONS | COT STREAM ===
    Write-Host $topBorder -ForegroundColor DarkGray
    
    # Row 1: Titles
    $decTitle = Format-Cell " DECISIONS" ($BoxWidth - 2)
    $cotTitle = Format-Cell " COT STREAM" ($BoxWidth - 2)
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $decTitle -NoNewline -ForegroundColor Cyan
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $cotTitle -NoNewline -ForegroundColor Cyan
    Write-Host "|" -ForegroundColor DarkGray
    
    # Row 2-5: Content
    for ($i = 0; $i -lt 4; $i++) {
        # Decision
        $decLine = ""
        $decColor = "Gray"
        if ($i -lt $decisions.Count) {
            $dec = $decisions[$i]
            $icon = switch ($dec.priority) { 'red' { 'R' } 'yellow' { 'Y' } default { 'G' } }
            $decLine = "   [$icon] $($dec.q)"
            $decColor = switch ($dec.priority) { 'red' { 'Red' } 'yellow' { 'Yellow' } default { 'Green' } }
        }
        
        # COT
        $cotLine = ""
        if ($i -lt $cotLines.Count -and $cotLines[$i]) {
            $cotLine = " " + $cotLines[$i]
            if ($cotLine.Length -gt ($BoxWidth - 2)) { $cotLine = $cotLine.Substring(0, $BoxWidth - 2) }
        }
        
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-Cell $decLine ($BoxWidth - 2)) -NoNewline -ForegroundColor $decColor
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host " " -NoNewline
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-Cell $cotLine ($BoxWidth - 2)) -NoNewline -ForegroundColor DarkGray
        Write-Host "|" -ForegroundColor DarkGray
    }
    
    # Row 6: Empty
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $empty -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host $empty -NoNewline
    Write-Host "|" -ForegroundColor DarkGray
    
    # Bottom border
    Write-Host $topBorder -ForegroundColor DarkGray
    
    # === INPUT SECTION ===
    $inputLine = "-" * $TotalWidth
    Write-Host $inputLine -ForegroundColor DarkGray
}

# --- SHOW HOTKEYS ---
function Show-Hotkeys {
    Write-Host "[C]ontinue [M]ode [L]ib [1]BE [2]FE [A]udit [D]ec [R]ef [H]elp [Q]uit" -ForegroundColor DarkYellow
}

# --- STREAM VIEWER ---
function Show-Stream {
    param([string]$Type)
    
    $logFile = Get-ChildItem "$LogDir\*-$Type.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (!$logFile) { 
        Write-Host "  No $Type log found." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    
    Clear-Host
    $title = $Type.ToUpper()
    Write-Host ("=" * $TotalWidth) -ForegroundColor Cyan
    Write-Host "  $title COT STREAM" -ForegroundColor White
    Write-Host ("=" * $TotalWidth) -ForegroundColor Cyan
    Write-Host "  Source: $($logFile.Name)" -ForegroundColor Gray
    Write-Host ("-" * $TotalWidth) -ForegroundColor DarkGray
    
    $lines = Get-Content $logFile.FullName -Tail 15 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line.Length -gt 75) { $line = $line.Substring(0, 75) }
        Write-Host "  $line" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host ("-" * $TotalWidth) -ForegroundColor DarkGray
    Write-Host "  Press Q to return..." -ForegroundColor Yellow
    
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).KeyChar
            if ($key -eq 'q' -or $key -eq 'Q') { return }
        }
        Start-Sleep -Milliseconds 200
    }
}

# --- EXECUTE COMMAND ---
function Invoke-Cmd {
    param([string]$UserInput)
    
    $parts = $UserInput -split ' ', 2
    $cmd = $parts[0].ToLower()
    $cmdArgs = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    
    switch ($cmd) {
        'nuke' {
            Invoke-Query "DELETE FROM tasks WHERE status='pending'" | Out-Null
            Write-Host "  Nuked pending tasks!" -ForegroundColor Red
        }
        'status' {
            $stats = Invoke-Query "SELECT status, COUNT(*) as c FROM tasks GROUP BY status"
            foreach ($s in $stats) { Write-Host "  $($s.status): $($s.c)" -ForegroundColor Gray }
        }
        'set' {
            $setParts = $cmdArgs -split ' ', 2
            if ($setParts.Count -ge 2) {
                if (!(Test-Path $TuningFile)) { "| Parameter | Value | Source |`n|---|---|---|" | Out-File $TuningFile -Encoding UTF8 }
                "| $($setParts[0]) | $($setParts[1]) | Manual |" | Out-File $TuningFile -Append -Encoding UTF8
                Write-Host "  Tuned: $($setParts[0]) -> $($setParts[1])" -ForegroundColor Green
            }
        }
        'post' {
            $postParts = $cmdArgs -split ' ', 2
            if ($postParts.Count -ge 2) {
                $type = $postParts[0]
                $desc = $postParts[1] -replace "'", "''"
                Invoke-Query "INSERT INTO tasks (type, desc, deps, status, updated_at, priority) VALUES ('$type', '$desc', '[]', 'pending', strftime('%s','now'), 1)" | Out-Null
                Write-Host "  Posted to $type" -ForegroundColor Green
            }
        }
        'decide' {
            $decParts = $cmdArgs -split ' ', 2
            if ($decParts.Count -ge 2 -and $decParts[0] -match '^\d+$') {
                $answer = $decParts[1] -replace "'", "''"
                Invoke-Query "UPDATE decisions SET status='resolved', answer='$answer' WHERE id=$($decParts[0])" | Out-Null
                Write-Host "  Decision resolved" -ForegroundColor Green
            }
        }
        'mode' {
            $proj = Get-ProjectMode
            Write-Host "  Mode: $($proj.Icon) $($proj.Mode)" -ForegroundColor $proj.Color
        }
        'milestone' {
            if ($cmdArgs) {
                $cmdArgs | Out-File $MilestoneFile -NoNewline -Encoding UTF8
                Write-Host "  Milestone: $cmdArgs" -ForegroundColor Cyan
            }
        }
        'reset' {
            if ($cmdArgs -match '^\d+$') {
                Invoke-Reset -TaskId ([int]$cmdArgs)
            }
            else {
                Write-Host "  Usage: reset <task_id>" -ForegroundColor Yellow
            }
        }
        'help' {
            Write-Host ""
            Write-Host "  COMMANDS:" -ForegroundColor Cyan
            Write-Host "    post <type> <desc>  - Post task"
            Write-Host "    set <key> <val>     - Update tuning"
            Write-Host "    decide <id> <ans>   - Resolve decision"
            Write-Host "    reset <id>          - Reset stuck task"
            Write-Host "    mode                - Show mode"
            Write-Host "    milestone <date>    - Set milestone"
            Write-Host "    nuke                - Clear pending"
            Write-Host "    status              - Show stats"
            Write-Host ""
            Write-Host "  HOTKEYS:" -ForegroundColor Yellow
            Write-Host "    C - Continue (auto-resume next task)"
            Write-Host "    M - Toggle TEXT/PS mode"
            Write-Host "    A - View audit log"
            Write-Host ""
        }
        default {
            if ($UserInput.Trim()) {
                Write-Host "  Unknown: $cmd (type 'help')" -ForegroundColor Red
            }
        }
    }
}

# --- MAIN LOOP ---
while ($true) {
    Show-Dashboard
    
    # Show prompt FIRST
    $proj = Get-ProjectMode
    Write-Host "$($proj.Icon) commander> " -NoNewline -ForegroundColor White
    
    # Capture cursor position for later
    $promptLine = [Console]::CursorTop
    
    # Add spacing to push hotkeys to bottom
    Write-Host ""
    Write-Host ""
    Write-Host ""
    Write-Host ""
    Write-Host ""
    Write-Host ""
    Show-Hotkeys
    
    # Move cursor back to prompt line for input
    [Console]::SetCursorPosition(14, $promptLine)
    
    # Input buffer
    $inputBuffer = ""
    
    while ($true) {
        if ([Console]::KeyAvailable) {
            $keyInfo = [Console]::ReadKey($true)
            $key = $keyInfo.Key
            $char = $keyInfo.KeyChar
            
            # Handle hotkeys when buffer is empty
            if ($inputBuffer -eq "") {
                if ($char -eq 'c' -or $char -eq 'C') { 
                    Write-Host ""
                    Invoke-Continue
                    Start-Sleep -Seconds 1
                    break 
                }
                if ($char -eq 'm' -or $char -eq 'M') { 
                    Write-Host ""
                    Switch-Mode
                    break 
                }
                if ($char -eq 'a' -or $char -eq 'A') { 
                    Write-Host ""
                    Write-Host "  AUDIT LOG:" -ForegroundColor Cyan
                    $logs = Get-AuditLog
                    foreach ($log in $logs) {
                        $icon = switch ($log.action) { 'approve' { '✅' } 'reject' { '🔴' } 'escalate' { '⚠️' } default { '📋' } }
                        Write-Host "    $icon [$($log.task_id)] $($log.action) - $($log.reason)" -ForegroundColor Gray
                    }
                    Start-Sleep -Seconds 2
                    break
                }
                if ($char -eq 'l' -or $char -eq 'L') { 
                    Show-LibrarianPanel
                    break 
                }
                if ($char -eq '1') { Show-Stream "backend"; break }
                if ($char -eq '2') { Show-Stream "frontend"; break }
                if ($char -eq 'd' -or $char -eq 'D') { Open-DocFile "$DocsDir\DECISION_LOG.md"; break }
                if ($char -eq 's' -or $char -eq 'S') { Open-DocFile $SpecFile; break }
                if ($char -eq 'r' -or $char -eq 'R') { break }
                if ($char -eq 'h' -or $char -eq 'H') { 
                    Write-Host ""
                    Invoke-Cmd "help"
                    Start-Sleep -Seconds 2
                    break 
                }
                if ($char -eq 'q' -or $char -eq 'Q') { 
                    Write-Host ""
                    Write-Host "  Goodbye!" -ForegroundColor Yellow
                    exit 
                }
            }
            
            # Handle Enter
            if ($key -eq 'Enter') {
                Write-Host ""
                if ($inputBuffer.Trim()) {
                    Invoke-Cmd $inputBuffer
                    Start-Sleep -Milliseconds 800
                }
                break
            }
            
            # Handle Backspace
            if ($key -eq 'Backspace') {
                if ($inputBuffer.Length -gt 0) {
                    $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
                continue
            }
            
            # Handle Escape
            if ($key -eq 'Escape') {
                $inputBuffer = ""
                break
            }
            
            # Regular character
            if ($char -match '[\x20-\x7E]') {
                $inputBuffer += $char
                Write-Host $char -NoNewline
            }
        }
        Start-Sleep -Milliseconds 50
    }
    
    # Show bottom separator and hotkeys after command
    Write-Host ("-" * $TotalWidth) -ForegroundColor DarkGray
    Show-Hotkeys
    Start-Sleep -Milliseconds 300
}
