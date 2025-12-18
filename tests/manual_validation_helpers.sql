-- v21.0 Manual Validation Helpers
-- Use these snippets to validate the two skipped tests during manual smoke

-- ============================================================================
-- VALIDATION 1: RED Decision Alert
-- ============================================================================

-- Insert a RED priority decision (triggers RED_DECISION alert)
INSERT INTO decisions (question, status, priority)
VALUES ('CRITICAL: Manual smoke test - is production ready?', 'pending', 'red');

-- Verify it was created:
SELECT * FROM decisions WHERE priority = 'red';

-- After testing, cleanup:
-- DELETE FROM decisions WHERE question LIKE '%Manual smoke test%';


-- ============================================================================
-- VALIDATION 2: All Completed -> NO_WORK
-- ============================================================================

-- First, check current task states:
SELECT status, COUNT(*) as count FROM tasks GROUP BY status;

-- Mark all pending/in_progress tasks as completed:
UPDATE tasks SET status = 'completed', updated_at = strftime('%s','now')
WHERE status IN ('pending', 'in_progress');

-- Verify all tasks are completed:
SELECT status, COUNT(*) as count FROM tasks GROUP BY status;

-- Now run /go - should return NO_WORK

-- To restore test tasks for further testing:
-- UPDATE tasks SET status = 'pending' WHERE id IN (1, 2, 3);  -- adjust IDs as needed


-- ============================================================================
-- HELPFUL QUERIES FOR DEBUGGING
-- ============================================================================

-- Check worker heartbeats:
SELECT worker_id, worker_type, allowed_lanes,
       datetime(last_seen, 'unixepoch', 'localtime') as last_seen_dt,
       (strftime('%s','now') - last_seen) as age_seconds,
       task_ids
FROM worker_heartbeats
ORDER BY last_seen DESC;

-- Check scheduler state:
SELECT key, value FROM config WHERE key LIKE 'scheduler%';

-- Check active tasks:
SELECT id, lane, type, status, worker_id,
       datetime(updated_at, 'unixepoch', 'localtime') as updated_dt
FROM tasks
WHERE status = 'in_progress';

-- Check lane distribution:
SELECT COALESCE(NULLIF(lane,''), type) as lane_name, status, COUNT(*)
FROM tasks
GROUP BY lane_name, status
ORDER BY lane_name, status;
