# Vibe Coding V3.3 - Implementation Plan

## Scope: Features 9-15 (Lower ROI, Polish & Performance)

| # | Feature | ROI | Type | Effort |
|---|---------|-----|------|--------|
| 9 | `status_updated_at` Column | 3:1 | Schema | ~10 lines |
| 10 | Task History Archival | 2:1 | Controller | ~30 lines |
| 11 | Dead Letter View (already done) | ✅ | Schema | Done |
| 12 | `backoff_until` Index | 2:1 | Schema | ~2 lines |
| 13 | In-Memory Worker Cache | 3:1 | Controller | ~60 lines |
| 14 | Weighted Scoring Router | 3:1 | Controller | ~50 lines |
| 15 | Auto-Scaler Hook | 1:1 | Controller | ~40 lines (Optional) |

**Note:** Feature 11 was already implemented in V3.2 (`view_dead_letter_queue`).

---

## Feature 9: `status_updated_at` Column

**Purpose:** Track exactly when status changed (vs. general `updated_at`)

**Schema Change:**
```sql
ALTER TABLE tasks ADD COLUMN status_updated_at INTEGER DEFAULT (strftime('%s', 'now'));
```

**Controller Change:**
- Update `status_updated_at` in all status transitions
- Already partially done (some UPDATE statements set it)

**Estimated Lines:** ~10

---

## Feature 10: Task History Archival

**Purpose:** Prevent history table bloat by moving old records to archive

**New Table:**
```sql
CREATE TABLE IF NOT EXISTS task_history_archive (
    id INTEGER PRIMARY KEY,
    task_id INTEGER,
    status TEXT,
    worker_id TEXT,
    timestamp INTEGER,
    details TEXT
);
```

**New Function:**
```python
def archive_old_history(conn: sqlite3.Connection, days: int = 7):
    """Move history older than N days to archive table."""
    cutoff = int(time.time()) - (days * 86400)
    conn.execute("""
        INSERT INTO task_history_archive 
        SELECT * FROM task_history WHERE timestamp < ?
    """, (cutoff,))
    conn.execute("DELETE FROM task_history WHERE timestamp < ?", (cutoff,))
```

**Integration:** Call in main loop periodically (every 100 iterations)

**Estimated Lines:** ~30

---

## Feature 12: `backoff_until` Index

**Purpose:** Fast lookup of tasks ready for retry

**Schema Change:**
```sql
CREATE INDEX IF NOT EXISTS idx_backoff_ready 
ON tasks(status, backoff_until) WHERE status = 'pending';
```

**Estimated Lines:** ~2

---

## Feature 13: In-Memory Worker Cache

**Purpose:** Reduce DB queries for worker health during routing

**Implementation:**
```python
WORKER_CACHE = {}
CACHE_TTL = 10  # seconds

def get_cached_workers(conn, lane):
    now = time.time()
    cache_key = lane
    
    if cache_key in WORKER_CACHE:
        cached, timestamp = WORKER_CACHE[cache_key]
        if now - timestamp < CACHE_TTL:
            return cached
    
    # Query DB and cache
    workers = conn.execute("""
        SELECT worker_id, tier, active_tasks, capacity_limit 
        FROM worker_health WHERE lane = ? AND status = 'online'
    """, (lane,)).fetchall()
    
    WORKER_CACHE[cache_key] = ([dict(w) for w in workers], now)
    return WORKER_CACHE[cache_key][0]

def invalidate_worker_cache(lane=None):
    if lane:
        WORKER_CACHE.pop(lane, None)
    else:
        WORKER_CACHE.clear()
```

**Integration:** 
- Call `get_cached_workers()` in routing functions
- Call `invalidate_worker_cache()` after worker updates

**Estimated Lines:** ~60

---

## Feature 14: Weighted Scoring Router

**Purpose:** Replace simple "least busy" with multi-factor scoring

**Algorithm:**
```python
def calculate_worker_score(worker, task_effort, task_priority):
    score = 0
    
    # Factor 1: Free Capacity (higher = better)
    free = worker['capacity_limit'] - worker['active_tasks']
    score += free * 10
    
    # Factor 2: Tier Match (senior for hard tasks)
    if task_effort >= 4 and worker['tier'] == 'senior':
        score += 50
    elif task_effort >= 4 and worker['tier'] != 'senior':
        score -= 20  # Penalty
    
    # Factor 3: Priority Override (critical = any slot)
    if task_priority == 'critical':
        score += 30
    elif task_priority == 'high':
        score += 15
    
    return score
```

**Integration:** Update `get_best_worker_with_tier()` to use scoring

**Estimated Lines:** ~50

---

## Feature 15: Auto-Scaler Hook (OPTIONAL)

**Purpose:** Provision virtual workers when pool saturated

**Implementation:**
```python
def provision_virtual_worker(conn, lane):
    """Simulate K8s pod / Lambda / Cursor session spin-up."""
    new_id = f"@{lane}-auto-{int(time.time())}"
    print(f"⚡ [Scaler] Provisioning {new_id}")
    
    conn.execute("""
        INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, last_seen)
        VALUES (?, ?, 'standard', 3, 'online', ?)
    """, (new_id, lane, int(time.time())))
    
    invalidate_worker_cache(lane)
    return new_id
```

**Integration:**
- Call when `check_saturation()` returns True
- Optional: Add `MAX_AUTO_SCALE_WORKERS` limit

**Note:** This is a hook for future scaling. Currently just registers virtual IDs.

**Estimated Lines:** ~40

---

## Proposed Changes Summary

### [MODIFY] migrations/v25_schema.sql
- Add `status_updated_at` column
- Add `task_history_archive` table
- Add `idx_backoff_ready` index

### [MODIFY] vibe_controller.py
- Add `WORKER_CACHE` and cache functions
- Add `archive_old_history()` function
- Add `calculate_worker_score()` function
- Update `get_best_worker_with_tier()` with scoring
- (Optional) Add `provision_virtual_worker()` hook

---

## Verification Plan

| Test | Description |
|------|-------------|
| Cache Hit | Query same lane twice, verify DB hit only once |
| Cache Invalidation | Update worker, verify cache cleared |
| Archival | Create old history, run archive, verify moved |
| Scoring | Compare scores for various task/worker combos |
| Backoff Index | Verify EXPLAIN uses index for pending lookups |

---

## Estimated Total Effort

| Component | Lines Changed |
|-----------|--------------|
| Schema | +20 |
| Controller | +150 |
| Tests | +80 |
| **Total** | **~250 lines** |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Cache staleness | 10s TTL, invalidate on writes |
| Scoring edge cases | Fallback to simple if all scores equal |
| Archive data loss | Archive table preserves all data |

---

**Status:** Awaiting Approval
