function Invoke-KeyRouter {
    param(
        [ConsoleKeyInfo]$KeyInfo,
        [UiState]$State
    )

    if (-not $KeyInfo -or -not $State) { return "noop" }

    switch ($KeyInfo.Key) {
        'Tab' {
            # Golden Contract: Tab behavior depends on context
            if ($State.OverlayMode -eq "History") {
                # In History overlay: cycle subviews (TASKS -> DOCS -> SHIP)
                $State.CycleHistorySubview()
                return "historyTab"
            }
            elseif ($State.InputBuffer.Length -eq 0) {
                # Not in overlay, empty input: cycle mode ring (OPS -> PLAN -> RUN -> SHIP)
                $State.CycleMode()
                return "mode"
            }
            return "noop"
        }
        'Enter' {
            # Golden Contract: Enter toggles details pane in History overlay
            if ($State.OverlayMode -eq "History") {
                $State.ToggleHistoryDetails()
                return "historyDetails"
            }
            return "noop"
        }
        'F2' {
            # Golden Contract: F2 toggles HISTORY overlay
            $State.ToggleOverlay("History")
            return "overlay"
        }
        # F4 intentionally omitted - golden doesn't have StreamDetails overlay
        'Escape' {
            # Golden Contract: ESC PRIORITY
            # 1. If in History with details visible -> close details first (NOT overlay)
            # 2. If in History without details -> close overlay
            # 3. If input buffer has content -> clear buffer
            if ($State.OverlayMode -eq "History") {
                if ($State.HistoryDetailsVisible) {
                    # ESC Priority: close details pane first
                    $State.CloseHistoryDetails()
                    return "historyDetails"
                }
                else {
                    # Close overlay
                    $State.OverlayMode = "None"
                    $State.MarkDirty("overlay")
                    return "overlay"
                }
            }
            elseif ($State.InputBuffer.Length -gt 0) {
                $State.InputBuffer = ""
                $State.MarkDirty("input")
                return "input"
            }
            return "noop"
        }
        default {
            return "noop"
        }
    }
}
