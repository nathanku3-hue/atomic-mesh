# Vibe Coding V3.4 - Implementation Plan

## Titanium Refinements (Final Polish)

### Approved Features (Gain-to-Cost Winners)

| # | Feature | Cost | Gain | Verdict |
|---|---------|------|------|---------|
| 1 | Extended Worker Roles (Specialists) | 🟢 Low | 🔵 Very High | ✅ WINNER |
| 2 | ChatOps (Slack/Discord) | 🟡 Medium | 🔵 High | ✅ ACCEPT |
| 3 | Dashboard (Streamlit) | 🟡 Medium | 🔵 High | ✅ ACCEPT |

### Rejected Features

| # | Feature | Cost | Gain | Verdict | Rationale |
|---|---------|------|------|---------|-----------|
| 4 | Advanced Dependency Analysis | 🔴 High | ⚪ Medium | ❌ REJECT | LLM handles this |
| 5 | Predictive Monitoring | 🔴 High | ⚪ Low | ❌ REJECT | Overengineering |
| 6 | Distributed Worker Management | 🔴 Very High | ⚪ Low | ❌ REJECT | SQLite WAL is enough |

---

## Feature 1: Extended Worker Roles (Specialists)

**Cost:** 🟢 Low (~20 lines)
**Gain:** 🔵 Very High (Expands system IQ)

### New Specialists

| Worker ID | Lane | Role | Trigger |
|-----------|------|------|---------|
| `@security-1` | security | Security Auditor | After @backend, before @qa |
| `@ux-designer` | ux | UX/A11y Auditor | Alongside @frontend |
| `@data-analyst` | data | Data Quality | For data pipeline tasks |

### Schema Change

```sql
-- Add new specialists to worker_health
INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, priority_score)
VALUES 
    ('@security-1', 'security', 'senior', 3, 'online', 70),
    ('@ux-designer', 'ux', 'senior', 3, 'online', 70),
    ('@data-analyst', 'data', 'senior', 3, 'online', 70);
```

### New SOP Files

**`library/prompts/security_auditor.md`:**
```markdown
# Security Auditor SOP

## Role
Scan for security vulnerabilities before QA review.

## Checklist
1. Run `npm audit` / `pip audit`
2. Check for `.env` leaks in code
3. Scan for SQL injection patterns
4. Verify no hardcoded secrets
5. Check dependency vulnerabilities

## Output
- PASS/FAIL with findings list
- Block deployment if CRITICAL issues found
```

**`library/prompts/ux_auditor.md`:**
```markdown
# UX/A11y Auditor SOP

## Role
Verify accessibility and responsive design.

## Checklist
1. Verify semantic HTML structure
2. Check ARIA labels on interactive elements
3. Test keyboard navigation flow
4. Verify color contrast ratios
5. Mobile viewport responsiveness

## Output
- A11y score (0-100)
- List of violations with severity
```

### Estimated Effort
- Schema: +5 lines
- SOPs: +2 files (~100 lines each)
- **Total: ~30 minutes**

---

## Feature 2: ChatOps Integration

**Cost:** 🟡 Medium (~150 lines)
**Gain:** 🔵 High (Team-friendly interface)

### Architecture

```
Slack Command → Flask Webhook → vibe_admin.py → SQLite
```

### Commands

| Command | Action | Example |
|---------|--------|---------|
| `/vibe status` | Show active workers/tasks | Workers: 5 active, Tasks: 12 pending |
| `/vibe retry <id>` | Retry failed task | Task #42 reset to pending |
| `/vibe approve <id>` | Approve high-risk task | Task #42 approved |
| `/vibe dlq` | Show dead letter tasks | 3 tasks in DLQ |
| `/vibe worker <id>` | Show worker status | @backend-1: 2 active tasks |

### Implementation: `vibe_chatops.py`

