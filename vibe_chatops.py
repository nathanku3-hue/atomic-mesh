"""
Vibe ChatOps - Slack/Discord Integration
=========================================
Flask webhook for team-friendly control of the Vibe Coding system.

Usage:
    python vibe_chatops.py
    
Slack Setup:
    1. Create Slack App at api.slack.com
    2. Add slash command: /vibe
    3. Point to: https://your-server:5001/slack/command
"""

from flask import Flask, request, jsonify
import sqlite3
import os
import sys

app = Flask(__name__)
DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")


def get_db():
    """Get database connection."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({"status": "ok", "version": "3.4"})


@app.route('/slack/command', methods=['POST'])
def slack_command():
    """
    Handle Slack slash commands.
    
    Commands:
        /vibe status    - Show active workers and task counts
        /vibe retry <id> - Retry a failed task
        /vibe approve <id> - Approve a high-risk task
        /vibe dlq       - Show dead letter queue
        /vibe worker <id> - Show specific worker status
    """
    text = request.form.get('text', '').strip()
    user = request.form.get('user_name', 'unknown')
    
    print(f"📨 [ChatOps] Command from {user}: /vibe {text}")
    
    try:
        if not text or text == 'help':
            return get_help()
        elif text == 'status':
            return get_status_summary()
        elif text.startswith('retry '):
            task_id = text.split()[1]
            return retry_task(task_id, user)
        elif text.startswith('approve '):
            task_id = text.split()[1]
            return approve_task(task_id, user)
        elif text == 'dlq':
            return get_dlq_summary()
        elif text.startswith('worker '):
            worker_id = text.split()[1]
            return get_worker_status(worker_id)
        else:
            return f"❓ Unknown command: {text}\n\nType `/vibe help` for usage."
    except Exception as e:
        return f"❌ Error: {str(e)}"


def get_help():
    """Return help message."""
    return """
*🏭 Vibe Controller ChatOps*

*Commands:*
• `/vibe status` - Show system overview
• `/vibe dlq` - Show dead letter queue
• `/vibe retry <id>` - Retry a failed task
• `/vibe approve <id>` - Approve a blocked task
• `/vibe worker <id>` - Show worker status

*Examples:*
```
/vibe status
/vibe retry 42
/vibe worker @backend-1
```
"""


def get_status_summary():
    """Get system status summary."""
    conn = get_db()
    
    # Worker summary by lane
    workers = conn.execute("""
        SELECT lane, COUNT(*) as count, 
               SUM(active_tasks) as load,
               SUM(capacity_limit) as capacity
        FROM worker_health 
        WHERE status = 'online' 
        GROUP BY lane
    """).fetchall()
    
    # Task summary by status
    tasks = conn.execute("""
        SELECT status, COUNT(*) as count 
        FROM tasks 
        GROUP BY status
        ORDER BY count DESC
    """).fetchall()
    
    conn.close()
    
    lines = ["📊 *Vibe System Status*\n"]
    
    lines.append("*Workers:*")
    for w in workers:
        utilization = (w['load'] / w['capacity'] * 100) if w['capacity'] > 0 else 0
        lines.append(f"  • {w['lane']}: {w['count']} workers ({w['load']}/{w['capacity']} = {utilization:.0f}%)")
    
    lines.append("\n*Tasks:*")
    for t in tasks:
        emoji = "🔄" if t['status'] == 'in_progress' else "⏳" if t['status'] == 'pending' else "✅" if t['status'] == 'completed' else "💀" if t['status'] == 'dead_letter' else "📋"
        lines.append(f"  {emoji} {t['status']}: {t['count']}")
    
    return "\n".join(lines)


def retry_task(task_id, user):
    """Retry a failed task."""
    conn = get_db()
    
    # Check task exists
    task = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if not task:
        conn.close()
        return f"❌ Task #{task_id} not found"
    
    # Reset task
    conn.execute("UPDATE tasks SET status = 'pending', attempt_count = 0, updated_at = strftime('%s', 'now') WHERE id = ?", (task_id,))  # SAFETY-ALLOW: status-write
    conn.commit()
    conn.close()
    
    return f"🔄 Task #{task_id} reset to pending by {user}\n*Goal:* {task['goal'][:50]}..."


def approve_task(task_id, user):
    """Approve a blocked/review task."""
    conn = get_db()
    
    task = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if not task:
        conn.close()
        return f"❌ Task #{task_id} not found"
    
    conn.execute("UPDATE tasks SET status = 'in_progress', updated_at = strftime('%s', 'now') WHERE id = ?", (task_id,))  # SAFETY-ALLOW: status-write
    conn.commit()
    conn.close()
    
    return f"✅ Task #{task_id} approved by {user}\n*Goal:* {task['goal'][:50]}..."


def get_dlq_summary():
    """Get dead letter queue summary."""
    conn = get_db()
    
    dlq = conn.execute("""
        SELECT id, goal, lane, last_error_type, attempt_count, 
               (strftime('%s', 'now') - updated_at) / 3600 as hours_dead
        FROM tasks 
        WHERE status = 'dead_letter' 
        ORDER BY updated_at ASC 
        LIMIT 10
    """).fetchall()
    
    conn.close()
    
    if not dlq:
        return "✅ *Dead Letter Queue is empty!*"
    
    lines = [f"💀 *Dead Letter Queue ({len(dlq)} tasks):*\n"]
    for t in dlq:
        escalation = "🔥" if t['hours_dead'] >= 24 else ""
        lines.append(f"  {escalation}#{t['id']} ({t['lane']}) - {t['hours_dead']:.0f}h dead")
        lines.append(f"    └ {t['goal'][:40]}...")
    
    lines.append(f"\n_Use `/vibe retry <id>` to retry a task_")
    
    return "\n".join(lines)


def get_worker_status(worker_id):
    """Get specific worker status."""
    # Normalize worker ID
    if not worker_id.startswith('@'):
        worker_id = f"@{worker_id}"
    
    conn = get_db()
    
    worker = conn.execute("""
        SELECT * FROM worker_health WHERE worker_id = ?
    """, (worker_id,)).fetchone()
    
    if not worker:
        conn.close()
        return f"❌ Worker {worker_id} not found"
    
    # Get active tasks
    tasks = conn.execute("""
        SELECT id, goal, status FROM tasks 
        WHERE worker_id = ? AND status IN ('pending', 'in_progress')
        LIMIT 5
    """, (worker_id,)).fetchall()
    
    conn.close()
    
    lines = [f"👷 *Worker: {worker_id}*\n"]
    lines.append(f"  • Lane: {worker['lane']}")
    lines.append(f"  • Tier: {worker['tier']}")
    lines.append(f"  • Status: {worker['status']}")
    lines.append(f"  • Load: {worker['active_tasks']}/{worker['capacity_limit']}")
    
    if tasks:
        lines.append(f"\n*Active Tasks:*")
        for t in tasks:
            lines.append(f"  • #{t['id']} ({t['status']}): {t['goal'][:30]}...")
    
    return "\n".join(lines)


if __name__ == '__main__':
    print("🚀 Vibe ChatOps Server Starting...")
    print(f"   DB: {DB_PATH}")
    print(f"   Endpoint: http://localhost:5001/slack/command")
    app.run(port=5001, debug=False)
