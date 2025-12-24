import unittest
import os
import shutil
import sqlite3
import vibe_controller
from vibe_controller import scan_for_secrets, expand_task_context

class TestV51Controller(unittest.TestCase):
    
    def setUp(self):
        # Setup temp environment
        self.test_skills_dir = "tests/temp_skills_v51"
        self.test_domains_dir = "tests/temp_skills_v51/domains"
        
        os.makedirs(self.test_domains_dir, exist_ok=True)
        
        # Create backend skill
        with open(os.path.join(self.test_skills_dir, "backend.md"), "w") as f:
            f.write("Backend Rules: Do not log.")
            
        # Create domain skill
        with open(os.path.join(self.test_domains_dir, "medicine.md"), "w") as f:
            f.write("[MED-01] HIPAA Compliance.")
            
        # Patch controller constants
        vibe_controller.SKILLS_DIR = self.test_skills_dir
        vibe_controller.DOMAINS_DIR = self.test_domains_dir
        
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

    def test_security_regex_scan(self):
        """Verify hardcoded security scanner blocks API keys."""
        # Test AWS Key
        unsafe_diff = "var aws_key = 'AKIA1234567890ABCDEF';"
        usage, msg = scan_for_secrets(unsafe_diff)
        self.assertFalse(usage)
        self.assertIn("CRITICAL SECURITY ALERT", msg)
        
        # Test OpenAI Key
        unsafe_diff = "api_key = 'sk-123456789012345678901234567890123456789012345678';"
        usage, msg = scan_for_secrets(unsafe_diff)
        self.assertFalse(usage)
        self.assertIn("CRITICAL SECURITY ALERT", msg)
        
        # Test Safe Diff
        safe_diff = "const safe = true;"
        usage, msg = scan_for_secrets(safe_diff)
        self.assertTrue(usage)

    def test_supremacy_clause_injection(self):
        """Verify V5.1 Logic injects Supremacy Clause correctly."""
        self.conn.execute("""
            INSERT INTO tasks (id, goal, lane, domain, context_files)
            VALUES (1, 'Build Med App', 'backend', 'medicine', '[]')
        """)
        task = self.conn.execute("SELECT * FROM tasks WHERE id=1").fetchone()
        task_dict = dict(task)
        
        success = expand_task_context(self.conn, task_dict)
        self.assertTrue(success)
        
        # Fetch updated task from DB
        updated_task = self.conn.execute("SELECT * FROM tasks WHERE id=1").fetchone()
        updated_goal = updated_task['goal']
        
        self.assertIn("--- DOMAIN LENS: MEDICINE (ABSOLUTE RULES) ---", updated_goal)
        self.assertIn("*** SUPREMACY CLAUSE", updated_goal)
        self.assertIn("[MED-01] HIPAA Compliance.", updated_goal)

    def test_safety_switch_missing_domain(self):
        """Verify CRITICAL error using V5.1 structure."""
        self.conn.execute("""
            INSERT INTO tasks (id, goal, lane, domain, context_files)
            VALUES (2, 'Ghost Protocol', 'backend', 'missing_domain', '[]')
        """)
        task = self.conn.execute("SELECT * FROM tasks WHERE id=2").fetchone()
        task_dict = dict(task)
        
        # expand_task_context checks for error string return or raises
        # In current V5.1 implementation, it catches FileNotFoundError inside inject?
        # No, get_domain_rules raises FileNotFoundError. 
        # inject_domain_and_lane_rules catches it and returns error string.
        # expand_task_context prints SAFETY SWITCH and returns False.
        
        success = expand_task_context(self.conn, task_dict)
        self.assertFalse(success)

if __name__ == '__main__':
    unittest.main()
