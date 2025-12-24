#!/usr/bin/env pwsh
# Diagnose /draft-plan silent failure

$ErrorActionPreference = "Stop"

Write-Host "=== Diagnose /draft-plan ===" -ForegroundColor Cyan
Write-Host ""

# Load adapter
$adapterPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Adapters" "MeshServerAdapter.ps1"
Write-Host "Loading adapter: $adapterPath"
. $adapterPath

$projectPath = (Get-Location).Path
Write-Host "ProjectPath: $projectPath"
Write-Host ""

# Check for existing draft
Write-Host "=== Step 1: Check for existing draft ===" -ForegroundColor Yellow
$existingDraft = Get-LatestDraftPlan -ProjectPath $projectPath
if ($existingDraft) {
    Write-Host "Existing draft found: $existingDraft" -ForegroundColor Green
} else {
    Write-Host "No existing draft" -ForegroundColor Gray
}
Write-Host ""

# Test Invoke-DraftPlan
Write-Host "=== Step 2: Call Invoke-DraftPlan ===" -ForegroundColor Yellow
$result = Invoke-DraftPlan -ProjectPath $projectPath -TimeoutMs 10000
Write-Host "Result:" -ForegroundColor Cyan
$result | Format-Table -AutoSize
Write-Host ""
Write-Host "Full result:" -ForegroundColor Cyan
$result | ConvertTo-Json -Depth 3