```python
"""
Vibe ChatOps - Slack/Discord Integration
"""
from flask import Flask, request, jsonify
import sqlite3
import os

app = Flask(__name__)
DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/slack/command', methods=['POST'])
def slack_command():
    text = request.form.get('text', '').strip()
    
    if text == 'status':
        return get_status_summary()
    elif text.startswith('retry '):
        task_id = text.split()[1]
        return retry_task(task_id)
    elif text.startswith('approve '):
        task_id = text.split()[1]
        return approve_task(task_id)
    elif text == 'dlq':
        return get_dlq_summary()
    else:
        return "Usage: status | retry <id> | approve <id> | dlq"

def get_status_summary():
    conn = get_db()
    workers = conn.execute("""
        SELECT lane, COUNT(*) as count, SUM(active_tasks) as load
        FROM worker_health WHERE status='online' GROUP BY lane
    """).fetchall()
    
    tasks = conn.execute("""
        SELECT status, COUNT(*) as count FROM tasks GROUP BY status
    """).fetchall()
    conn.close()
    
    lines = ["📊 *Vibe Status*"]
    lines.append("\n*Workers:*")
    for w in workers:
        lines.append(f"  • {w['lane']}: {w['count']} ({w['load']} active)")
    lines.append("\n*Tasks:*")
    for t in tasks:
        lines.append(f"  • {t['status']}: {t['count']}")
    
    return "\n".join(lines)

def retry_task(task_id):
    # Call vibe_admin logic
    from vibe_admin import retry_task as admin_retry
    admin_retry(task_id)
    return f"🔄 Task #{task_id} reset to pending"

def approve_task(task_id):
    from vibe_admin import approve_task as admin_approve
    admin_approve(task_id)
    return f"✅ Task #{task_id} approved"

def get_dlq_summary():
    conn = get_db()
    dlq = conn.execute("""
        SELECT id, goal, lane, last_error_type FROM tasks 
        WHERE status='dead_letter' ORDER BY created_at DESC LIMIT 5
    """).fetchall()
    conn.close()
    
    if not dlq:
        return "✅ Dead Letter Queue is empty"
    
    lines = [f"💀 *{len(dlq)} Dead Letter Tasks:*"]
    for t in dlq:
        lines.append(f"  • #{t['id']} ({t['lane']}): {t['goal'][:30]}...")
    return "\n".join(lines)

if __name__ == '__main__':
    app.run(port=5001)
```

### Deployment
1. Run: `python vibe_chatops.py`
2. Configure Slack App slash command to `https://your-server:5001/slack/command`

### Estimated Effort
- New file: ~150 lines
- Flask dependency
- **Total: ~2 hours**

---

## Feature 3: Dashboard (Streamlit)

**Cost:** 🟡 Medium (~200 lines)
**Gain:** 🔵 High (Visibility)

### Architecture

```
Streamlit ← SQLite (Read-Only) → Real-time Refresh
```

### Dashboard Sections

| Section | Data Source | Refresh |
|---------|-------------|---------|
| Metrics Bar | worker_health, tasks | 5s |
| Active Tasks | tasks (in_progress) | 5s |
| Worker Pool | worker_health | 10s |
| Dead Letter Queue | tasks (dead_letter) | 10s |
| Task History | task_history | Manual |

### Implementation: `dashboard.py`

