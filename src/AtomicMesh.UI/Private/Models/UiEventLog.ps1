class UiEventLog {
    [System.Collections.Generic.List[UiEvent]]$Events
    [int]$Capacity

    UiEventLog() {
        $this.Capacity = 200
        $this.Events = [System.Collections.Generic.List[UiEvent]]::new()
    }

    UiEventLog([int]$capacity) {
        $this.Capacity = if ($capacity -gt 0) { $capacity } else { 200 }
        $this.Events = [System.Collections.Generic.List[UiEvent]]::new()
    }

    [void]Add([UiEvent]$event) {
        if (-not $event) { return }
        $this.Events.Add($event)
        while ($this.Events.Count -gt $this.Capacity) {
            $this.Events.RemoveAt(0)
        }
    }

    [UiEvent[]]GetAll() {
        return $this.Events.ToArray()
    }
}
