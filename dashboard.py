"""
Vibe Coding Factory Floor - Streamlit Dashboard
================================================
Real-time monitoring dashboard for the Vibe Coding system.

Usage:
    pip install streamlit pandas
    streamlit run dashboard.py

Features:
    - Live metrics (workers, tasks, DLQ)
    - Worker pool health table
    - Task Kanban (Pending/In Progress/Review/Completed)
    - Dead Letter Queue alerts with retry button
    - Auto-refresh (5s interval)
"""

import streamlit as st
import sqlite3
import pandas as pd
import time
import os

DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")

# Page config
st.set_page_config(
    page_title="Vibe Factory Floor",
    page_icon="🏭",
    layout="wide",
    initial_sidebar_state="collapsed"
)

# Custom CSS for dark theme
st.markdown("""
<style>
    .stMetric {
        background-color: #1e1e1e;
        padding: 10px;
        border-radius: 5px;
    }
    .error-box {
        background-color: #ff4b4b;
        padding: 10px;
        border-radius: 5px;
        color: white;
    }
</style>
""", unsafe_allow_html=True)


def get_conn():
    """Get database connection."""
    try:
        return sqlite3.connect(DB_PATH)
    except Exception as e:
        st.error(f"❌ Database connection failed: {e}")
        return None


def main():
    # Header
    st.title("🏭 Vibe Coding Factory Floor")
    st.caption(f"V3.4 Final Master | DB: {DB_PATH} | Last refresh: {time.strftime('%H:%M:%S')}")
    
    conn = get_conn()
    if not conn:
        st.stop()
    
    # === Metrics Row ===
    st.markdown("---")
    col1, col2, col3, col4, col5 = st.columns(5)
    
    with col1:
        total_workers = pd.read_sql("SELECT COUNT(*) as c FROM worker_health", conn).iloc[0]['c']
        active_workers = pd.read_sql("SELECT COUNT(*) as c FROM worker_health WHERE active_tasks > 0", conn).iloc[0]['c']
        st.metric("👷 Workers", f"{active_workers}/{total_workers}", delta="active")
    
    with col2:
        pending = pd.read_sql("SELECT COUNT(*) as c FROM tasks WHERE status='pending'", conn).iloc[0]['c']
        st.metric("⏳ Pending", pending)
    
    with col3:
        in_progress = pd.read_sql("SELECT COUNT(*) as c FROM tasks WHERE status='in_progress'", conn).iloc[0]['c']
        st.metric("🔄 In Progress", in_progress)
    
    with col4:
        completed = pd.read_sql("SELECT COUNT(*) as c FROM tasks WHERE status='completed'", conn).iloc[0]['c']
        st.metric("✅ Completed", completed)
    
    with col5:
        dlq = pd.read_sql("SELECT COUNT(*) as c FROM tasks WHERE status='dead_letter'", conn).iloc[0]['c']
        if dlq > 0:
            st.metric("💀 Dead Letter", dlq, delta=f"⚠️ ALERT", delta_color="inverse")
        else:
            st.metric("💀 Dead Letter", 0, delta="✅ Clear")
    
    # === Worker Pool ===
    st.markdown("---")
    st.subheader("👷 Worker Pool")
    
    workers_df = pd.read_sql("""
        SELECT 
            worker_id as "Worker",
            lane as "Lane",
            tier as "Tier",
            active_tasks as "Active",
            capacity_limit as "Capacity",
            status as "Status",
            CASE WHEN active_tasks >= capacity_limit THEN '🔴' 
                 WHEN active_tasks > 0 THEN '🟡' 
                 ELSE '🟢' END as "Load"
        FROM worker_health 
        ORDER BY lane, tier DESC
    """, conn)
    
    st.dataframe(workers_df, use_container_width=True, hide_index=True)
    
    # === Task Kanban ===
    st.markdown("---")
    st.subheader("📋 Task Kanban")
    
    tabs = st.tabs(["⏳ Pending", "🔄 In Progress", "👀 Review", "✅ Completed", "🔒 Blocked"])
    
    with tabs[0]:
        pending_df = pd.read_sql("""
            SELECT id as "ID", lane as "Lane", 
                   substr(goal, 1, 50) as "Goal", 
                   worker_id as "Worker",
                   priority as "Priority"
            FROM tasks WHERE status='pending' 
            ORDER BY priority DESC, created_at ASC LIMIT 20
        """, conn)
        if not pending_df.empty:
            st.dataframe(pending_df, use_container_width=True, hide_index=True)
        else:
            st.info("No pending tasks")
    
    with tabs[1]:
        progress_df = pd.read_sql("""
            SELECT id as "ID", lane as "Lane",
                   substr(goal, 1, 50) as "Goal",
                   worker_id as "Worker",
                   priority as "Priority"
            FROM tasks WHERE status='in_progress'
            ORDER BY updated_at DESC LIMIT 20
        """, conn)
        if not progress_df.empty:
            st.dataframe(progress_df, use_container_width=True, hide_index=True)
        else:
            st.info("No tasks in progress")
    
    with tabs[2]:
        review_df = pd.read_sql("""
            SELECT id as "ID", lane as "Lane",
                   substr(goal, 1, 50) as "Goal",
                   worker_id as "Worker"
            FROM tasks WHERE status='review_needed'
            ORDER BY created_at ASC LIMIT 20
        """, conn)
        if not review_df.empty:
            st.dataframe(review_df, use_container_width=True, hide_index=True)
        else:
            st.info("No tasks awaiting review")
    
    with tabs[3]:
        completed_df = pd.read_sql("""
            SELECT id as "ID", lane as "Lane",
                   substr(goal, 1, 50) as "Goal",
                   worker_id as "Worker"
            FROM tasks WHERE status='completed'
            ORDER BY updated_at DESC LIMIT 20
        """, conn)
        if not completed_df.empty:
            st.dataframe(completed_df, use_container_width=True, hide_index=True)
        else:
            st.info("No completed tasks yet")
    
    with tabs[4]:
        blocked_df = pd.read_sql("""
            SELECT id as "ID", lane as "Lane",
                   substr(goal, 1, 50) as "Goal",
                   worker_id as "Worker"
            FROM tasks WHERE status='blocked'
            ORDER BY created_at ASC LIMIT 20
        """, conn)
        if not blocked_df.empty:
            st.dataframe(blocked_df, use_container_width=True, hide_index=True)
        else:
            st.info("No blocked tasks")
    
    # === Dead Letter Queue (Alert Section) ===
    if dlq > 0:
        st.markdown("---")
        st.subheader("💀 Dead Letter Queue")
        st.error(f"⚠️ {dlq} tasks have failed permanently and need manual review!")
        
        dlq_df = pd.read_sql("""
            SELECT 
                id as "ID",
                lane as "Lane",
                substr(goal, 1, 40) as "Goal",
                last_error_type as "Error Type",
                attempt_count as "Attempts",
                (strftime('%s', 'now') - updated_at) / 3600 as "Hours Dead"
            FROM tasks WHERE status='dead_letter'
            ORDER BY updated_at ASC
        """, conn)
        st.dataframe(dlq_df, use_container_width=True, hide_index=True)
        
        # Retry interface
        col_retry, col_purge = st.columns(2)
        with col_retry:
            task_id = st.text_input("Task ID to retry:", key="retry_id")
            if st.button("🔄 Retry Task", type="primary"):
                if task_id:
                    try:
                        conn.execute("UPDATE tasks SET status='pending', attempt_count=0, updated_at=strftime('%s', 'now') WHERE id=?", (task_id,))  # SAFETY-ALLOW: status-write
                        conn.commit()
                        st.success(f"✅ Task #{task_id} reset to pending!")
                        time.sleep(1)
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ Failed: {e}")
        
        with col_purge:
            if st.button("🗑️ Purge All DLQ", type="secondary"):
                st.warning("⚠️ This will delete all dead letter tasks!")
                if st.button("Confirm Purge"):
                    conn.execute("DELETE FROM tasks WHERE status='dead_letter'")
                    conn.commit()
                    st.success("🧹 Dead letter queue purged")
                    st.rerun()
    
    conn.close()
    
    # === Auto-refresh ===
    st.markdown("---")
    auto_refresh = st.checkbox("Auto-refresh (5s)", value=False)
    if auto_refresh:
        time.sleep(5)
        st.rerun()


if __name__ == "__main__":
    main()
