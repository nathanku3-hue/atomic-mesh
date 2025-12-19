function Render-StatsOverlay {
    param(
        $State,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    if (-not $State) { return }

    $window = $Host.UI.RawUI.WindowSize
    $height = if ($window.Height -gt 0) { $window.Height } else { 24 }
    $w = if ($Width -gt 0) { $Width } else { 80 }

    $row = 2
    $title = "Render Stats (F6 to close)"
    if ($title.Length -gt $w) { $title = $title.Substring(0, $w) }
    TryWriteAt -Row $row -Col 0 -Text $title -Color "DarkCyan" | Out-Null
    $row++

    # Calculate rates
    $elapsed = ($State.NowUtc - [datetime]::MinValue).TotalSeconds
    $rps = if ($elapsed -gt 0) { [math]::Round($State.RenderFrames / $elapsed, 2) } else { 0 }
    $dps = if ($elapsed -gt 0) { [math]::Round($State.DataRefreshes / $elapsed, 2) } else { 0 }

    $lines = @(
        "Render Frames:   $($State.RenderFrames)"
        "Skipped Frames:  $($State.SkippedFrames)"
        "Data Refreshes:  $($State.DataRefreshes)"
        ""
        "Renders/sec:     $rps"
        "Data ticks/sec:  $dps"
        ""
        "IsDirty:         $($State.IsDirty)"
        "DirtyReason:     $($State.DirtyReason)"
        "AutoRefresh:     $($State.AutoRefreshEnabled)"
        ""
        "Window:          $($State.LastWidth) x $($State.LastHeight)"
        "SnapshotHash:    $(if ($State.LastSnapshotHash) { $State.LastSnapshotHash.Substring(0, [Math]::Min(40, $State.LastSnapshotHash.Length)) + '...' } else { '(none)' })"
    )

    $maxRows = [Math]::Max(1, $height - 6)
    $count = 0
    foreach ($line in $lines) {
        if ($count -ge $maxRows) { break }
        $display = if ($line.Length -gt $w) { $line.Substring(0, $w) } else { $line }
        TryWriteAt -Row $row -Col 0 -Text $display -Color "Gray" | Out-Null
        $row++
        $count++
    }
}
