function Reset-OrphanedTasks {
    <#
    .SYNOPSIS
        Resets tasks stuck in 'in_progress' status for >10 minutes on startup.
        This prevents "zombie tasks" from blocking lanes after worker crashes.

    .PARAMETER DbPath
        Path to the mesh.db SQLite database.

    .PARAMETER TimeoutSeconds
        How long a task can be in_progress without update before considered orphaned.
        Default: 600 (10 minutes).

    .OUTPUTS
        Number of tasks reset, or -1 if database doesn't exist.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DbPath,

        [int]$TimeoutSeconds = 600
    )

    if (-not (Test-Path $DbPath)) {
        return -1
    }

    try {
        # Use Python for SQLite access (consistent with rest of codebase)
        $pythonScript = @"
import sqlite3
import sys

db_path = sys.argv[1]
timeout = int(sys.argv[2])

conn = sqlite3.connect(db_path)
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('PRAGMA busy_timeout=5000')
c = conn.cursor()

# Check if heartbeat_at column exists (v23.1+)
cols = {row[1] for row in c.execute('PRAGMA table_info(tasks)').fetchall()}
has_heartbeat = 'heartbeat_at' in cols

# Use heartbeat_at if available (more precise), fallback to updated_at
if has_heartbeat:
    # Prefer heartbeat_at: tasks are orphaned if heartbeat is stale
    # But also check updated_at for tasks that never got a heartbeat (heartbeat_at=0)
    c.execute('''
        SELECT COUNT(*) FROM tasks
        WHERE status = 'in_progress'
        AND (
            (heartbeat_at > 0 AND heartbeat_at < strftime('%s','now') - ?)
            OR (heartbeat_at = 0 AND updated_at < strftime('%s','now') - ?)
        )
    ''', (timeout, timeout))
else:
    # Fallback: use updated_at only
    c.execute('''
        SELECT COUNT(*) FROM tasks
        WHERE status = 'in_progress'
        AND updated_at < strftime('%s','now') - ?
    ''', (timeout,))

count = c.fetchone()[0]

if count > 0:
    # Reset orphaned tasks
    if has_heartbeat:
        c.execute('''
            UPDATE tasks
            SET status = 'pending',
                worker_id = NULL,
                lease_id = '',
                heartbeat_at = 0,
                updated_at = strftime('%s','now')
            WHERE status = 'in_progress'
            AND (
                (heartbeat_at > 0 AND heartbeat_at < strftime('%s','now') - ?)
                OR (heartbeat_at = 0 AND updated_at < strftime('%s','now') - ?)
            )
        ''', (timeout, timeout))
    else:
        c.execute('''
            UPDATE tasks
            SET status = 'pending',
                worker_id = NULL,
                lease_id = '',
                updated_at = strftime('%s','now')
            WHERE status = 'in_progress'
            AND updated_at < strftime('%s','now') - ?
        ''', (timeout,))
    conn.commit()

conn.close()
print(count)
"@

        $result = $pythonScript | python - $DbPath $TimeoutSeconds 2>&1

        if ($LASTEXITCODE -eq 0) {
            return [int]$result
        }
        return 0
    }
    catch {
        # Silently fail - orphan reset is best-effort
        return 0
    }
}