```python
"""
Vibe Coding Factory Floor - Streamlit Dashboard
Run: streamlit run dashboard.py
"""
import streamlit as st
import sqlite3
import pandas as pd
import time

DB_PATH = "vibe_coding.db"

st.set_page_config(
    page_title="Vibe Factory Floor",
    page_icon="🏭",
    layout="wide"
)

def get_conn():
    return sqlite3.connect(DB_PATH)

# Header
st.title("🏭 Vibe Coding Factory Floor")
st.caption(f"V3.3 Titanium Master | Last refresh: {time.strftime('%H:%M:%S')}")

# Metrics Row
col1, col2, col3, col4 = st.columns(4)

conn = get_conn()
with col1:
    active = conn.execute("""
        SELECT COUNT(*) FROM worker_health WHERE active_tasks > 0
    """).fetchone()[0]
    total = conn.execute("SELECT COUNT(*) FROM worker_health").fetchone()[0]
    st.metric("Active Workers", f"{active}/{total}")

with col2:
    pending = conn.execute("""
        SELECT COUNT(*) FROM tasks WHERE status='pending'
    """).fetchone()[0]
    st.metric("Pending Tasks", pending)

with col3:
    in_progress = conn.execute("""
        SELECT COUNT(*) FROM tasks WHERE status='in_progress'
    """).fetchone()[0]
    st.metric("In Progress", in_progress)

with col4:
    dlq = conn.execute("""
        SELECT COUNT(*) FROM tasks WHERE status='dead_letter'
    """).fetchone()[0]
    if dlq > 0:
        st.metric("Dead Letter", dlq, delta=f"⚠️ {dlq} stuck")
    else:
        st.metric("Dead Letter", 0, delta="✅ Clear")

# Worker Pool
st.subheader("👷 Worker Pool")
workers_df = pd.read_sql("""
    SELECT worker_id, lane, tier, active_tasks, capacity_limit, status
    FROM worker_health ORDER BY lane, tier DESC
""", conn)
st.dataframe(workers_df, use_container_width=True)

# Active Tasks (Kanban-style)
st.subheader("📋 Active Tasks")
tabs = st.tabs(["Pending", "In Progress", "Review", "Completed"])

with tabs[0]:
    pending_df = pd.read_sql("""
        SELECT id, lane, goal, worker_id, priority, created_at
        FROM tasks WHERE status='pending' ORDER BY created_at DESC LIMIT 20
    """, conn)
    st.dataframe(pending_df, use_container_width=True)

with tabs[1]:
    progress_df = pd.read_sql("""
        SELECT id, lane, goal, worker_id, priority, updated_at
        FROM tasks WHERE status='in_progress' ORDER BY updated_at DESC LIMIT 20
    """, conn)
    st.dataframe(progress_df, use_container_width=True)

with tabs[2]:
    review_df = pd.read_sql("""
        SELECT id, lane, goal, worker_id, priority
        FROM tasks WHERE status='review_needed' ORDER BY created_at DESC LIMIT 20
    """, conn)
    st.dataframe(review_df, use_container_width=True)

with tabs[3]:
    completed_df = pd.read_sql("""
        SELECT id, lane, goal, worker_id, updated_at
        FROM tasks WHERE status='completed' ORDER BY updated_at DESC LIMIT 20
    """, conn)
    st.dataframe(completed_df, use_container_width=True)

# Dead Letter Queue (Alert)
if dlq > 0:
    st.subheader("💀 Dead Letter Queue")
    st.error(f"{dlq} tasks have failed permanently and need manual review!")
    dlq_df = pd.read_sql("""
        SELECT id, lane, goal, last_error_type, attempt_count, created_at
        FROM tasks WHERE status='dead_letter' ORDER BY created_at DESC
    """, conn)
    st.dataframe(dlq_df, use_container_width=True)
    
    # Retry button
    task_id = st.text_input("Task ID to retry:")
    if st.button("🔄 Retry Task"):
        if task_id:
            conn.execute("""
                UPDATE tasks SET status='pending', attempt_count=0 
                WHERE id=?
            """, (task_id,))
            conn.commit()
            st.success(f"Task #{task_id} reset to pending!")
            st.rerun()

conn.close()

# Auto-refresh
st.markdown("---")
if st.checkbox("Auto-refresh (5s)", value=True):
    time.sleep(5)
    st.rerun()
```

### Deployment
```bash
pip install streamlit pandas
streamlit run dashboard.py
```

### Estimated Effort
- New file: ~200 lines
- Streamlit dependency
- **Total: ~2 hours**

---

## Summary

### Files to Create/Modify

| File | Type | Lines |
|------|------|-------|
| `migrations/v25_schema.sql` | MODIFY | +5 |
| `library/prompts/security_auditor.md` | NEW | ~100 |
| `library/prompts/ux_auditor.md` | NEW | ~100 |
| `vibe_chatops.py` | NEW | ~150 |
| `dashboard.py` | NEW | ~200 |
| `requirements.txt` | MODIFY | +2 |

### Dependencies

```
flask>=2.0
streamlit>=1.28
pandas>=2.0
```

### Total Estimated Effort

| Feature | Time |
|---------|------|
| Specialist Workers | 30 min |
| ChatOps | 2 hours |
| Dashboard | 2 hours |
| **Total** | **~4.5 hours** |

---

## Architecture After V3.4

```
┌─────────────────────────────────────────────────────────────┐
│                    VIBE CODING V3.4                        │
├─────────────────────────────────────────────────────────────┤
│  User Interfaces                                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   CLI       │  │  ChatOps    │  │ Dashboard   │         │
│  │ vibe_admin  │  │ /vibe cmd   │  │ Streamlit   │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
├─────────┴────────────────┴────────────────┴─────────────────┤
│                    SQLite (WAL Mode)                        │
│           tasks | worker_health | task_history              │
├─────────────────────────────────────────────────────────────┤
│  Workers                                                     │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐ ┌────────┐  │
│  │Backend │ │Frontend│ │   QA   │ │ Security │ │   UX   │  │
│  │ @b-1   │ │ @f-1   │ │ @qa-1  │ │ @sec-1   │ │ @ux-1  │  │
│  └────────┘ └────────┘ └────────┘ └──────────┘ └────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

**Status:** Awaiting Approval
