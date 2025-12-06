"""
Atomic Mesh v8.5.1 - Database Connection Pool
Eliminates N+1 connection problem across modules.

BEFORE: Each module called sqlite3.connect() independently
        - 16+ connection sites
        - No pooling
        - Potential connection leaks on exception

AFTER:  Single connection pool with context manager
        - Thread-safe
        - Automatic cleanup
        - WAL mode enforced once
"""

import sqlite3
import os
import threading
from contextlib import contextmanager
from typing import Optional

# =============================================================================
# CONFIGURATION
# =============================================================================

DB_FILE = os.getenv("ATOMIC_MESH_DB", os.path.join(os.getcwd(), "mesh.db"))

# Thread-local storage for connections
_local = threading.local()

# Connection settings
_connection_settings = {
    "check_same_thread": False,  # Allow cross-thread access (with care)
    "timeout": 30.0,             # 30 second timeout
    "isolation_level": None,     # Autocommit mode for performance
}


# =============================================================================
# CONNECTION POOL
# =============================================================================

def _get_connection() -> sqlite3.Connection:
    """
    Get or create a thread-local database connection.
    Uses WAL mode for better concurrent access.
    """
    if not hasattr(_local, 'connection') or _local.connection is None:
        conn = sqlite3.connect(DB_FILE, **_connection_settings)
        
        # Enable WAL mode for better concurrent access
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA cache_size=10000")
        
        # Row factory for dict-like access
        conn.row_factory = sqlite3.Row
        
        _local.connection = conn
    
    return _local.connection


def close_connection():
    """Explicitly close the thread-local connection."""
    if hasattr(_local, 'connection') and _local.connection is not None:
        try:
            _local.connection.close()
        except:
            pass
        _local.connection = None


@contextmanager
def get_db():
    """
    Context manager for database access.
    
    Usage:
        with get_db() as conn:
            conn.execute("SELECT * FROM tasks")
            conn.commit()
    
    Benefits:
        - Automatic connection reuse within thread
        - Exception-safe (no leaks)
        - WAL mode enabled once
    """
    conn = _get_connection()
    try:
        yield conn
    except Exception as e:
        conn.rollback()
        raise
    # Note: We don't close here - connection is reused within thread


@contextmanager
def get_db_cursor():
    """
    Context manager that also provides a cursor.
    
    Usage:
        with get_db_cursor() as (conn, cur):
            cur.execute("SELECT * FROM tasks WHERE id=?", (task_id,))
            row = cur.fetchone()
    """
    with get_db() as conn:
        cur = conn.cursor()
        try:
            yield conn, cur
        finally:
            cur.close()


# =============================================================================
# QUERY HELPERS
# =============================================================================

def execute_query(sql: str, params: tuple = None, fetch: str = "all") -> Optional[list]:
    """
    Execute a query and return results.
    
    Args:
        sql: The SQL query
        params: Optional parameters tuple
        fetch: "all", "one", or "none"
    
    Returns:
        List of rows, single row, or None
    """
    with get_db() as conn:
        cur = conn.execute(sql, params or ())
        
        if fetch == "all":
            return cur.fetchall()
        elif fetch == "one":
            return cur.fetchone()
        else:
            conn.commit()
            return None


def execute_many(sql: str, params_list: list) -> int:
    """
    Execute a query with multiple parameter sets (batch insert/update).
    
    Args:
        sql: The SQL query with placeholders
        params_list: List of parameter tuples
    
    Returns:
        Number of rows affected
    """
    with get_db() as conn:
        cur = conn.executemany(sql, params_list)
        conn.commit()
        return cur.rowcount


# =============================================================================
# SCHEMA INITIALIZATION
# =============================================================================

def init_db():
    """Initialize database schema if not exists."""
    with get_db() as conn:
        # Core tables
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS config (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                desc TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                priority INTEGER DEFAULT 1,
                worker_id TEXT,
                retry_count INTEGER DEFAULT 0,
                output TEXT,
                created_at INTEGER,
                updated_at INTEGER
            );
            
            CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
            CREATE INDEX IF NOT EXISTS idx_tasks_type ON tasks(type);
        """)
        conn.commit()


# =============================================================================
# CLEANUP
# =============================================================================

import atexit

@atexit.register
def _cleanup():
    """Clean up connections on process exit."""
    close_connection()
