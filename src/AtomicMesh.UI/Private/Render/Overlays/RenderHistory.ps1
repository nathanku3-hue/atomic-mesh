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

                # Pending (top 3)
                $pending = @()
                try { if ($snap.PendingTasks) { $pending = @($snap.PendingTasks) } } catch {}
                foreach ($task in ($pending | Select-Object -First 3)) {
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

    # Header: "HISTORY VIEW (F2/Esc to exit)" on left, details hint on right
    $leftLabel = "HISTORY VIEW"
    $leftHint = "(F2/Esc to exit)"
    $padL = $ContentWidthL - $leftLabel.Length - $leftHint.Length
    if ($padL -lt 0) { $padL = 0 }

    TryWriteAt -Row $R -Col 0 -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col 2 -Text $leftLabel -Color "Cyan" | Out-Null
    $hintCol = 2 + $leftLabel.Length + $padL
    TryWriteAt -Row $R -Col $hintCol -Text $leftHint -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($Half - 2) -Text " |" -Color "DarkGray" | Out-Null

    # Right panel: show details hint or details pane indicator
    $rightHint = if ($detailsVisible) { "[DETAILS VISIBLE] Esc=close" } else { "Enter=toggle details" }
    TryWriteAt -Row $R -Col $Half -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($Half + 2) -Text $rightHint.PadRight($ContentWidthR) -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($W - 2) -Text " |" -Color "DarkGray" | Out-Null
    $R++

    # Border after header
    Draw-Border -Row $R -HalfWidth $Half
    $R++

    # Column headers vary by subview (golden contract)
    $headerLeft = ""
    $pipelineLabel = "PIPELINE"
    switch ($subview) {
        "TASKS" {
            $headerLeft = " WORKER      CONTENT              HE"
        }
        "DOCS" {
            $headerLeft = " FILE        DESCRIPTION          ST"
        }
        "SHIP" {
            $headerLeft = " ARTIFACT    VERSION              ST"
        }
    }
    if ($headerLeft.Length -gt $ContentWidthL) {
        $headerLeft = $headerLeft.Substring(0, $ContentWidthL)
    }
    Print-Row -Row $R -LeftTxt $headerLeft -RightTxt $pipelineLabel -HalfWidth $Half -ColorL "DarkCyan" -ColorR "Cyan"
    $R++

    # Resolve history rows from snapshot (read-only)
    $rows = Get-HistoryRows -State $state -Subview $subview

    $selectedIdx = if ($state.HistorySelectedRow -ge 0) { $state.HistorySelectedRow } else { 0 }
    $maxRows = 5
    if (-not $rows -or $rows.Count -eq 0) {
        $emptyMsg = switch ($subview) {
            "TASKS" { "(no history data)" }
            "DOCS"  { "(no docs data)" }
            "SHIP"  { "(no ship data)" }
        }
        Print-Row -Row $R -LeftTxt $emptyMsg -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
        $R++
    } else {
        $displayRows = $rows | Select-Object -First $maxRows
        for ($i = 0; $i -lt $displayRows.Count; $i++) {
            $row = $displayRows[$i]
            $prefix = if ($i -eq $selectedIdx) { ">" } else { " " }
            $text = ""
            switch ($subview) {
                "TASKS" {
                    $worker = Fit-Text -Text (if ($row.worker) { [string]$row.worker } else { "-" }) -Width 8
                    $content = Fit-Text -Text (if ($row.content) { [string]$row.content } else { "" }) -Width ($ContentWidthL - 12)
                    $status = Fit-Text -Text (if ($row.status) { [string]$row.status } else { "" }) -Width 8
                    $text = "$prefix $worker $content $status"
                }
                "DOCS" {
                    $file = Fit-Text -Text (if ($row.file) { [string]$row.file } else { "-" }) -Width 8
                    $desc = Fit-Text -Text (if ($row.desc) { [string]$row.desc } else { "" }) -Width ($ContentWidthL - 10)
                    $text = "$prefix $file $desc"
                }
                "SHIP" {
                    $artifact = Fit-Text -Text (if ($row.artifact) { [string]$row.artifact } else { "-" }) -Width 8
                    $version = Fit-Text -Text (if ($row.version) { [string]$row.version } else { "" }) -Width ($ContentWidthL - 10)
                    $text = "$prefix $artifact $version"
                }
            }
            $colorL = if ($row.color) { [string]$row.color } elseif ($i -eq $selectedIdx) { "White" } else { "Gray" }
            Print-Row -Row $R -LeftTxt $text -RightTxt "" -HalfWidth $Half -ColorL $colorL -ColorR "DarkGray"
            $R++
        }
    }

    # If details visible, render a details pane below
    if ($detailsVisible) {
        Print-Row -Row $R -LeftTxt "" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
        $R++

        # Details header
        Print-Row -Row $R -LeftTxt "--- TASK DETAILS ---" -RightTxt "" -HalfWidth $Half -ColorL "Yellow" -ColorR "DarkGray"
        $R++

        $detailRow = $null
        if ($rows -and $rows.Count -gt $selectedIdx) {
            $detailRow = $rows[$selectedIdx]
        }
        if ($detailRow) {
            switch ($subview) {
                "TASKS" {
                    $worker = if ($detailRow.worker) { [string]$detailRow.worker } else { "(none)" }
                    $status = if ($detailRow.status) { [string]$detailRow.status } else { "-" }
                    $notes = if ($detailRow.notes) { [string]$detailRow.notes } else { "" }
                    Print-Row -Row $R -LeftTxt "Worker: $worker" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"; $R++
                    Print-Row -Row $R -LeftTxt "Status: $status" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"; $R++
                    Print-Row -Row $R -LeftTxt (Fit-Text -Text $notes -Width ($Half - 4)) -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"; $R++
                }
                "DOCS" {
                    $file = if ($detailRow.file) { [string]$detailRow.file } else { "(none)" }
                    $state = if ($detailRow.status) { [string]$detailRow.status } else { "-" }
                    $summary = if ($detailRow.desc) { [string]$detailRow.desc } else { "" }
                    Print-Row -Row $R -LeftTxt "Doc: $file" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"; $R++
                    Print-Row -Row $R -LeftTxt "Status: $state" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"; $R++
                    Print-Row -Row $R -LeftTxt (Fit-Text -Text $summary -Width ($Half - 4)) -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"; $R++
                }
                "SHIP" {
                    $artifact = if ($detailRow.artifact) { [string]$detailRow.artifact } else { "(none)" }
                    $version = if ($detailRow.version) { [string]$detailRow.version } else { "-" }
                    $notes = if ($detailRow.notes) { [string]$detailRow.notes } else { "" }
                    Print-Row -Row $R -LeftTxt "Artifact: $artifact" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"; $R++
                    Print-Row -Row $R -LeftTxt "Version: $version" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"; $R++
                    Print-Row -Row $R -LeftTxt (Fit-Text -Text $notes -Width ($Half - 4)) -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"; $R++
                }
            }
        } else {
            Print-Row -Row $R -LeftTxt "No selection" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"; $R++
        }

        Print-Row -Row $R -LeftTxt "Press ESC to close details" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
        $R++
    }

    # Frame-fill: Clear remaining rows to prevent bleed-through from underlying page
    if ($BottomRow -gt 0) {
        while ($R -lt $BottomRow) {
            Print-Row -Row $R -LeftTxt "" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
            $R++
        }
    }
}
