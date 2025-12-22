if (-not (Get-Command Fit-Text -ErrorAction SilentlyContinue)) {
    function Fit-Text {
        param([string]$Text, [int]$Width)
        if (-not $Text) { return "" }
        if ($Text.Length -le $Width) { return $Text }
        if ($Width -le 3) { return $Text.Substring(0, $Width) }
        return $Text.Substring(0, $Width - 3) + "..."
    }
}

function Get-HistoryRows {
    param(
        $State,
        [string]$Subview
    )
    $rows = @()
    if (-not $State) { return $rows }
    try {
        $snap = $State.Cache.LastSnapshot
        if (-not $snap) { return $rows }
        switch ($Subview) {
            "TASKS" {
                # Merge active (now) + pending (next) + history (past)
                function Add-Row {
                    param($list, [string]$status, [string]$lane, [string]$desc, [string]$color = "", $notes = $null)
                    $laneSafe = if ($lane) { [string]$lane } else { "-" }
                    $descSafe = if ($desc) { [string]$desc } else { "" }
                    $list += @{
                        worker = $laneSafe
                        content = $descSafe
                        status = $status
                        color = $color
                        notes = $notes
                    }
                    return ,$list
                }

                # Active
                if ($snap.ActiveTask) {
                    $lane = if ($snap.ActiveTask.lane) { $snap.ActiveTask.lane } elseif ($snap.ActiveTask.type) { $snap.ActiveTask.type } else { "—" }
                    $rows = Add-Row -list $rows -status "RUNNING" -lane $lane -desc $snap.ActiveTask.desc -color "Green"
                }

                # Pending (use as many as fit the left pane)
                $pending = @()
                try { if ($snap.PendingTasks) { $pending = @($snap.PendingTasks) } } catch {}
                foreach ($task in $pending) {
                    $lane = if ($task.lane) { $task.lane } elseif ($task.type) { $task.type } else { "—" }
                    $rows = Add-Row -list $rows -status "PENDING" -lane $lane -desc $task.desc -color "Yellow"
                }

                # History/audit (past) - fill remaining
                $history = @()
                try { if ($snap.HistoryTasks) { $history = @($snap.HistoryTasks) } } catch {}
                foreach ($h in $history) {
                    $lane = if ($h.lane) { $h.lane } else { "SYS" }
                    $status = if ($h.action) { [string]$h.action } elseif ($h.status) { [string]$h.status } else { "DONE" }
                    $desc = if ($h.desc) { [string]$h.desc } else { "" }
                    # Format time if created_at present
                    $timeTxt = ""
                    try {
                        if ($h.created_at) {
                            $dt = [DateTimeOffset]::FromUnixTimeSeconds([long]$h.created_at).ToLocalTime()
                            $timeTxt = $dt.ToString("HH:mm")
                        }
                    } catch {}
                    $rows = Add-Row -list $rows -status $(if ($timeTxt) { $timeTxt } else { $status }) -lane $lane -desc $desc -color "DarkGray" -notes $status
                }
            }
            "DOCS"  { if ($snap.HistoryDocs)  { $rows = @($snap.HistoryDocs) } }
            "SHIP"  { if ($snap.HistoryShip)  { $rows = @($snap.HistoryShip) } }
            default { }
        }
    } catch { }
    return $rows
}

