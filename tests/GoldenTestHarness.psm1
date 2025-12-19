# Golden-Master Test Harness for AtomicMesh.UI
# Provides render-to-string capability and fixture comparison

$script:RenderBuffer = [System.Text.StringBuilder]::new()
$script:BufferWidth = 80
$script:BufferHeight = 24
$script:CursorRow = 0
$script:CursorCol = 0
$script:IsCapturing = $false

# Initialize a virtual frame buffer (2D array of characters)
$script:FrameBuffer = $null

function Initialize-GoldenCapture {
    param(
        [int]$Width = 80,
        [int]$Height = 24
    )

    $script:BufferWidth = $Width
    $script:BufferHeight = $Height
    $script:CursorRow = 0
    $script:CursorCol = 0
    $script:IsCapturing = $true

    # Initialize frame buffer with spaces
    $script:FrameBuffer = @()
    for ($r = 0; $r -lt $Height; $r++) {
        $script:FrameBuffer += ,([char[]](" " * $Width))
    }
}

function Write-ToBuffer {
    param(
        [string]$Text,
        [switch]$NoNewline
    )

    if (-not $script:IsCapturing) { return }

    foreach ($char in $Text.ToCharArray()) {
        if ($char -eq "`n") {
            $script:CursorRow++
            $script:CursorCol = 0
            continue
        }
        if ($char -eq "`r") {
            $script:CursorCol = 0
            continue
        }

        if ($script:CursorRow -lt $script:BufferHeight -and $script:CursorCol -lt $script:BufferWidth) {
            $script:FrameBuffer[$script:CursorRow][$script:CursorCol] = $char
            $script:CursorCol++
        }
    }

    if (-not $NoNewline) {
        $script:CursorRow++
        $script:CursorCol = 0
    }
}

function Set-BufferPosition {
    param(
        [int]$Row,
        [int]$Col
    )

    if (-not $script:IsCapturing) { return }

    $script:CursorRow = [Math]::Max(0, [Math]::Min($Row, $script:BufferHeight - 1))
    $script:CursorCol = [Math]::Max(0, [Math]::Min($Col, $script:BufferWidth - 1))
}

function Get-CapturedFrame {
    if (-not $script:FrameBuffer) { return "" }

    $lines = @()
    foreach ($row in $script:FrameBuffer) {
        $lines += (-join $row)
    }
    return ($lines -join "`n")
}

function Stop-GoldenCapture {
    $script:IsCapturing = $false
    return Get-CapturedFrame
}

function Normalize-Frame {
    param(
        [string]$Frame,
        [string]$RepoRoot = ""
    )

    if (-not $Frame) { return "" }

    # 1. Line endings: \r\n -> \n
    $normalized = $Frame -replace "`r`n", "`n"

    # 2. Trailing spaces: strip per line
    $lines = $normalized -split "`n"
    $lines = $lines | ForEach-Object { $_.TrimEnd() }
    $normalized = $lines -join "`n"

    # 3. Path tokens: replace repo path with <REPO>
    if ($RepoRoot) {
        $escaped = [regex]::Escape($RepoRoot)
        $normalized = $normalized -replace $escaped, "<REPO>"
        # Also handle forward-slash variant
        $forwardSlash = $RepoRoot -replace "\\", "/"
        $escapedFwd = [regex]::Escape($forwardSlash)
        $normalized = $normalized -replace $escapedFwd, "<REPO>"
    }

    # 4. Timestamps: replace common patterns
    # ISO format: 2025-12-19T10:30:45
    $normalized = $normalized -replace "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", "<TIMESTAMP>"
    # Unix timestamp: 1734567890
    $normalized = $normalized -replace "\b\d{10}\b", "<TIMESTAMP>"

    # 5. Trailing newlines: ensure exactly one
    $normalized = $normalized.TrimEnd("`n") + "`n"

    return $normalized
}

