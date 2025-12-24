import unittest
import os
import shutil
import vibe_controller
from vibe_controller import scan_for_secrets, validate_commit_message

class TestV52Features(unittest.TestCase):
    
    def test_security_scanner(self):
        """Verify hardcoded security scanner blocks API keys."""
        # Test AWS Key
        unsafe_diff = "var aws_key = 'AKIA1234567890ABCDEF';"
        usage, msg = scan_for_secrets(unsafe_diff)
        self.assertFalse(usage)
        self.assertIn("CRITICAL", msg)
        
        # Test OpenAI Key
        unsafe_diff = "api_key = 'sk-123456789012345678901234567890123456789012345678';"
        usage, msg = scan_for_secrets(unsafe_diff)
        self.assertFalse(usage)
        
        # Test Safe Diff
        safe_diff = "const safe = true;"
        usage, msg = scan_for_secrets(safe_diff)
        self.assertTrue(usage)

    def test_commit_validation_traceability(self):
        """Verify Commit Validator enforces Traceability Chain (Ref: #ID)."""
        task_id = 101
        
        # Valid commit
        valid_msg = "feat(auth): add hashing (Ref: #101)"
        is_valid, _ = validate_commit_message(valid_msg, task_id)
        self.assertTrue(is_valid)
        
        # Invalid: Missing Ref
        invalid_msg_no_ref = "feat(auth): add hashing"
        is_valid, msg = validate_commit_message(invalid_msg_no_ref, task_id)
        self.assertFalse(is_valid)
        self.assertIn("missing Traceability Tag", msg)
        
        # Invalid: Wrong ID
        invalid_msg_wrong_id = "feat(auth): add hashing (Ref: #999)"
        is_valid, msg = validate_commit_message(invalid_msg_wrong_id, task_id)
        self.assertFalse(is_valid)
        self.assertIn("missing Traceability Tag", msg)
        
        # Invalid: Bad Format (Not Conventional)
        invalid_msg_bad_fmt = "Added hashing (Ref: #101)"
        is_valid, msg = validate_commit_message(invalid_msg_bad_fmt, task_id)
        self.assertFalse(is_valid)
        self.assertIn("violates Conventional Commits", msg)

if __name__ == '__main__':
    unittest.main()
