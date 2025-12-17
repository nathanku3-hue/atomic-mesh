import sqlite3
import os

# Use environment variable or default to mesh.db
db_path = os.environ.get('ATOMIC_MESH_DB', 'mesh.db')

with sqlite3.connect(db_path) as conn:
    conn.execute("UPDATE tasks SET status='pending', worker_id=NULL, retry_count=retry_count+1 WHERE id=1")  # SAFETY-ALLOW: status-write (debug script)
    conn.commit()

print("Task 1 Reset")
