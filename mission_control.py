"""
🚀 Atomic Mesh: Mission Control
================================
A real-time GUI dashboard for monitoring the Atomic Mesh swarm.

Features:
- Decision Matrix (Red/Yellow/Green status)
- Live Operations (Active workers)
- Roadmap (Pending tasks)
- COT Stream viewer
- Quick actions (Open Spec, Tuning, Logs)

Run: streamlit run mission_control.py
"""

import streamlit as st
import sqlite3
import pandas as pd
import subprocess
import os
import time
from datetime import datetime

# CONFIG
DB_FILE = "mesh.db"
LOG_DIR = "logs"
DOCS_DIR = os.path.join(os.path.dirname(__file__), "..", "Finance", "openstock-v2", "docs")
REFRESH_RATE = 2

st.set_page_config(
    page_title="Atomic Mission Control", 
    layout="wide", 
    page_icon="🚀",
    initial_sidebar_state="collapsed"
)

# Custom CSS for better visuals
st.markdown("""
<style>
    .stMetric {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        padding: 15px;
        border-radius: 10px;
        border: 1px solid #0f3460;
    }
    .stExpander {
        background: #1a1a2e;
        border-radius: 8px;
    }
    div[data-testid="stMetricValue"] {
        font-size: 2rem;
    }
</style>
""", unsafe_allow_html=True)

# --- HELPERS ---
def get_db():
    return sqlite3.connect(DB_FILE, check_same_thread=False)

def open_file(path):
    """Opens file in VS Code or default editor."""
    try:
        if os.name == 'nt':  # Windows
            # Try VS Code first
            result = subprocess.run(["code", path], capture_output=True)
            if result.returncode != 0:
                os.startfile(path)
        else:  # Mac/Linux
            subprocess.call(('open', path))
        st.success(f"Opened: {os.path.basename(path)}")
    except Exception as e:
        st.error(f"Could not open file: {e}")

def get_latest_log():
    """Finds the latest daily log file."""
    try:
        if not os.path.exists(LOG_DIR):
            return None
        files = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR) if f.endswith('.log')]
        if not files:
            return None
        return max(files, key=os.path.getctime)
    except Exception:
        return None

def get_status_icon(status):
    icons = {
        "completed": "✅",
        "in_progress": "🔄",
        "pending": "⏳",
        "failed": "❌"
    }
    return icons.get(status, "❓")

def get_type_icon(task_type):
    icons = {
        "backend": "⚙️",
        "frontend": "🎨",
        "qa": "🛡️"
    }
    return icons.get(task_type, "📦")

# --- UI HEADER ---
st.title("🚀 Atomic Mesh: Mission Control")
st.caption(f"Last refresh: {datetime.now().strftime('%H:%M:%S')} | Auto-refresh every {REFRESH_RATE}s")

# --- SIDEBAR: Quick Actions ---
with st.sidebar:
    st.header("⚡ Quick Actions")
    
    if st.button("📄 Open ACTIVE_SPEC.md", use_container_width=True):
        open_file("docs/ACTIVE_SPEC.md")
    
    if st.button("📋 Open DECISION_LOG.md", use_container_width=True):
        open_file("docs/DECISION_LOG.md")
    
    if st.button("🎛️ Open TUNING.md", use_container_width=True):
        open_file("docs/TUNING.md")
    
    st.divider()
    
    if st.button("🚨 NUKE QUEUE (Emergency)", use_container_width=True, type="primary"):
        with get_db() as conn:
            count = conn.execute("DELETE FROM tasks WHERE status='pending'").rowcount
            conn.commit()
        st.warning(f"🚨 Deleted {count} pending tasks!")
    
    st.divider()
    st.header("📊 Statistics")
    
    with get_db() as conn:
        stats = pd.read_sql("""
            SELECT 
                status,
                COUNT(*) as count
            FROM tasks 
            GROUP BY status
        """, conn)
    
    for _, row in stats.iterrows():
        st.metric(row['status'].title(), row['count'])

# --- MAIN LAYOUT ---
col1, col2, col3 = st.columns([1, 1, 1])

