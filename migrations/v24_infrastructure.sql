-- Vibe Coding V1.0 Infrastructure
-- Run: sqlite3 vibe_coding.db < v24_infrastructure.sql
-- PostgreSQL-compatible schema for future migration

-- =============================================================================
-- 1. TASKS TABLE (with Leases for Atomic Ownership)
-- =============================================================================

CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    lane TEXT NOT NULL,              -- '@backend', '@frontend', '@qa', '@docs'
    status TEXT DEFAULT 'pending',   -- 'pending', 'in_progress', 'blocked', 'review_needed', 'completed', 'cancelled'
    goal TEXT NOT NULL,
    context_files TEXT,              -- JSON list of file paths
    dependencies TEXT,               -- JSON list of task IDs
    worker_id TEXT,
    lease_id TEXT,
    lease_expires_at INTEGER DEFAULT 0,
    attempt_count INTEGER DEFAULT 0,
    metadata TEXT,                   -- JSON (risk, notified, etc)
    blocker_msg TEXT DEFAULT '',
    manager_feedback TEXT DEFAULT '',
    worker_output TEXT DEFAULT '',
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- =============================================================================
-- 2. TASK MESSAGES (Conversation Memory)
-- =============================================================================

CREATE TABLE IF NOT EXISTS task_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER NOT NULL,
    role TEXT NOT NULL,              -- 'worker', 'brain', 'system'
    msg_type TEXT NOT NULL,          -- 'clarification', 'next_step', 'submission', 'alert', 'approval', 'rejection'
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- =============================================================================
-- 3. DECISIONS TABLE (Human-in-the-Loop Escalations)
-- =============================================================================

CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER,
    priority TEXT NOT NULL,          -- 'red', 'yellow', 'green'
    question TEXT NOT NULL,
    context TEXT,
    status TEXT DEFAULT 'pending',   -- 'pending', 'approved', 'rejected'
    answer TEXT,
    created_at INTEGER NOT NULL,
    resolved_at INTEGER,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- =============================================================================
-- 4. PERFORMANCE INDEXES (For Controller Queries)
-- =============================================================================

-- Sweeper: Find stale in_progress tasks
CREATE INDEX IF NOT EXISTS idx_tasks_sweeper 
ON tasks(status, lease_expires_at) 
WHERE status = 'in_progress';

-- Review Handler: Find tasks needing review
CREATE INDEX IF NOT EXISTS idx_tasks_review_queue 
ON tasks(status) 
WHERE status = 'review_needed';

-- Lane Queries: Status per lane
CREATE INDEX IF NOT EXISTS idx_tasks_lane_status 
ON tasks(lane, status);

-- Message History: Fast retrieval by task
CREATE INDEX IF NOT EXISTS idx_task_messages_task_id 
ON task_messages(task_id, created_at);

-- Decisions Queue: Pending decisions by priority
CREATE INDEX IF NOT EXISTS idx_decisions_status 
ON decisions(status, priority, created_at);

-- =============================================================================
-- 5. WAL MODE (Concurrency)
-- =============================================================================

PRAGMA journal_mode = WAL;

-- =============================================================================
-- VERIFICATION QUERIES (Run after migration)
-- =============================================================================
-- SELECT name FROM sqlite_master WHERE type='table';
-- SELECT name FROM sqlite_master WHERE type='index';
-- SELECT sql FROM sqlite_master WHERE type='table' AND name='tasks';
