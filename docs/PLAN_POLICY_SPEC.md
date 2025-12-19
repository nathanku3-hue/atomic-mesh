# PLAN Policy Specification

> Version: 1.0
> Status: ACTIVE
> Last Updated: 2025-12-19

---

## 1. Source of Truth

| Component | Role |
|-----------|------|
| Tasks DB (`tasks` table) | **Sole execution source** — all `/go` operations read from here |
| Draft plan file (`docs/PLANS/draft_*.md`) | Staging area only — has no effect on execution |
| `/accept-plan` | Hydration gate — moves draft into tasks DB |

**Invariant:** Draft file changes NEVER affect execution until `/accept-plan` hydrates DB.

---

## 2. Command Flow Rules

### 2.1 When `/accept-plan` is MANDATORY

| Condition | Behavior |
|-----------|----------|
| No accepted plan loaded | `/go` must return friendly message, not crash |
| Tasks DB has zero tasks | `/go` must return friendly message, not crash |

**Required `/go` response (no tasks):**
```
No tasks loaded. Use /accept-plan to load a plan first.
```

### 2.2 When `/accept-plan` is NOT mandatory

| Condition | Behavior |
|-----------|----------|
| Tasks exist in DB | `/go` runs against last accepted plan |
| Draft exists/changed after last accept | Warning only, not a blocker |

**Invariant:** Draft drift is informational, never blocks execution.

---

## 3. "Next:" Line Rules (Exact Strings)

The PLAN screen must display exactly ONE `Next:` line based on state:

| State | Next Line | Notes |
|-------|-----------|-------|
| No draft file exists | `Next: /draft-plan` | Creates plan file |
| Draft exists, DB has no tasks | `Next: /accept-plan` | Loads tasks into DB |
| Draft exists, DB has no accepted plan | `Next: /accept-plan` | Loads tasks into DB |
| Accepted plan loaded + tasks exist | `Next: /go` | Pick next task |
| Draft changed since accept + tasks exist | `Next: /go` | Continue with accepted plan |

### 3.1 Drift Warning

When draft has changed since last `/accept-plan` AND tasks exist in DB, append warning line:

```
Next: /go
Draft changed — /accept-plan to load new tasks
```

**Test assertions:**
```powershell
# MUST match exactly (regex)
$NextLine -match '^Next: /(draft-plan|accept-plan|go)$'

# Drift warning MUST appear on separate line
$DriftWarning -eq 'Draft changed — /accept-plan to load new tasks'
```

---

## 4. Lane Row Formatting

### 4.1 Color-Only Rule

**NEVER** print status words in lane rows:
- ❌ `RUNNING`
- ❌ `OK`
- ❌ `BLOCKED`
- ❌ `IDLE`

Lane health is communicated via:
1. Progress bar tokens (`■□`)
2. Health dot color (●)
3. Numeric counters

### 4.2 Work Lanes (BACKEND, FRONTEND)

**Format:**
```
<LANE> <tokens> A:<active> D:<done>/<total> <summary> <dot>
```

**Examples:**
```
BACKEND  ■■□□□ A:1 D:2/5 Implementing auth ●
FRONTEND ■■■□□ A:0 D:3/5 Styling complete  ●
```

**Unknown Accounting Rule:**
If `total == 0` AND (`active > 0` OR `pending > 0`):
```
BACKEND  ■□□□□ A:2 D:— Task in progress ●
```
Use `D:—` (em-dash) to indicate unknown accounting.

### 4.3 Audit Lanes (QA/AUDIT, LIBRARIAN)

**Format:**
```
<LANE> <tokens> <summary> <dot>
```

**Examples:**
```
QA/AUDIT  ■■■■■ All verified    ●
LIBRARIAN ■■■■■ Library clean   ●
```

**No A:/D: counters on audit lanes.**

---

## 5. Health Dot Rules

### 5.1 Placement

- One dot per lane row
- Fixed column position near right divider
- Unicode: `●` (U+25CF BLACK CIRCLE)

### 5.2 Color Semantics

| Color | ANSI | Meaning |
|-------|------|---------|
| Green | `[32m` | Healthy, high confidence |
| Yellow | `[33m` | Degraded, unknown, non-blocking issue |
| Red | `[31m` | Blocked, failed, low confidence |

### 5.3 Color Assignment Rules

| Condition | Dot Color |
|-----------|-----------|
| All tasks done, no failures | Green |
| Active work in progress, no issues | Green |
| Unknown accounting (`D:—`) | Yellow |
| Pending review / awaiting input | Yellow |
| Any task blocked | Red |
| Any task failed | Red |
| Lane has error state | Red |

---

## 6. Test Assertions

### 6.1 PowerShell Test Helpers

