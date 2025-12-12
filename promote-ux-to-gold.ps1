# ============================================================================
# ATOMIC MESH - UX PROMOTION SCRIPT (Sandbox → Gold)
# ============================================================================
# Decision: UX-CP-001
# Approver: The Gavel
# Date: 2025-12-11
# Status: ✅ APPROVED
# ============================================================================

# GOVERNANCE: Fail fast on any error
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  ATOMIC MESH - UX PROMOTION TO GOLD                            ║" -ForegroundColor Cyan
Write-Host "║  Decision ID: UX-CP-001                                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verify we're in the gold repo
$currentPath = Get-Location
if ($currentPath.Path -notlike "*atomic-mesh" -or $currentPath.Path -like "*sandbox*") {
    Write-Host "❌ ERROR: This script must be run from E:\Code\atomic-mesh" -ForegroundColor Red
    Write-Host "   Current location: $currentPath" -ForegroundColor Yellow
    exit 1
}

# Verify sandbox exists
$sandboxPath = "E:\Code\atomic-mesh-ui-sandbox\control_panel.ps1"
if (-not (Test-Path $sandboxPath)) {
    Write-Host "❌ ERROR: Sandbox file not found: $sandboxPath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Pre-flight checks passed" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 1: Safety Snapshot + Backup
# ============================================================================
Write-Host "🔒 STEP 1: Creating safety snapshot and backup..." -ForegroundColor Cyan
Write-Host ""

# Create backup of current control panel
$backupFile = ".\control_panel.ps1.pre_ux_backup"
Copy-Item .\control_panel.ps1 $backupFile
Write-Host "✅ File backup created: $backupFile" -ForegroundColor Green

# Optional: Create system snapshot via your snapshot mechanism
Write-Host ""
Write-Host "📸 System snapshot (optional):" -ForegroundColor Yellow
Write-Host "   If you have snapshot capability, run:" -ForegroundColor Gray
Write-Host "   .\control_panel.ps1 /snapshot v13.1.0-pre-ux" -ForegroundColor White
Write-Host ""
Write-Host "   Press Enter to continue without snapshot, or Ctrl+C to abort..." -ForegroundColor Gray
Read-Host

# ============================================================================
# STEP 2: Visual Diff Review
# ============================================================================
Write-Host ""
Write-Host "📊 STEP 2: Opening diff viewer for manual review..." -ForegroundColor Cyan
Write-Host ""

code --diff `
    E:\Code\atomic-mesh\control_panel.ps1 `
    E:\Code\atomic-mesh-ui-sandbox\control_panel.ps1

Write-Host "⏸️  REVIEW CHECKLIST:" -ForegroundColor Yellow
Write-Host "   ✓ Changes confined to UI (hints, palette, debug overlay)" -ForegroundColor Gray
Write-Host "   ✓ No changes to update_task_state" -ForegroundColor Gray
Write-Host "   ✓ No changes to /ship confirmation logic" -ForegroundColor Gray
Write-Host "   ✓ No changes to safety linter or DB writes" -ForegroundColor Gray
Write-Host "   ✓ ~138 insertions, ~74 deletions expected" -ForegroundColor Gray
Write-Host ""
Write-Host "   Press Enter after reviewing diff, or Ctrl+C to abort..." -ForegroundColor Gray
Read-Host

# ============================================================================
# STEP 3: Copy Sandbox to Gold
# ============================================================================
Write-Host ""
Write-Host "📦 STEP 3: Promoting sandbox UX changes to gold..." -ForegroundColor Cyan
Write-Host ""

Copy-Item `
    E:\Code\atomic-mesh-ui-sandbox\control_panel.ps1 `
    E:\Code\atomic-mesh\control_panel.ps1 -Force

Write-Host "✅ control_panel.ps1 updated in gold" -ForegroundColor Green

# ============================================================================
# STEP 4: Run CI + Safety Gates
# ============================================================================
Write-Host ""
Write-Host "🧪 STEP 4: Running governance checks..." -ForegroundColor Cyan
Write-Host ""

# Static safety check
if (Test-Path "tests\static_safety_check.py") {
    Write-Host "→ Running static safety check..." -ForegroundColor Gray
    try {
        python tests\static_safety_check.py
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ Static safety: PASS" -ForegroundColor Green
        }
        else {
            throw "Static safety check failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "  ❌ Static safety: FAIL" -ForegroundColor Red
        Write-Host ""
        Write-Host "🔄 ROLLBACK COMMAND:" -ForegroundColor Yellow
        Write-Host "   Copy-Item $backupFile .\control_panel.ps1" -ForegroundColor White
        exit 1
    }
}
else {
    Write-Host "  ⚠️  Static safety check not found, skipping..." -ForegroundColor Yellow
}

# CI tests
if (Test-Path "tests\run_ci.py") {
    Write-Host "→ Running CI tests..." -ForegroundColor Gray
    try {
        python tests\run_ci.py
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ CI: PASS" -ForegroundColor Green
        }
        else {
            throw "CI failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "  ❌ CI: FAIL" -ForegroundColor Red
        Write-Host ""
        Write-Host "🔄 ROLLBACK COMMAND:" -ForegroundColor Yellow
        Write-Host "   Copy-Item $backupFile .\control_panel.ps1" -ForegroundColor White
        exit 1
    }
}
else {
    Write-Host "  ⚠️  CI tests not found, skipping..." -ForegroundColor Yellow
}

# ============================================================================
# STEP 5: Manual Smoke Test Instructions
# ============================================================================
Write-Host ""
Write-Host "🧪 STEP 5: SMOKE TEST (Manual Validation Required)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Please run the following tests in gold control panel:" -ForegroundColor White
Write-Host ""
Write-Host "1. Launch Control Panel:" -ForegroundColor Yellow
Write-Host "   .\control_panel.ps1" -ForegroundColor White
Write-Host ""
Write-Host "2. First-Time Hint (if no tasks exist):" -ForegroundColor Yellow
Write-Host "   ✓ Micro-hint: 'OPS: ask health, drift, or type /ops'" -ForegroundColor Gray
Write-Host "   ✓ Footer: 'First time here? Type /init to bootstrap...'" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Mode Cycling:" -ForegroundColor Yellow
Write-Host "   ✓ Press Tab to cycle OPS ↔ PLAN" -ForegroundColor Gray
Write-Host "   ✓ Verify micro-hint changes with mode" -ForegroundColor Gray
Write-Host "   ✓ Verify [MODE] badge updates (Cyan/Yellow)" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Command Palette:" -ForegroundColor Yellow
Write-Host "   ✓ Type / and verify priority: /help, /init, /ops, /plan, /run, /ship" -ForegroundColor Gray
Write-Host "   ✓ Test Backspace/Esc to close picker cleanly" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Router Debug:" -ForegroundColor Yellow
Write-Host "   ✓ Run /router-debug and verify toggle message" -ForegroundColor Gray
Write-Host ""
Write-Host "6. Safety Check:" -ForegroundColor Yellow
Write-Host "   ✓ Run /ship (without --confirm) and verify it still blocks" -ForegroundColor Gray
Write-Host ""
Write-Host "Press Enter after completing smoke tests..." -ForegroundColor Gray
Read-Host

# ============================================================================
# STEP 6: Success Summary
# ============================================================================
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ UX PROMOTION COMPLETE - Decision UX-CP-001                 ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📋 NEXT STEPS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Update Decision Packet:" -ForegroundColor White
Write-Host "   → Tick gold production testing checkboxes in:" -ForegroundColor Gray
Write-Host "     docs\DECISIONS\2025-12-11-ux-control-panel.md" -ForegroundColor White
Write-Host ""
Write-Host "2. Create Follow-Up Tasks:" -ForegroundColor White
Write-Host "   → T-UX-ROUTER-01: Wire router debug overlay" -ForegroundColor Gray
Write-Host "   → T-UX-ROUTER-02: Add routing rules + tests" -ForegroundColor Gray
Write-Host "   → See: docs\TASKS\T-UX-ROUTER.md" -ForegroundColor White
Write-Host ""
Write-Host "3. Tag Release (when ready):" -ForegroundColor White
Write-Host "   git tag v13.2.0-ux-control-panel" -ForegroundColor White
Write-Host "   git push origin v13.2.0-ux-control-panel" -ForegroundColor White
Write-Host ""
Write-Host "4. Resync Sandbox (optional):" -ForegroundColor White
Write-Host "   Copy-Item E:\Code\atomic-mesh\control_panel.ps1 ``" -ForegroundColor White
Write-Host "             E:\Code\atomic-mesh-ui-sandbox\control_panel.ps1" -ForegroundColor White
Write-Host ""
Write-Host "───────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "🔄 ROLLBACK COMMAND (if needed):" -ForegroundColor Yellow
Write-Host "   Copy-Item $backupFile .\control_panel.ps1" -ForegroundColor White
Write-Host ""
Write-Host "📊 STATISTICS:" -ForegroundColor Cyan
Write-Host "   Modified: control_panel.ps1" -ForegroundColor Gray
Write-Host "   Changes: ~138 insertions, ~74 deletions" -ForegroundColor Gray
Write-Host "   Backup: $backupFile" -ForegroundColor Gray
Write-Host ""
