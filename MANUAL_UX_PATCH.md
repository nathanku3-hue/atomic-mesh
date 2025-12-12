# SANDBOX UX POLISH - Step-by-Step Manual Application Guide

**IMPORTANT**: The automated script had issues. Please apply these changes manually.
This ensures clean, working PowerShell code.

---

## Step 1: Add Router Debug Globals

**Location**: After line 333 (`$Global:LastShipNote = $null`)

**ADD these 3 lines**:
```powershell
# SANDBOX UX: Router debug overlay toggle
$Global:RouterDebug = $false
$Global:LastRoutedCommand = $null
```

**Result** (lines 334-336 will be NEW):
```powershell
$Global:LastShipNote = $null

# SANDBOX UX: Router debug overlay toggle
$Global:RouterDebug = $false
$Global:LastRoutedCommand = $null

# Mode configuration...
```

---

## Step 2: Update Mode Config to Add MicroHint

**Location**: Lines 337-340

**FIND**:
```powershell
    "OPS"  = @{ Color = "Cyan";    Prompt = "[OPS]";  Hint = "Monitor health & drift" }
    "PLAN" = @{ Color = "Yellow";  Prompt = "[PLAN]"; Hint = "Describe work to plan" }
    "RUN"  = @{ Color = "Magenta"; Prompt = "[RUN]";  Hint = "Execute & steer" }
    "SHIP" = @{ Color = "Green";   Prompt = "[SHIP]"; Hint = "Release w/ confirm" }
```

**REPLACE WITH**:
```powershell
    "OPS"  = @{ Color = "Cyan";    Prompt = "[OPS]";  Hint = "Monitor health & drift";    MicroHint = "OPS: ask 'health', 'drift', or type /ops" }
    "PLAN" = @{ Color = "Yellow";  Prompt = "[PLAN]"; Hint = "Describe work to plan";      MicroHint = "PLAN: describe what you want to build" }
    "RUN"  = @{ Color = "Magenta"; Prompt = "[RUN]";  Hint = "Execute & steer";            MicroHint = "RUN: give feedback or just press Enter" }
    "SHIP" = @{ Color = "Green";   Prompt = "[SHIP]"; Hint = "Release w/ confirm";         MicroHint = "SHIP: write notes, /ship --confirm to release" }
```

---

## Step 3: Replace Get-PickerCommands Function

**Location**: Lines 239-258 (starts with `function Get-PickerCommands {`)

**DELETE** the entire function (20 lines) and **REPLACE** with this:

```powershell
function Get-PickerCommands {
    param([string]$Filter = "")

    # SANDBOX UX: Priority commands (always shown first)
    $priorityOrder = @("help", "init", "ops", "plan", "run", "ship")

    if ($Filter -eq "") {
        $result = @()
        foreach ($cmdName in $priorityOrder) {
            if ($Global:Commands.Contains($cmdName)) {
                $result += [PSCustomObject]@{Name = $cmdName; Desc = $Global:Commands[$cmdName].Desc; Tier = "priority"}
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
                $cmdObj = [PSCustomObject]@{Name = $k; Desc = $Global:Commands[$k].Desc; Tier = "all"}
                if ($k -in $priorityOrder) {
                    $priorityMatches += $cmdObj
                } else {
                    $otherMatches += $cmdObj
                }
            }
        }
        $sortedOthers = $otherMatches | Sort-Object -Property Name
        $sortedPriority = @()
        foreach ($cmd in $priorityOrder) {
            $match = $priorityMatches | Where-Object {$_.Name -eq $cmd}
            if ($match) { $sortedPriority += $match }
        }
        return $sortedPriority + $sortedOthers
    }
}
```

---

## Step 4: Add /router-debug Command

**Location**: After line 672 (after the `"refresh"` case closes with `}`)

**ADD** this new command case:

```powershell
        "router-debug" {
            $Global:RouterDebug = -not $Global:RouterDebug
            $status = if ($Global:RouterDebug) {"ENABLED"} else {"DISABLED"}
            Write-Host ""
            Write-Host "  🔍 Router Debug $status" -ForegroundColor $(if ($Global:RouterDebug) {"Green"} else {"Yellow"})
            Write-Host "     Debug overlay will show routing decisions above input bar" -ForegroundColor DarkGray
            Write-Host ""
            return "refresh"
        }
```

---

## Step 5: Replace Draw-FooterBar Function  

**Location**: Lines 2874-2913 (starts with `function Draw-FooterBar {`)

**DELETE** the entire function (40 lines) and **REPLACE** with:

```powershell
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

    # SANDBOX UX: First-time hint
    $stats = Get-TaskStats
    $hasTasks = ($stats.pending -gt 0 -or $stats.in_progress -gt 0 -or $stats.completed -gt 0)
    if (-not $hasTasks) {
        Set-Pos $footerRow 2
        Write-Host "First time here? Type /init to bootstrap a new project." -ForegroundColor DarkGray -NoNewline
    }
    else {
        $scenario = Get-SystemScenario
        $nextHint = switch ($scenario) {
            "fresh"   {"/init"}
            "messy"   {"/lib clean"}
            "pending" {"/run"}
            default   {"/ops"}
        }
        Set-Pos $footerRow 0
        Write-Host "  Next: " -NoNewline -ForegroundColor DarkGray
        Write-Host $nextHint -NoNewline -ForegroundColor Cyan
    }

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
    if ($col -lt 0) {$col = 0}
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
```

---

## Testing After Changes

```powershell
cd E:\Code\atomic-mesh-ui-sandbox
.\control_panel.ps1
```

**Verify**:
- ✅ No parse errors
- ✅ Mode hint appears above input (e.g. "OPS: ask 'health'...")
- ✅ Type `/` and see help/init/ops/plan/run/ship first
- ✅ Type `/router-debug` and verify command works
- ✅ If no tasks, see "First time here?" hint

---

## If You  Get Parse Errors

1. Check line endings (should be `\r\n` on Windows)
2. Check that all braces `{}` match
3. Check that all quotes are properly closed
4. Use VS Code or PowerShell ISE - they show syntax errors

---

## Summary of Changes
- ✅ 3 new lines (router debug globals)
-✅ 4 lines modified (mode config MicroHint)
- ✅ 1 function replaced (Get-PickerCommands - ~45 lines)
- ✅ 1 new command added (/router-debug - ~9 lines)
- ✅ 1 function replaced (Draw-FooterBar - ~60 lines)

**Total**: ~120 lines changed across 5 locations
**Risk**: Low (UI-only, no state machine changes)