function Get-UnifiedDiff {
    param(
        [string]$Expected,
        [string]$Actual,
        [string]$Label = "fixture"
    )

    $expectedLines = $Expected -split "`n"
    $actualLines = $Actual -split "`n"

    $diff = [System.Text.StringBuilder]::new()
    [void]$diff.AppendLine("--- expected/$Label")
    [void]$diff.AppendLine("+++ actual/$Label")

    $maxLines = [Math]::Max($expectedLines.Count, $actualLines.Count)
    $contextSize = 3
    $diffRanges = @()

    # Find diff ranges
    for ($i = 0; $i -lt $maxLines; $i++) {
        $exp = if ($i -lt $expectedLines.Count) { $expectedLines[$i] } else { $null }
        $act = if ($i -lt $actualLines.Count) { $actualLines[$i] } else { $null }

        if ($exp -ne $act) {
            $diffRanges += $i
        }
    }

    if ($diffRanges.Count -eq 0) {
        [void]$diff.AppendLine("(no differences)")
        return $diff.ToString()
    }

    # Output diffs with context
    $shown = @{}
    foreach ($diffLine in $diffRanges) {
        $start = [Math]::Max(0, $diffLine - $contextSize)
        $end = [Math]::Min($maxLines - 1, $diffLine + $contextSize)

        for ($i = $start; $i -le $end; $i++) {
            if ($shown.ContainsKey($i)) { continue }
            $shown[$i] = $true

            $exp = if ($i -lt $expectedLines.Count) { $expectedLines[$i] } else { $null }
            $act = if ($i -lt $actualLines.Count) { $actualLines[$i] } else { $null }

            $lineNum = $i + 1
            if ($exp -eq $act) {
                [void]$diff.AppendLine(" $lineNum : $exp")
            } else {
                if ($null -ne $exp) {
                    [void]$diff.AppendLine("-$lineNum : $exp")
                }
                if ($null -ne $act) {
                    [void]$diff.AppendLine("+$lineNum : $act")
                }
            }
        }
        [void]$diff.AppendLine("...")
    }

    return $diff.ToString()
}

function Assert-GoldenMatch {
    param(
        [string]$FixtureName,
        [string]$ActualFrame,
        [string]$RepoRoot = "",
        [string]$FixturesPath = ""
    )

    if (-not $FixturesPath) {
        $FixturesPath = Join-Path $PSScriptRoot "fixtures"
    }

    $goldenPath = Join-Path $FixturesPath "golden\$FixtureName"
    $actualDir = Join-Path $FixturesPath "_actual"
    $actualPath = Join-Path $actualDir $FixtureName

    # Normalize actual frame
    $normalizedActual = Normalize-Frame -Frame $ActualFrame -RepoRoot $RepoRoot

    # Ensure _actual directory exists
    if (-not (Test-Path $actualDir)) {
        New-Item -ItemType Directory -Path $actualDir -Force | Out-Null
    }

    # Always write actual output for inspection
    Set-Content -Path $actualPath -Value $normalizedActual -NoNewline -Encoding UTF8

    # Check if golden fixture exists
    if (-not (Test-Path $goldenPath)) {
        Write-Host "FIXTURE NOT FOUND: $goldenPath" -ForegroundColor Yellow
        Write-Host "Actual output written to: $actualPath" -ForegroundColor Yellow
        Write-Host "To create fixture: copy _actual\$FixtureName to golden\$FixtureName" -ForegroundColor Cyan
        return @{
            Pass = $false
            Reason = "FIXTURE_NOT_FOUND"
            ActualPath = $actualPath
        }
    }

    # Load and normalize expected
    $expectedRaw = Get-Content -Path $goldenPath -Raw -Encoding UTF8
    $normalizedExpected = Normalize-Frame -Frame $expectedRaw -RepoRoot $RepoRoot

    # Compare
    if ($normalizedExpected -eq $normalizedActual) {
        return @{
            Pass = $true
            Reason = "MATCH"
        }
    }

    # Mismatch - print unified diff
    Write-Host ""
    Write-Host "FIXTURE MISMATCH: $FixtureName" -ForegroundColor Red
    Write-Host ""
    $diff = Get-UnifiedDiff -Expected $normalizedExpected -Actual $normalizedActual -Label $FixtureName
    Write-Host $diff -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actual output written to: $actualPath" -ForegroundColor Cyan
    Write-Host ""

    return @{
        Pass = $false
        Reason = "MISMATCH"
        Diff = $diff
        ActualPath = $actualPath
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-GoldenCapture',
    'Write-ToBuffer',
    'Set-BufferPosition',
    'Get-CapturedFrame',
    'Stop-GoldenCapture',
    'Normalize-Frame',
    'Get-UnifiedDiff',
    'Assert-GoldenMatch'
)