```powershell
# Assert no status words in lane output
function Assert-NoStatusWords {
    param([string]$LaneOutput)
    $forbidden = @('RUNNING', 'OK', 'BLOCKED', 'IDLE')
    foreach ($word in $forbidden) {
        if ($LaneOutput -match "\b$word\b") {
            throw "Lane contains forbidden status word: $word"
        }
    }
}

# Assert correct Next: line
function Assert-NextLine {
    param(
        [string]$Output,
        [ValidateSet('draft-plan','accept-plan','go')]
        [string]$Expected
    )
    if ($Output -notmatch "Next: /$Expected") {
        throw "Expected 'Next: /$Expected' but not found"
    }
}

# Assert health dot present
function Assert-HealthDot {
    param([string]$LaneRow)
    if ($LaneRow -notmatch '●') {
        throw "Lane row missing health dot"
    }
}

# Assert work lane format
function Assert-WorkLaneFormat {
    param([string]$LaneRow)
    # Pattern: LANE tokens A:n D:n/n|— summary dot
    $pattern = '^(BACKEND|FRONTEND)\s+[■□]+\s+A:\d+\s+D:(\d+/\d+|—)\s+.+\s+●$'
    if ($LaneRow -notmatch $pattern) {
        throw "Work lane format invalid: $LaneRow"
    }
}

# Assert audit lane format
function Assert-AuditLaneFormat {
    param([string]$LaneRow)
    # Pattern: LANE tokens summary dot (no A:/D:)
    $pattern = '^(QA/AUDIT|LIBRARIAN)\s+[■□]+\s+[^AD].+\s+●$'
    if ($LaneRow -notmatch $pattern) {
        throw "Audit lane format invalid: $LaneRow"
    }
}
```

### 6.2 Python Test Helpers

```python
import re

FORBIDDEN_STATUS_WORDS = ['RUNNING', 'OK', 'BLOCKED', 'IDLE']

def assert_no_status_words(lane_output: str) -> None:
    """Lane rows must not contain status words."""
    for word in FORBIDDEN_STATUS_WORDS:
        if re.search(rf'\b{word}\b', lane_output):
            raise AssertionError(f"Lane contains forbidden status word: {word}")

def assert_next_line(output: str, expected: str) -> None:
    """Verify correct Next: command is shown."""
    assert expected in ('draft-plan', 'accept-plan', 'go')
    pattern = rf'Next: /{expected}\b'
    if not re.search(pattern, output):
        raise AssertionError(f"Expected 'Next: /{expected}' not found")

def assert_health_dot(lane_row: str) -> None:
    """Every lane row must have exactly one health dot."""
    if '●' not in lane_row:
        raise AssertionError("Lane row missing health dot")

def assert_work_lane_format(lane_row: str) -> None:
    """Work lanes: LANE tokens A:n D:n/n|— summary dot"""
    pattern = r'^(BACKEND|FRONTEND)\s+[■□]+\s+A:\d+\s+D:(\d+/\d+|—)\s+.+\s+●$'
    if not re.match(pattern, lane_row.strip()):
        raise AssertionError(f"Work lane format invalid: {lane_row}")

def assert_audit_lane_format(lane_row: str) -> None:
    """Audit lanes: LANE tokens summary dot (no A:/D:)"""
    pattern = r'^(QA/AUDIT|LIBRARIAN)\s+[■□]+\s+[^AD].+\s+●$'
    if not re.match(pattern, lane_row.strip()):
        raise AssertionError(f"Audit lane format invalid: {lane_row}")
```

---

## 7. State Machine Summary

```
                    ┌──────────────────────────────────────┐
                    │                                      │
                    ▼                                      │
    ┌─────────┐  /draft-plan  ┌─────────┐  /accept-plan  ┌─────────┐
    │ NO PLAN │──────────────▶│  DRAFT  │───────────────▶│ ACCEPTED│
    └─────────┘               └─────────┘                └─────────┘
         │                         │                          │
         │                         │                          │ /go
         │                         │                          ▼
         │                         │                    ┌──────────┐
         │                         │ (edit file)        │ EXECUTING│
         │                         ▼                    └──────────┘
         │                    ┌─────────┐                     │
         │                    │  DRIFT  │◀────────────────────┘
         │                    └─────────┘      (file changed)
         │                         │
         │                         │ /accept-plan
         │                         ▼
         └─────────────────▶ [ACCEPTED]
```

**States:**
- `NO PLAN`: No draft file exists → Next: /draft-plan
- `DRAFT`: Draft exists, no tasks in DB → Next: /accept-plan
- `ACCEPTED`: Tasks hydrated in DB → Next: /go
- `DRIFT`: Draft changed after accept, tasks still valid → Next: /go (with warning)
- `EXECUTING`: /go running tasks from DB

---

## 8. Error Handling

### 8.1 /go with No Tasks

**Input:** User runs `/go` when tasks DB is empty

**Expected Output:**
```
No tasks loaded. Use /accept-plan to load a plan first.
```

**Must NOT:**
- Crash or throw exception
- Show stack trace
- Return empty/silent response

### 8.2 /accept-plan with No Draft

**Input:** User runs `/accept-plan` when no draft file exists

**Expected Output:**
```
No draft plan found. Use /draft-plan to create one first.
```

### 8.3 /accept-plan Parse Failure

**Input:** Draft file exists but cannot be parsed

**Expected Output:**
```
Failed to parse draft plan: <reason>
Fix the plan file and try again.
```

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-19 | Initial specification |
