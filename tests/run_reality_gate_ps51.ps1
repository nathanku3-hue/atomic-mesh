$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gatePath = Join-Path $PSScriptRoot "run_reality_gate.ps1"
$ps51Path = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $ps51Path)) {
    $ps51Path = "powershell.exe"
}

if (-not (Test-Path $gatePath)) {
    Write-Host "[MISSING] reality gate script ($gatePath)" -ForegroundColor Red
    exit 1
}

Write-Host "[RUN] reality gate (PowerShell 5.1)" -ForegroundColor Cyan
$output = & $ps51Path -NoLogo -NoProfile -File $gatePath 2>&1
$exitCode = $LASTEXITCODE

if ($output) {
    $output | ForEach-Object { Write-Host $_ }
}

if ($exitCode -ne 0) {
    Write-Host "[FAIL] reality gate under PowerShell 5.1 (exit $exitCode)" -ForegroundColor Red
} else {
    Write-Host "[PASS] reality gate under PowerShell 5.1" -ForegroundColor Green
}

exit $exitCode
