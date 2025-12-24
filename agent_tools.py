"""
Vibe Coding Agent Tools
=======================
Tools exposed to AI workers (Architect, Backend, Frontend, QA)
to interact with the Vibe Controller system.
"""

import sqlite3
import time
import os
from typing import Optional

DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")

def ask_clarification(task_id: int, question: str) -> str:
    """
    Call this when you are BLOCKED and cannot proceed. 
    It will pause your task and notify the Architect/Human.
    
    Args:
        task_id: Your current task ID.
        question: Specific details on what is missing or ambiguous.
    """
    conn = sqlite3.connect(DB_PATH)
    try:
        now = int(time.time())
        
        # 1. Log the Question as a task message
        # msg_type='clarification' helps the UI rendering
        conn.execute("""
            INSERT INTO task_messages (task_id, role, msg_type, content, created_at)
            VALUES (?, 'worker', 'clarification', ?, ?)
        """, (task_id, question, now))
        
        # 2. Set Status to BLOCKED and Release Lease
        # We also store the blocker message in a new column or metadata if schema allowed, 
        # but for now we rely on the task_messages history.
        # V1.2 Controller looks for 'blocker_msg' in metadata or just relies on status.
        # Let's add it to metadata for easier sweeper access.
        
        cursor = conn.execute("SELECT metadata FROM tasks WHERE id=?", (task_id,))
        row = cursor.fetchone()
        metadata = {}
        if row and row[0]:
            import json
            try:
                metadata = json.loads(row[0])
            except:
                pass
        
        metadata['blocker_msg'] = question
        import json
        
        conn.execute("""
            UPDATE tasks 
            SET status='blocked', lease_id=NULL, updated_at=?, metadata=?
            WHERE id=?
        """, (now, json.dumps(metadata), task_id))  # SAFETY-ALLOW: status-write
        
        conn.commit()
        return "Status set to BLOCKED. The Architect has been notified. Please wait for instructions."
        
    except Exception as e:
        return f"Error: {e}"
    finally:
        conn.close()

def claim_task(lane: str, worker_id: str) -> Optional[dict]:
    """
    Attempts to claim a pending task for the given lane.
    Returns task dict if successful, None otherwise.
    """
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        now = int(time.time())
        lease_expires = now + 600 # 10 minutes
        
        # Atomic claim (Transaction)
        conn.execute("BEGIN IMMEDIATE")
        
        # 1. Find candidate
        cursor = conn.execute("""
            SELECT id FROM tasks 
            WHERE status='pending' AND lane=? 
            ORDER BY created_at ASC 
            LIMIT 1
        """, (lane,))
        row = cursor.fetchone()
        
        if not row:
            conn.rollback()
            return None
            
        task_id = row['id']
        
        # 2. Claim it
        conn.execute("""
            UPDATE tasks 
            SET status='in_progress', worker_id=?, lease_id=?, lease_expires_at=?, updated_at=?
            WHERE id=?
        """, (worker_id, worker_id, lease_expires, now, task_id))  # SAFETY-ALLOW: status-write
        
        # 3. Return updated task
        cursor = conn.execute("SELECT * FROM tasks WHERE id=?", (task_id,))
        task = dict(cursor.fetchone())
        
        conn.commit()
        return task
        
    except Exception:
        conn.rollback()
        return None
    finally:
        conn.close()
