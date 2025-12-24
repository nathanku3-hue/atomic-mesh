-- Vibe Coding v24.1 Migration
-- Adds Atomic Ownership, Lease Expiry, and Message Logging
-- Compatible with existing Atomic Mesh v24.2 schema

-- =============================================================================
-- PHASE 1: LEASE & OWNERSHIP COLUMNS
-- =============================================================================
-- Prevents "Zombie Workers" and allows safe concurrency.

-- Add lease tracking columns (if not already present from v24.2)
-- These are idempotent - will only add if column doesn't exist

-- Lease ID for tracking worker ownership
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS lease_id TEXT DEFAULT '';

-- Unix timestamp when lease expires
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS lease_expires_at INTEGER DEFAULT 0;

-- Track rejection/retry attempts
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS attempt_count INTEGER DEFAULT 0;

-- Worker-Brain communication columns
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS blocker_msg TEXT DEFAULT '';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS manager_feedback TEXT DEFAULT '';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS worker_output TEXT DEFAULT '';

-- =============================================================================
-- PHASE 2: TASK MESSAGE LOG (THE MEMORY)
-- =============================================================================
-- Enables multi-turn conversations (clarifications) and audit trails.

CREATE TABLE IF NOT EXISTS task_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER NOT NULL,
    role TEXT NOT NULL,       -- 'worker', 'brain', 'system'
    msg_type TEXT NOT NULL,   -- 'clarification', 'feedback', 'submission', 'review', 'approval', 'rejection'
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- Index for fast history retrieval
CREATE INDEX IF NOT EXISTS idx_task_messages_task_id 
ON task_messages(task_id, created_at);

-- =============================================================================
-- PHASE 3: DECISIONS TABLE (HUMAN-IN-THE-LOOP)
-- =============================================================================
-- Persists high-risk approvals and escalations separate from chat context.

CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id INTEGER,
    priority TEXT NOT NULL,   -- 'red', 'yellow', 'green'
    question TEXT NOT NULL,
    context TEXT,             -- Additional context or reasoning
    status TEXT DEFAULT 'pending',  -- 'pending', 'approved', 'rejected'
    answer TEXT,              -- Human decision/feedback
    created_at INTEGER NOT NULL,
    resolved_at INTEGER,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- Index for querying pending decisions
CREATE INDEX IF NOT EXISTS idx_decisions_status 
ON decisions(status, priority, created_at);

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================
-- Run these to verify migration success:

-- 1. Check all new columns exist
-- SELECT sql FROM sqlite_master WHERE type='table' AND name='tasks';

-- 2. Verify task_messages table
-- SELECT COUNT(*) FROM task_messages;

-- 3. Verify decisions table
-- SELECT COUNT(*) FROM decisions;

-- 4. Check indexes
-- SELECT name FROM sqlite_master WHERE type='index' AND tbl_name IN ('task_messages', 'decisions');

-- =============================================================================
-- ROLLBACK (if needed)
-- =============================================================================
-- SQLite doesn't support DROP COLUMN, so rollback requires recreation.
-- Only use if you need to completely undo this migration.

-- DROP TABLE IF EXISTS task_messages;
-- DROP TABLE IF EXISTS decisions;
-- DROP INDEX IF EXISTS idx_task_messages_task_id;
-- DROP INDEX IF EXISTS idx_decisions_status;

-- Note: Removing columns from tasks table requires:
-- 1. Create new table without those columns
-- 2. Copy data
-- 3. Drop old table
-- 4. Rename new table
-- This is destructive and should only be done in development.

-- =============================================================================
-- NOTES
-- =============================================================================
-- * This migration is compatible with Atomic Mesh v24.2
-- * All ALTER TABLE statements use IF NOT EXISTS for idempotency
-- * Indexes are created with IF NOT EXISTS to allow re-running
-- * The schema supports the full Worker-Brain communication workflow
-- * Lease expiry enables automatic recovery from zombie workers
-- * Message log provides full audit trail and conversation history
-- * Decisions table separates high-risk approvals from task flow