function Render-HistoryOverlay {
    param(
        $State,
        [int]$StartRow = 0,
        [int]$BottomRow = -1  # Frame-fill target (like Render-Plan)
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    $state = if ($State) { $State } else { [UiState]::new() }
    $subview = if ($state.HistorySubview) { $state.HistorySubview } else { "TASKS" }
    $detailsVisible = $state.HistoryDetailsVisible

    # Get dimensions
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $Half = [Math]::Floor($W / 2)
    $ContentWidthL = $Half - 4
    $ContentWidthR = $W - $Half - 4
    $R = $StartRow

    # Border top
    Draw-Border -Row $R -HalfWidth $Half
    $R++

    # Header row
    $leftLabel = "HISTORY VIEW"
    $rightHint = if ($detailsVisible) { "[DETAILS VISIBLE] Esc=close" } else { "Enter=toggle details" }
    $padL = $ContentWidthL - $leftLabel.Length - $rightHint.Length
    if ($padL -lt 1) { $padL = 1 }

    TryWriteAt -Row $R -Col 0 -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col 2 -Text $leftLabel -Color "Cyan" | Out-Null
    $hintCol = 2 + $leftLabel.Length + $padL
    TryWriteAt -Row $R -Col $hintCol -Text $rightHint -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($Half - 2) -Text " |" -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col $Half -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($Half + 2) -Text "".PadRight($ContentWidthR) -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($W - 2) -Text " |" -Color "DarkGray" | Out-Null
    $R++

    # Border after header
    Draw-Border -Row $R -HalfWidth $Half
    $R++

    # Column headers
    $headerWorkerWidth = 8
    $headerStatusWidth = 8
    $headerContentWidth = $ContentWidthL - (1 + 1 + $headerWorkerWidth + 1 + $headerStatusWidth)
    if ($headerContentWidth -lt 0) { $headerContentWidth = 0 }
    $contentLabel = "CONTENT"
    $contentPadLeft = [Math]::Max(1, [Math]::Floor(($headerContentWidth - $contentLabel.Length) / 2))
    $contentPadRight = $headerContentWidth - $contentPadLeft - $contentLabel.Length
    if ($contentPadRight -lt 0) { $contentPadRight = 0 }
    $headerLeft = " WORKER".PadRight($headerWorkerWidth + 2) +
        (" " * $contentPadLeft) + $contentLabel + (" " * $contentPadRight) + " " +
        "HE".PadLeft($headerStatusWidth)
    $pipelineLabel = "PIPELINE"
    Print-Row -Row $R -LeftTxt $headerLeft -RightTxt $pipelineLabel -HalfWidth $Half -ColorL "DarkCyan" -ColorR "Cyan"
    $R++

    # Soft trim helper to avoid mid-word cutoffs
    function Soft-Trim {
        param([string]$text, [int]$width)
        if ($width -le 0) { return "" }
        if (-not $text) { return "" }
        if ($text.Length -le $width) { return $text }
        $candidate = $text.Substring(0, $width)
        $lastSpace = $candidate.LastIndexOf(" ")
        if ($lastSpace -gt 0) {
            $candidate = $candidate.Substring(0, $lastSpace)
        }
        return $candidate
    }

    # Resolve history rows from snapshot (read-only)
    $rows = Get-HistoryRows -State $state -Subview $subview

    $selectedIdx = if ($state.HistorySelectedRow -ge 0) { $state.HistorySelectedRow } else { 0 }
    $maxRows = 5
    if ($BottomRow -gt 0) {
        $maxRows = [Math]::Max(1, $BottomRow - ($StartRow + 4))
    }
    $maxRows = [Math]::Min(10, $maxRows)  # cap to 10 rows but use available height
    if ($rows -and $rows.Count -gt 0) {
        $maxSelectable = $rows.Count - 1
        if ($selectedIdx -gt $maxSelectable) { $selectedIdx = $maxSelectable; $state.HistorySelectedRow = $selectedIdx }
    } else {
        $selectedIdx = 0
        $state.HistorySelectedRow = 0
    }
    if (-not $rows -or $rows.Count -eq 0) {
        $emptyMsg = switch ($subview) {
            "TASKS" { "(no history data)" }
            "DOCS"  { "(no docs data)" }
            "SHIP"  { "(no ship data)" }
        }
        Print-Row -Row $R -LeftTxt $emptyMsg -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
        $R++
    } else {
        $startIdx = if ($state.HistoryScrollOffset -ge 0) { $state.HistoryScrollOffset } else { 0 }
        if ($startIdx -gt [Math]::Max(0, $rows.Count - 1)) { $startIdx = 0 }
        $displayRows = $rows | Select-Object -Skip $startIdx -First $maxRows
        for ($i = 0; $i -lt $displayRows.Count; $i++) {
            $row = $displayRows[$i]
            $globalIdx = $startIdx + $i
            $prefix = if ($globalIdx -eq $selectedIdx) { ">" } else { " " }
            $rightText = ""
            $workerWidth = 8
            $statusWidth = 8
            # prefix + space + worker + space + content + space + status
            $contentWidthAvail = $ContentWidthL - (1 + 1 + $workerWidth + 1 + $statusWidth)
            if ($contentWidthAvail -lt 0) { $contentWidthAvail = 0 }
            $text = ""
            $colorL = if ($row.color) { [string]$row.color } elseif ($i -eq $selectedIdx) { "White" } else { "Gray" }
            switch ($subview) {
                "TASKS" {
                    $shortContent = if ($row.content) { [string]$row.content } else { "" }
                    if ($shortContent -match "(?i)\s+DoD:") {
                        $shortContent = ($shortContent -split "(?i)\s+DoD:", 2)[0]
                    }
                    $shortContent = $shortContent.TrimEnd(" ","-","—")
                    $worker = Fit-Text -Text $(if ($row.worker) { [string]$row.worker } else { "-" }) -Width 8
                    $content = Soft-Trim -text $shortContent -width $contentWidthAvail
                    $statusRaw = if ($row.status) { [string]$row.status } else { "" }
                    $status = $statusRaw.PadRight($statusWidth).Substring(0, $statusWidth)
                    $text = "$prefix " + $worker.PadRight($workerWidth) + " " + $content.PadRight($contentWidthAvail) + " " + $status.PadLeft($statusWidth)
                    if ($i -eq $selectedIdx) {
                        $rightText = if ($row.content) { [string]$row.content } else { "" }
                    }
                }
                "DOCS" {
                    $file = Fit-Text -Text $(if ($row.file) { [string]$row.file } else { "-" }) -Width 8
                    $desc = Fit-Text -Text $(if ($row.desc) { [string]$row.desc } else { "" }) -Width ($ContentWidthL - 10)
                    $text = "$prefix $file $desc"
                    if ($i -eq $selectedIdx) {
                        $rightText = if ($row.desc) { [string]$row.desc } else { "" }
                    }
                }
                "SHIP" {
                    $artifact = Fit-Text -Text $(if ($row.artifact) { [string]$row.artifact } else { "-" }) -Width 8
                    $version = Fit-Text -Text $(if ($row.version) { [string]$row.version } else { "" }) -Width ($ContentWidthL - 10)
                    $text = "$prefix $artifact $version"
                }
            }
            $colorL = if ($row.color) { [string]$row.color } elseif ($i -eq $selectedIdx) { "White" } else { "Gray" }
            Print-Row -Row $R -LeftTxt $text -RightTxt "" -HalfWidth $Half -ColorL $colorL -ColorR "DarkGray"
            $R++
        }
    }

    # Fixed right-pane area (2 rows below header) showing selected item's full content
    $rightStart = $StartRow + 4  # header row 0-3; content starts at StartRow+4 after headers/borders
    $detailLines = @()
    $availableDetailRows = if ($BottomRow -gt 0) { [Math]::Max(0, $BottomRow - $rightStart) } else { 2 }
    if ($availableDetailRows -lt 1) { $availableDetailRows = 2 }
    if ($rows -and $rows.Count -gt $selectedIdx) {
        $sel = $rows[$selectedIdx]
        $fullRaw = if ($sel.content) { [string]$sel.content } else { "" }

        # Prefer splitting on DoD first, then pipes/semicolons into logical lines
        $segments = @()
        $primaryLine = ""
        $fullTrim = $fullRaw.Trim()
        $dodIdx = $fullTrim.IndexOf("DoD:", [System.StringComparison]::OrdinalIgnoreCase)
        if ($dodIdx -gt 0) {
            $firstPart = $fullTrim.Substring(0, $dodIdx).Trim().TrimEnd("-", "—", "–", "|", ";")
            $rest = $fullTrim.Substring($dodIdx).Trim()
            $primaryLine = $firstPart
            if ($firstPart) { $segments += $firstPart }
            $splitRest = $rest -split "[\|;]"  # split on pipe or semicolon
            foreach ($seg in $splitRest) {
                $s = $seg.Trim().TrimStart("-","—","–")
                if ($s) { $segments += $s }
            }
        }
        else {
            $splitSimple = $fullTrim -split "[\|;]"
            foreach ($seg in $splitSimple) {
                $s = $seg.Trim().TrimStart("-","—","–")
                if ($s) { $segments += $s }
            }
            if (-not $primaryLine -and $segments.Count -gt 0) { $primaryLine = $segments[0] }
        }
        if (-not $primaryLine) { $primaryLine = $fullTrim }
        if ($segments.Count -eq 0 -and $fullTrim) { $segments = @($fullTrim) }
        if ($primaryLine -and ($segments.Count -eq 0 -or $segments[0] -ne $primaryLine)) {
            $segments = @($primaryLine) + $segments
        }

        foreach ($seg in $segments) {
            $startOffset = 0
            $segLen = $seg.Length
            while ($startOffset -lt $segLen -or $startOffset -eq 0) {
                $len = [Math]::Min($ContentWidthR, [Math]::Max(0, $segLen - $startOffset))
                $chunk = if ($len -gt 0) { $seg.Substring($startOffset, $len) } else { "" }
                $detailLines += $chunk.PadRight($ContentWidthR)
                $startOffset += $ContentWidthR
                if ($detailLines.Count -ge $availableDetailRows) { break }
                if ($len -eq 0) { break }
            }
            if ($detailLines.Count -ge $availableDetailRows) { break }
        }
    }
    while ($detailLines.Count -lt $availableDetailRows) {
        $detailLines += ("".PadRight($ContentWidthR))
    }
    for ($idx = 0; $idx -lt $availableDetailRows; $idx++) {
        $rowNum = $rightStart + $idx
        TryWriteAt -Row $rowNum -Col $Half -Text "| " -Color "DarkGray" | Out-Null
        TryWriteAt -Row $rowNum -Col ($Half + 2) -Text $detailLines[$idx] -Color "White" | Out-Null
        TryWriteAt -Row $rowNum -Col ($W - 2) -Text " |" -Color "DarkGray" | Out-Null
    }
    $R = [Math]::Max($R, $rightStart + $availableDetailRows)

    # Frame-fill: Clear remaining rows to prevent bleed-through from underlying page
    if ($BottomRow -gt 0) {
        while ($R -lt $BottomRow) {
            Print-Row -Row $R -LeftTxt "" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
            $R++
        }
    }
}