# --- 1. DECISION MATRIX (Red/Yellow/Green) ---
with col1:
    st.subheader("🚦 Decision Matrix")
    
    with get_db() as conn:
        # RED: Failed Tasks or High Priority Pending
        red_tasks = pd.read_sql("""
            SELECT * FROM tasks 
            WHERE status='failed' OR (status='pending' AND priority >= 8)
            ORDER BY id DESC
        """, conn)
        
        # YELLOW: Standard Pending
        yellow_tasks = pd.read_sql("""
            SELECT * FROM tasks 
            WHERE status='pending' AND priority < 8
            ORDER BY priority DESC, id ASC
            LIMIT 10
        """, conn)
        
        # GREEN: Recent Completed
        green_tasks = pd.read_sql("""
            SELECT * FROM tasks 
            WHERE status='completed'
            ORDER BY updated_at DESC
            LIMIT 5
        """, conn)
    
    # RED ZONE
    if not red_tasks.empty:
        st.error(f"🛑 {len(red_tasks)} URGENT ACTIONS REQUIRED")
        for _, row in red_tasks.iterrows():
            with st.expander(f"🔴 Task {row['id']}: {row['desc'][:50]}...", expanded=True):
                st.write(f"**Type:** {row['type'].upper()} | **Priority:** P{row['priority']}")
                if row['status'] == 'failed':  # SAFETY-ALLOW: status-write
                    st.code(row['output'] if row['output'] else "No error output", language="bash")
                col_a, col_b = st.columns(2)
                with col_a:
                    if st.button("📝 Open Spec", key=f"spec_{row['id']}"):
                        open_file("docs/ACTIVE_SPEC.md")
                with col_b:
                    if st.button("🔧 Open Tuning", key=f"tune_{row['id']}"):
                        open_file("docs/TUNING.md")
    
    # YELLOW ZONE
    elif not yellow_tasks.empty:
        st.warning(f"⏳ {len(yellow_tasks)} Tasks Pending")
        for _, row in yellow_tasks.head(3).iterrows():
            st.info(f"**{row['id']}** {get_type_icon(row['type'])} {row['desc'][:60]}...")
    
    # GREEN ZONE
    else:
        st.success("✅ System Nominal. No Blockers.")
    
    # Recent Completions
    if not green_tasks.empty:
        with st.expander("✅ Recently Completed"):
            for _, row in green_tasks.iterrows():
                st.write(f"**{row['id']}** {get_type_icon(row['type'])} {row['desc'][:50]}...")

# --- 2. LIVE STREAMS (Active Workers) ---
with col2:
    st.subheader("⚡ Active Operations")
    
    with get_db() as conn:
        active = pd.read_sql("""
            SELECT * FROM tasks 
            WHERE status='in_progress'
            ORDER BY updated_at DESC
        """, conn)
    
    # KPIs
    be_count = len(active[active['type'] == 'backend']) if not active.empty else 0
    fe_count = len(active[active['type'] == 'frontend']) if not active.empty else 0
    qa_count = len(active[active['type'] == 'qa']) if not active.empty else 0
    
    kpi1, kpi2, kpi3 = st.columns(3)
    with kpi1:
        st.metric("⚙️ Backend", f"{be_count}/2")
    with kpi2:
        st.metric("🎨 Frontend", fe_count)
    with kpi3:
        st.metric("🛡️ QA", qa_count)
    
    st.divider()
    
    # Active Task Details
    if not active.empty:
        for _, row in active.iterrows():
            with st.container():
                st.info(f"🔨 **{row['type'].upper()}** - Task {row['id']}")
                st.caption(f"\"{row['desc'][:120]}...\"")
                st.divider()
    else:
        st.write("🌙 No active workers. Swarm is idle.")
    
    # COT LIVE STREAM
    st.subheader("🧠 Chain of Thought")
    log_file = get_latest_log()
    
    if log_file:
        with st.expander("📜 Live COT Stream (Last 25 lines)", expanded=False):
            try:
                with open(log_file, "r", encoding="utf-8") as f:
                    lines = f.readlines()[-25:]
                st.code("".join(lines), language="bash")
            except Exception:
                st.warning("Log file busy or empty.")
        
        if st.button("📂 Open Full Log File"):
            open_file(log_file)
    else:
        st.caption("No log files found yet.")

# --- 3. ROADMAP (The Future) ---
with col3:
    st.subheader("🗺️ Mission Roadmap")
    
    with get_db() as conn:
        roadmap = pd.read_sql("""
            SELECT id, type, desc, deps, priority 
            FROM tasks 
            WHERE status='pending' 
            ORDER BY priority DESC, id ASC 
            LIMIT 8
        """, conn)
    
    if not roadmap.empty:
        for idx, row in roadmap.iterrows():
            icon = get_type_icon(row['type'])
            priority_badge = f"P{row['priority']}" if row['priority'] > 1 else ""
            
            with st.container():
                st.markdown(f"**{row['id']}** {icon} {priority_badge}")
                st.write(row['desc'][:80] + ("..." if len(row['desc']) > 80 else ""))
                
                if row['deps'] != '[]':
                    st.caption(f"⏳ Waiting on: {row['deps']}")
                
                st.divider()
    else:
        st.write("🎯 No missions queued. Ready for new objectives.")
    
    # Artifacts
    st.subheader("📦 Shared Artifacts")
    with get_db() as conn:
        try:
            artifacts = pd.read_sql("SELECT key, value FROM artifacts LIMIT 10", conn)
            if not artifacts.empty:
                for _, row in artifacts.iterrows():
                    st.code(f"{row['key']}: {row['value']}", language="yaml")
            else:
                st.caption("No artifacts stored yet.")
        except Exception:
            st.caption("Artifacts table not ready.")

# --- FOOTER ---
st.divider()
st.caption("🚀 Atomic Mesh Mission Control v1.0 | Press R to refresh | Streamlit Dashboard")

# --- AUTO REFRESH ---
time.sleep(REFRESH_RATE)
st.rerun()
