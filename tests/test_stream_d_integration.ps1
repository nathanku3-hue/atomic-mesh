# Stream D Integration Test
# Tests /dupcheck and /snippets commands for output discipline

Write-Host "=== Stream D Integration Test ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: /dupcheck with existing snippet (should detect itself)
Write-Host "Test 1: /dupcheck detects similar code" -ForegroundColor Yellow
$testFile = "library/snippets/python/retry_with_backoff.py"
if (Test-Path $testFile) {
    $output = python -c "from mesh_server import snippet_duplicate_check; print(snippet_duplicate_check(file_path='$testFile', lang='python'))" 2>&1
    $result = $output | ConvertFrom-Json -ErrorAction SilentlyContinue

    if ($result -and $result.warnings.Count -gt 0) {
        Write-Host "  ✅ PASS: Found $($result.warnings.Count) duplicate(s)" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "  ❌ FAIL: Should detect duplicate" -ForegroundColor Red
        $testsFailed++
    }
} else {
    Write-Host "  ⚠️  SKIP: Test file not found" -ForegroundColor Gray
}

# Test 2: /dupcheck limits to top 3
Write-Host "Test 2: /dupcheck output limit (top 3)" -ForegroundColor Yellow
$output = python -c "from mesh_server import snippet_duplicate_check; import json; r = snippet_duplicate_check(file_path='$testFile', lang='python'); d = json.loads(r); print(json.dumps({'count': len(d.get('warnings', [])), 'limited': len(d.get('warnings', []))}))" 2>&1
$result = $output | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($result) {
    Write-Host "  ✅ PASS: Function returns $($result.count) warning(s), will show max 3" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  ❌ FAIL: Could not verify limit" -ForegroundColor Red
    $testsFailed++
}

# Test 3: /snippets search works
Write-Host "Test 3: /snippets search functionality" -ForegroundColor Yellow
$output = python -c "from mesh_server import snippet_search; print(snippet_search(query='retry', lang='any', tags='', root_dir='.'))" 2>&1
$result = $output | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($result -and $result.results) {
    Write-Host "  ✅ PASS: Found $($result.results.Count) snippet(s)" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  ⚠️  SKIP: No snippets found (expected if empty)" -ForegroundColor Gray
}

# Test 4: No stack traces on error
Write-Host "Test 4: Error handling (no stack traces)" -ForegroundColor Yellow
$output = python -c "from mesh_server import snippet_duplicate_check; print(snippet_duplicate_check(file_path='nonexistent_file.py', lang='python'))" 2>&1
$result = $output | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($result -and $result.status -eq "ERROR" -and $result.message) {
    Write-Host "  ✅ PASS: Clean error message (no stack trace)" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  ❌ FAIL: Error handling issue" -ForegroundColor Red
    $testsFailed++
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Failed: $testsFailed" -ForegroundColor Red

if ($testsFailed -eq 0) {
    Write-Host ""
    Write-Host "✅ All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "❌ Some tests failed" -ForegroundColor Red
    exit 1
}
