import unittest
import os
import shutil
import vibe_controller
from unittest.mock import patch
import io
import sys

class TestV52Loopback(unittest.TestCase):
    
    def setUp(self):
        # Setup temp environment
        self.test_skills_dir = "tests/temp_skills_v52_loop"
        self.test_domains_dir = os.path.join(self.test_skills_dir, "domains")
        self.audit_file = "AUDIT.log"
        
        os.makedirs(self.test_domains_dir, exist_ok=True)
        
        # Create required files for main_loop mock task
        with open(os.path.join(self.test_skills_dir, "backend.md"), "w") as f:
            f.write("Backend Rules")
        with open(os.path.join(self.test_domains_dir, "medicine.md"), "w") as f:
            f.write("Medicine Rules")
            
        # Patch controller constants
        vibe_controller.SKILLS_DIR = self.test_skills_dir
        vibe_controller.DOMAINS_DIR = self.test_domains_dir
        vibe_controller.audit_file = self.audit_file # wait, audit_file is local var in main_loop? 
        # In main_loop: audit_file = "AUDIT.log"
        # So it writes to CWD/AUDIT.log. That's fine, I'll clean it up.

    def tearDown(self):
        if os.path.exists(self.test_skills_dir):
            shutil.rmtree(self.test_skills_dir)
        if os.path.exists(self.audit_file):
            os.remove(self.audit_file)

    @patch('vibe_controller.run_librarian_review')
    def test_rejection_feedback_loop(self, mock_librarian):
        """Verify Rejection Feedback Loop writes to Audit Log and prints Loopback."""
        # 1. Mock the Librarian to REJECT
        rejection_reason = "Test Rejection Reason: Missing Ref ID"
        mock_librarian.return_value = {"status": "REJECTED", "reason": rejection_reason}
        
        # 2. Capture Stdout
        captured_output = io.StringIO()
        sys.stdout = captured_output
        
        # 3. Run Main Loop
        try:
            vibe_controller.main_loop()
        finally:
            sys.stdout = sys.__stdout__ # Restore
            
        output = captured_output.getvalue()
        
        # 4. Assertions
        # Check Loopback Print
        self.assertIn("🔄 LOOPBACK", output)
        self.assertIn(rejection_reason, output)
        
        # Check Audit Log
        self.assertTrue(os.path.exists(self.audit_file), "AUDIT.log should be created")
        with open(self.audit_file, "r") as f:
            log_content = f.read()
        
        self.assertIn("REJECTED Task #102", log_content)
        self.assertIn(rejection_reason, log_content)

if __name__ == "__main__":
    unittest.main()
