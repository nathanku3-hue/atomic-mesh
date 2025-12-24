$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$tests = @(
    @{ Name = "test_pre_ship_sanity"; Path = Join-Path $PSScriptRoot "test_pre_ship_sanity.ps1" },
    @{ Name = "test_golden_parity";   Path = Join-Path $PSScriptRoot "test_golden_parity.ps1"   },
    @{ Name = "test_doc_readiness";   Path = Join-Path $PSScriptRoot "test_doc_readiness.ps1"   },
    @{ Name = "test_snapshot_logging";Path = Join-Path $PSScriptRoot "test_snapshot_logging.ps1"},
    @{ Name = "test_command_guards";  Path = Join-Path $PSScriptRoot "test_command_guards.ps1"  }
)

$failures = @()

foreach ($test in $tests) {
    $name = $test.Name
    $path = $test.Path

    if (-not (Test-Path $path)) {
        Write-Host "[MISSING] $name ($path)" -ForegroundColor Red
        $failures += ("{0}: missing" -f $name)
        continue
    }

    Write-Host "[RUN] $name" -ForegroundColor Cyan
    $output = & pwsh -NoLogo -NoProfile -File $path 2>&1
    $exit = $LASTEXITCODE

    if ($exit -ne 0) {
        Write-Host "[FAIL] $name (exit $exit)" -ForegroundColor Red
        # Show trailing context to make failures actionable without rerun
        $tail = $output | Select-Object -Last 20
        if ($tail) {
            Write-Host "---- tail ($name) ----" -ForegroundColor DarkGray
            foreach ($line in $tail) { Write-Host $line }
            Write-Host "-----------------------" -ForegroundColor DarkGray
        }
        $failures += ("{0}: exit {1}" -f $name, $exit)
    }
    else {
        Write-Host "[PASS] $name" -ForegroundColor Green
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Reality gate failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host ""
Write-Host "Reality gate passed (all suites green)." -ForegroundColor Green
exit 0
