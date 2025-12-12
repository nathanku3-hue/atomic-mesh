import sqlite3
conn = sqlite3.connect('mesh.db')
conn.execute("UPDATE tasks SET status='pending', worker_id=NULL, retry_count=retry_count+1 WHERE id=1")  # SAFETY-ALLOW: status-write (debug script)
conn.commit()
print("Task 1 Reset")
