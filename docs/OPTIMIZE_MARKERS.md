# Optimize Stage Markers

The Optimize stage in the pipeline checks task notes for entropy proof markers. These markers indicate that a task has been reviewed for optimization opportunities.

## Accepted Markers

The following patterns in task notes will mark a task as "optimized":

| Marker | Purpose |
|--------|---------|
| `Entropy Check: Passed` | Standard optimization verification |
| `OPTIMIZATION WAIVED` | Explicitly skipped (approved) |
| `CAPTAIN_OVERRIDE: ENTROPY` | Manual override by authorized user |

## Matching Rules

- Patterns are **case-insensitive**
- Whitespace between words is flexible (e.g., `Entropy Check:  Passed` works)
- Markers must appear in the task's `notes` field
- Partial matches do NOT count (e.g., `Entropy Check: Failed` is NOT a match)

## Stage Color Logic

| Color | Condition |
|-------|-----------|
| GREEN | At least one active task has an accepted marker |
| YELLOW | Active tasks exist but none have markers |
| GRAY | No active tasks, or Work stage is blocked |

## Pipeline Hint

When Optimize is YELLOW, the "Next:" hint suggests `/simplify <task-id>` where `<task-id>` is the first task without an entropy marker.

## Implementation

Detection is performed in `tools/snapshot.py`:

```python
entropy_patterns = [
    r"Entropy Check:\s*Passed",
    r"OPTIMIZATION WAIVED",
    r"CAPTAIN_OVERRIDE:\s*ENTROPY"
]
```

The snapshot returns:
- `FirstUnoptimizedTaskId` - First task needing optimization
- `HasAnyOptimized` - True if any task has a marker
- `OptimizeTotalTasks` - Count of active tasks
