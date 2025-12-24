import unittest
import os
import shutil
import sqlite3
import vibe_controller
from vibe_controller import expand_task_context

class TestV51Gatekeeper(unittest.TestCase):
    
    def setUp(self):
        # Setup temp environment
        self.test_skills_dir = "tests/temp_skills_v51"
        self.test_domains_dir = "skills/domains" # Use actual domains
        
        os.makedirs(self.test_skills_dir, exist_ok=True)
        # Create backend skill
        with open(os.path.join(self.test_skills_dir, "backend.md"), "w") as f:
            f.write("Backend Skills")
            
        # Patch controller constants
        vibe_controller.SKILLS_DIR = self.test_skills_dir
        
        # Setup in-memory DB
        self.conn = sqlite3.connect(":memory:")
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("""
            CREATE TABLE tasks (
                id INTEGER PRIMARY KEY,
                goal TEXT,
                lane TEXT,
                domain TEXT,
                context_files TEXT,
                updated_at INTEGER
            )
        """)

    def tearDown(self):
        if os.path.exists(self.test_skills_dir):
            shutil.rmtree(self.test_skills_dir)
        self.conn.close()

    def test_safety_switch_upstream_error(self):
        """Verify Controller returns Upstream Ingestion Failure error for missing domain."""
        self.conn.execute("""
            INSERT INTO tasks (id, goal, lane, domain, context_files)
            VALUES (1, 'Build Secret App', 'backend', 'missing_domain', '[]')
        """)
        
        task = self.conn.execute("SELECT * FROM tasks WHERE id=1").fetchone()
        
        with self.assertRaises(FileNotFoundError) as cm:
            expand_task_context(self.conn, dict(task))
        
        error_msg = str(cm.exception)
        self.assertIn("CRITICAL", error_msg)
        self.assertIn("Upstream Ingestion Failure", error_msg)
        self.assertIn("Architect must resolve domain", error_msg)

if __name__ == '__main__':
    unittest.main()
