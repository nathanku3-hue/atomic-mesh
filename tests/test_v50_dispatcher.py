import unittest
import os
import shutil
import sqlite3
import vibe_controller
from vibe_controller import expand_task_context

class TestV50Dispatcher(unittest.TestCase):
    
    def setUp(self):
        # Setup temp environment
        self.test_skills_dir = "tests/temp_skills"
        self.test_domains_dir = "skills/domains" # Use actual or temp? 
        # For safety switch test, we need control. Let's redirect domains dir too if possible.
        # But vibe_controller uses relative path "skills/domains".
        # We'll need to patch os.path.join or create the dir relative to CWD.
        
        os.makedirs(self.test_skills_dir, exist_ok=True)
        # Create backend skill
        with open(os.path.join(self.test_skills_dir, "backend.md"), "w") as f:
            f.write("Backend Skills: Log everything")
            
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

    def test_supremacy_clause_injection(self):
        """Verify Supremacy Clause is injected when domain is present."""
        self.conn.execute("""
            INSERT INTO tasks (id, goal, lane, domain, context_files)
            VALUES (1, 'Build Patient DB', 'backend', 'medicine', '[]')
        """)
        
        task = self.conn.execute("SELECT * FROM tasks WHERE id=1").fetchone()
        
        # Need to ensure skills/domains/medicine.md exists (it was created in steps)
        # This test relies on the actual file system state for domains, which is fine for integration logic
        
        expand_task_context(self.conn, dict(task))
        
        updated_task = self.conn.execute("SELECT * FROM tasks WHERE id=1").fetchone()
        goal = updated_task['goal']
        
        self.assertIn("--- DOMAIN LENS: MEDICINE (ABSOLUTE RULES) ---", goal)
        self.assertIn("MED-01", goal)
        self.assertIn("*** SUPREMACY CLAUSE", goal)
        self.assertIn("DOMAIN RULES are ABSOLUTE and IMMUTABLE", goal)

    def test_safety_switch_missing_domain(self):
        """Verify FileNotFoundError is raised if domain file is missing."""
        self.conn.execute("""
            INSERT INTO tasks (id, goal, lane, domain, context_files)
            VALUES (2, 'Build Legal DB', 'backend', 'klingon_law', '[]')
        """)
        
        task = self.conn.execute("SELECT * FROM tasks WHERE id=2").fetchone()
        
        with self.assertRaises(FileNotFoundError) as cm:
            expand_task_context(self.conn, dict(task))
        
        self.assertIn("CRITICAL: Domain file 'klingon_law' missing", str(cm.exception))

if __name__ == '__main__':
    unittest.main()
