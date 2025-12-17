# C:\Tools\atomic-mesh\worker.ps1
# FEATURES: Python MCP Client, COT Logging, Audio + Toast Alerts
# ISOLATION: Uses LOCAL project folder for logs
param (
    [string]$Type,
    [string]$Tool
)

$ID = "${Type}_$(Get-Date -Format 'HHmm')"
$MeshRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $MeshRoot) { $MeshRoot = (Get-Location).Path }
# --- MULTI-PROJECT ISOLATION: Use current directory for logs ---
$CurrentDir = (Get-Location).Path
$LogDir = "$CurrentDir\logs"
$LogFile = "$LogDir\$(Get-Date -Format 'yyyy-MM-dd')-$Type.log"
$CombinedLog = "$LogDir\combined.log"  # Shared log for Control Panel

# Ensure log dir exists
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
if (!(Test-Path $CombinedLog)) { "" | Out-File $CombinedLog -Encoding UTF8 }

$MCP_CLIENT = "$MeshRoot\mcp_client.py"

function Get-BlockedLanes {
    param([string]$WorkerType)
    $effective = if ($null -eq $WorkerType) { "" } else { [string]$WorkerType }
    $t = $effective.ToLower()
    switch ($t) {
        # Codex/generalist: owns backend/qa/ops by default (leave docs/frontend to Claude worker)
        "backend" { return @("frontend", "docs") }
        # Claude/creative: owns frontend/docs by default (leave backend/qa/ops to Codex worker)
        "frontend" { return @("backend", "qa", "ops") }
        # Explicit QA worker (if launched): restrict to qa lane only
        "qa" { return @("backend", "frontend", "ops", "docs") }
        default { return @() }
    }
}

# --- TOAST NOTIFICATION HELPER ---
function Show-Toast {
    param(
        [string]$Title,
        [string]$Message
    )
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $balloon.Icon = [System.Drawing.SystemIcons]::Warning
        $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
        $balloon.BalloonTipTitle = $Title
        $balloon.BalloonTipText = $Message
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 100
        $balloon.Dispose()
    }
    catch {
        Write-Host "   📢 $Title : $Message" -ForegroundColor Yellow
    }
}

# --- VISUAL IDENTITY ---
if ($Type -eq "backend") { $Color = "Green" }
elseif ($Type -eq "frontend") { $Color = "Cyan" }
else { $Color = "Yellow" }

Write-Host "🛡️ Worker $ID ($Type) online via $Tool." -ForegroundColor $Color

Set-Location $MeshRoot

while ($true) {
    # Poll using Python MCP client
    $JsonResult = $null
    try {
        $blocked = Get-BlockedLanes -WorkerType $Type
        $argsObj = @{
            worker_id = $ID
            blocked_lanes = $blocked
        }
        $argsJson = ($argsObj | ConvertTo-Json -Compress)
        # Capture stdout only (stderr includes MCP protocol logs)
        $JsonResult = python $MCP_CLIENT pick_task_braided $argsJson 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   ⚠️ MCP call failed (exit $LASTEXITCODE). Retrying..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            continue
        }
    }
    catch {
        Write-Host "   ⚠️ MCP connection error. Retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        continue
    }
    
    # Check for NO_WORK or empty result
    if ([string]::IsNullOrWhiteSpace($JsonResult) -or $JsonResult -match "NO_WORK") {
        Start-Sleep -Seconds 3
        continue
    }

    $JsonText = $JsonResult.Trim()
    $TaskData = $null
    try {
        $TaskData = $JsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Start-Sleep -Seconds 3
        continue
    }

    if (-not $TaskData -or $TaskData.status -ne "OK") {
        Start-Sleep -Seconds 3
        continue
    }

    $TaskID = $TaskData.id
    $Desc = if ($TaskData.description) { [string]$TaskData.description } else { "No description" }
    $Lane = if ($TaskData.lane) { [string]$TaskData.lane } else { $Type }
    
    $Header = "⚡ [$Type/$Lane] Task $TaskID"
    Write-Host "`n$Header" -ForegroundColor $Color
    
    # Log Header to both files
    $logLine = "[$((Get-Date).ToString('HH:mm:ss'))] $Header : $($Desc.Substring(0, [Math]::Min(80, $Desc.Length)))"
    try {
        $logLine | Out-File -FilePath $LogFile -Append -Encoding UTF8
        # Write to shared combined.log for Control Panel
        $logLine | Out-File -FilePath $CombinedLog -Append -Encoding UTF8
        # Keep combined.log from growing too large (last 100 lines)
        if ((Get-Content $CombinedLog -ErrorAction SilentlyContinue | Measure-Object).Count -gt 100) {
            Get-Content $CombinedLog -Tail 50 | Set-Content $CombinedLog -Encoding UTF8
        }
    }
    catch {}

    # --- EXECUTE ---
    $Prompt = "You are a logic engine. 
    TASK_ID: $TaskID
    INSTRUCTION: $Desc
    
    CONTEXT PROTOCOL:
    1. ANALYZE: If the instruction mentions specific files, READ THEM first.
    2. EXECUTE: Perform the task.
    3. REPORT: Print a 1-sentence summary of what you changed.
    
    Do not chatter. Just do the work."
    
    $Output = ""
    $StartTime = Get-Date

    try {
        if ($Tool -eq "claude") {
            $Output = claude --print "$Prompt" 2>&1 | Tee-Object -FilePath $LogFile -Append
        }
        elseif ($Tool -eq "codex") {
            $Output = codex exec "$Prompt" 2>&1 | Tee-Object -FilePath $LogFile -Append
        }
    }
    catch {
        $Output = "Execution error: $_"
    }
    
    $Duration = [Math]::Round(((Get-Date) - $StartTime).TotalSeconds, 1)

    # --- REPORTING ---
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Success (${Duration}s)" -ForegroundColor $Color
        python $MCP_CLIENT complete_task "{`"task_id`": $TaskID, `"output`": `"Done in ${Duration}s`", `"success`": true}" 2>&1 | Out-Null
    }
    else {
        Write-Host "   ❌ FAILURE (Exit $LASTEXITCODE, ${Duration}s)" -ForegroundColor Red
        
        # --- AUDIO ALERT ---
        [System.Console]::Beep(1000, 500)
        
        # --- TOAST NOTIFICATION ---
        Show-Toast -Title "🚨 Task $TaskID Failed" -Message "[$Type] Error after ${Duration}s"
        
        try {
            "   ❌ ERROR: Exit $LASTEXITCODE" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        }
        catch {}
        
        python $MCP_CLIENT complete_task "{`"task_id`": $TaskID, `"output`": `"Exit $LASTEXITCODE`", `"success`": false}" 2>&1 | Out-Null
    }
}
