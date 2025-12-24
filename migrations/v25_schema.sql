-- ============================================================
-- Vibe Coding V2.0 Infrastructure Schema
-- ============================================================
-- Support for Direct Delegation, Detailed Logging, and Worker Health
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
    
    -- Assignment (REQUIRED)
    worker_id TEXT NOT NULL,            -- Target worker (e.g., @backend-1)
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
    
    -- Retry Logic
    attempt_count INTEGER DEFAULT 0,
    
    -- Metadata (JSON)
    metadata TEXT,                      -- risk, priority, fallback_tried, blocker_msg, etc.
    
    -- Timestamps
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
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

INSERT OR IGNORE INTO worker_health (worker_id, lane, status, priority_score)
VALUES 
    ('@backend-1', 'backend', 'online', 60),
    ('@backend-2', 'backend', 'online', 50),
    ('@frontend-1', 'frontend', 'online', 60),
    ('@frontend-2', 'frontend', 'online', 50),
    ('@qa-1', 'qa', 'online', 50),
    ('@librarian', 'docs', 'online', 50);

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

INSERT OR REPLACE INTO schema_version (version) VALUES ('v25_2.1');
