import unittest
import os
import shutil
import sqlite3
import vibe_controller
from vibe_controller import scan_for_secrets, inject_domain_and_lane_rules

class TestV51Controller(unittest.TestCase):
    
    def setUp(self):
        # Setup temp environment
        self.test_skills_dir = "tests/temp_skills_v51"
        self.test_domains_dir = os.path.join(self.test_skills_dir, "domains")
        
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

    def tearDown(self):
        if os.path.exists(self.test_skills_dir):
            shutil.rmtree(self.test_skills_dir)
    
    def test_security_regex_scan(self):
        """Verify hardcoded security scanner blocks API keys."""
        # Test AWS Key
        unsafe_diff = "var aws_key = 'AKIA1234567890ABCDEF';"
        usage, msg = scan_for_secrets(unsafe_diff)
        self.assertFalse(usage)
        self.assertIn("CRITICAL: Found secret pattern", msg)
        
        # Test OpenAI Key
        unsafe_diff = "api_key = 'sk-123456789012345678901234567890123456789012345678';"
        usage, msg = scan_for_secrets(unsafe_diff)
        self.assertFalse(usage)
        
        # Test Safe Diff
        safe_diff = "const safe = true;"
        usage, msg = scan_for_secrets(safe_diff)
        self.assertTrue(usage)

    def test_supremacy_clause_injection(self):
        """Verify V5.1 Logic injects Supremacy Clause correctly."""
        task = {"id": 1, "goal": "Build Med App", "lane": "backend", "domain": "medicine"}
        
        context_str, error = inject_domain_and_lane_rules(task, task["domain"], task["lane"])
        self.assertIsNone(error)
        
        self.assertIn("--- DOMAIN RULES (ABSOLUTE OVERRIDE) ---", context_str)
        self.assertIn("[MED-01] HIPAA Compliance.", context_str)

    def test_safety_switch_missing_domain(self):
        """Verify CRITICAL error using V5.1 structure."""
        task = {"id": 2, "goal": "Ghost Protocol", "lane": "backend", "domain": "missing_domain"}
        
        context_str, error = inject_domain_and_lane_rules(task, task["domain"], task["lane"])
        self.assertIsNotNone(error)
        self.assertIn("CRITICAL: Domain Rules 'missing_domain' NOT FOUND", error)

if __name__ == '__main__':
    unittest.main()
