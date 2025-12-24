-- ============================================================
-- Vibe Coding V3.3 Infrastructure Schema
-- ============================================================
-- Features: Direct Delegation, Worker Tiers, Smart Backoff, DLQ
-- Run: sqlite3 vibe_coding.db < migrations/v25_schema.sql
-- ============================================================

-- Enable WAL mode for concurrent access
PRAGMA journal_mode = WAL;

-- ============================================================
-- 1. Tasks Table (Updated for Direct Assignment)
-- ============================================================
-- The worker_id field is now MANDATORY for push-based delegation.
-- Architect assigns tasks directly to specific workers.

CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    -- Assignment (NULL = pending reassignment after failure)
    worker_id TEXT,                      -- Target worker or NULL for pending/retry
    lane TEXT NOT NULL,                 -- Skill lane (backend, frontend, qa, docs)
    
    -- Status
    status TEXT DEFAULT 'pending',      -- pending, in_progress, review_needed, completed, blocked, failed
    
    -- Task Details
    goal TEXT NOT NULL,
    context_files TEXT,                 -- JSON array of file paths
    dependencies TEXT,                  -- JSON array of task IDs
    
    -- Lease Management
    lease_id TEXT,                      -- Worker session ID (for crash recovery)
    lease_expires_at INTEGER DEFAULT 0,
    
    -- Retry Logic (V3.2)
    attempt_count INTEGER DEFAULT 0,
    backoff_until INTEGER DEFAULT 0,    -- V3.2: Don't retry before this timestamp
    last_error_type TEXT,               -- V3.2: 'network', 'crash', 'permanent'
    
    -- Priority & Complexity (V3.2)
    priority TEXT DEFAULT 'normal',     -- 'critical', 'high', 'normal'
    effort_rating INTEGER DEFAULT 1,    -- 1 (easy) to 5 (hard)
    
    -- Metadata (JSON)
    metadata TEXT,                      -- risk, fallback_tried, blocker_msg, etc.
    
    -- Timestamps
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    status_updated_at INTEGER DEFAULT (strftime('%s', 'now'))  -- V3.3: Precise status tracking
);

-- ============================================================
-- 2. Task Messages (Preserves V1.x compatibility)
-- ============================================================
-- Stores clarification questions, feedback, and admin actions.

CREATE TABLE IF NOT EXISTS task_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER NOT NULL,
    role TEXT NOT NULL,                 -- worker, system, admin
    msg_type TEXT NOT NULL,             -- clarification, feedback, action
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- ============================================================
-- 3. Task History (V2.0 - Granular Audit Log)
-- ============================================================
-- Every status change is permanently logged for auditing.

CREATE TABLE IF NOT EXISTS task_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    worker_id TEXT,
    timestamp INTEGER NOT NULL,
    details TEXT,                       -- Human-readable context
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- ============================================================
-- 4. Worker Health (V2.0 - Load Balancing & Fallbacks)
-- ============================================================
-- Tracks worker availability and performance for smart assignment.

CREATE TABLE IF NOT EXISTS worker_health (
    worker_id TEXT PRIMARY KEY,         -- e.g., @backend-1
    lane TEXT NOT NULL,                 -- backend, frontend, qa, docs
    
    -- V3.2: Worker Tier
    tier TEXT DEFAULT 'standard',       -- 'senior', 'standard'
    capacity_limit INTEGER DEFAULT 3,   -- Max concurrent tasks (V3.2)
    
    -- Availability
    last_seen INTEGER DEFAULT 0,        -- Unix timestamp of last heartbeat
    status TEXT DEFAULT 'online',       -- online, busy, offline
    
    -- Load Metrics
    active_tasks INTEGER DEFAULT 0,     -- Current task count
    completed_today INTEGER DEFAULT 0,  -- Tasks completed today
    
    -- Priority (for load balancing)
    priority_score INTEGER DEFAULT 50   -- 0-100, higher = preferred
);

-- ============================================================
-- 5. Indexes for Performance
-- ============================================================

-- Fast lookup of worker's pending tasks (inbox)
CREATE INDEX IF NOT EXISTS idx_worker_inbox ON tasks(worker_id, status);

-- Fast task completion by status
CREATE INDEX IF NOT EXISTS idx_task_status ON tasks(status, created_at);

-- Fast audit log queries
CREATE INDEX IF NOT EXISTS idx_task_history ON task_history(task_id, timestamp);

-- Fast worker selection by lane
CREATE INDEX IF NOT EXISTS idx_worker_lane ON worker_health(lane, status, active_tasks);

-- ============================================================
-- 6. Default Workers (Bootstrap)
-- ============================================================
-- Insert default workers for each lane.

INSERT OR IGNORE INTO worker_health (worker_id, lane, tier, capacity_limit, status, priority_score)
VALUES 
    ('@backend-senior', 'backend', 'senior', 5, 'online', 80),
    ('@backend-1', 'backend', 'standard', 3, 'online', 60),
    ('@backend-2', 'backend', 'standard', 3, 'online', 50),
    ('@frontend-senior', 'frontend', 'senior', 5, 'online', 80),
    ('@frontend-1', 'frontend', 'standard', 3, 'online', 60),
    ('@frontend-2', 'frontend', 'standard', 3, 'online', 50),
    ('@qa-1', 'qa', 'standard', 3, 'online', 50),
    ('@librarian', 'docs', 'standard', 3, 'online', 50);

-- ============================================================
-- 7. V2.1: Deduplication Index for Guardians
-- ============================================================
-- Prevents creating duplicate QA/Docs tasks for the same goal.
-- Example: Only one "Verify Task #101" in the qa lane.

CREATE UNIQUE INDEX IF NOT EXISTS idx_dedup_guardians 
ON tasks(goal, lane);

-- ============================================================
-- Schema Version
-- ============================================================

CREATE TABLE IF NOT EXISTS schema_version (
    version TEXT PRIMARY KEY,
    applied_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE VIEW IF NOT EXISTS view_dead_letter_queue AS
SELECT id, goal, lane, attempt_count, last_error_type, created_at
FROM tasks WHERE status = 'dead_letter';

-- ============================================================
-- 9. V3.3: Task History Archive
-- ============================================================
-- Stores archived history records for data hygiene

CREATE TABLE IF NOT EXISTS task_history_archive (
    id INTEGER PRIMARY KEY,
    task_id INTEGER,
    status TEXT,
    worker_id TEXT,
    timestamp INTEGER,
    details TEXT
);

-- ============================================================
-- 10. V3.3: Backoff Ready Index
-- ============================================================
-- Fast lookup of tasks ready for retry

CREATE INDEX IF NOT EXISTS idx_backoff_ready 
ON tasks(status, backoff_until);

-- Update schema version
INSERT OR REPLACE INTO schema_version (version) VALUES ('v25_3.3');
