# NOTE: Using [object] to avoid type mismatch on module reload
class UiEventLog {
    [System.Collections.ArrayList]$Events
    [int]$Capacity

    UiEventLog() {
        $this.Capacity = 200
        $this.Events = [System.Collections.ArrayList]::new()
    }

    UiEventLog([int]$capacity) {
        $this.Capacity = if ($capacity -gt 0) { $capacity } else { 200 }
        $this.Events = [System.Collections.ArrayList]::new()
    }

    [void]Add([object]$event) {
        if (-not $event) { return }
        $this.Events.Add($event) | Out-Null
        while ($this.Events.Count -gt $this.Capacity) {
            $this.Events.RemoveAt(0)
        }
    }

    [object[]]GetAll() {
        return $this.Events.ToArray()
    }
}
