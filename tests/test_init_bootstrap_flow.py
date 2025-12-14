"""
Integration Test: /init → BOOTSTRAP Mode Flow

Simulates the exact flow that happens when a user runs /init:
1. Templates are copied to docs/
2. Placeholders are replaced ({{PROJECT_NAME}}, {{DATE}}, etc.)
3. Readiness scorer runs
4. System should stay in BOOTSTRAP mode until real content added

This catches "it works in tests but not in TUI" issues.
"""

import unittest
import sys
import os
import tempfile
import shutil
from pathlib import Path
from datetime import date

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.readiness import get_context_readiness


class TestInitBootstrapFlow(unittest.TestCase):
    """Integration test simulating the /init command flow"""

    def setUp(self):
        """Create temporary project directory"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()

    def tearDown(self):
        """Clean up temporary directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    def simulate_init_command(self, project_name="TestProject"):
        """
        Simulates exactly what control_panel.ps1 does in /init:
        - Reads templates from library/templates
        - Replaces placeholders
        - Writes to docs/
        """
        template_dir = Path(__file__).parent.parent / "library" / "templates"
        today = date.today().strftime("%Y-%m-%d")

        templates = {
            "PRD.template.md": "PRD.md",
            "SPEC.template.md": "SPEC.md",
            "DECISION_LOG.template.md": "DECISION_LOG.md",
        }

        for src_name, dst_name in templates.items():
            src_path = template_dir / src_name
            dst_path = self.docs_dir / dst_name

            # Read template
            content = src_path.read_text(encoding='utf-8')

            # Replace placeholders (exactly like control_panel.ps1 does)
            content = content.replace('{{PROJECT_NAME}}', project_name)
            content = content.replace('{{DATE}}', today)
            content = content.replace('{{AUTHOR}}', 'Atomic Mesh')

            # Write file
            dst_path.write_text(content, encoding='utf-8')

    def test_init_creates_bootstrap_mode(self):
        """After /init, system should be in BOOTSTRAP mode"""
        # Simulate /init command
        self.simulate_init_command(project_name="PaymentAPI")

        # Get readiness
        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: Should be in BOOTSTRAP mode
        self.assertEqual(result["status"], "BOOTSTRAP",
                        "Fresh /init should create BOOTSTRAP mode, not EXECUTION")

        # Assert: All files should exist but score ≤40%
        self.assertTrue(result["files"]["PRD"]["exists"])
        self.assertTrue(result["files"]["SPEC"]["exists"])
        self.assertTrue(result["files"]["DECISION_LOG"]["exists"])

        self.assertLessEqual(result["files"]["PRD"]["score"], 40,
                            "PRD template should be capped at 40%")
        self.assertLessEqual(result["files"]["SPEC"]["score"], 40,
                            "SPEC template should be capped at 40%")

        # Assert: PRD and SPEC should be blocking
        self.assertIn("PRD", result["overall"]["blocking_files"])
        self.assertIn("SPEC", result["overall"]["blocking_files"])

    def test_adding_real_content_increases_score(self):
        """After adding real content, score should rise and potentially unlock EXECUTION"""
        # Simulate /init
        self.simulate_init_command(project_name="TaskManager")

        # Verify BOOTSTRAP mode first
        result = get_context_readiness(base_dir=self.test_dir)
        self.assertEqual(result["status"], "BOOTSTRAP")

        # Add real content to PRD (simulating user editing the file)
        prd_path = self.docs_dir / "PRD.md"
        content = prd_path.read_text(encoding='utf-8')

        # Replace placeholder goals with real content
        real_goals = """
Build a collaborative task management system for distributed teams working remotely.
Enable real-time synchronization across multiple devices with offline support capabilities.
Provide intuitive drag-and-drop interface for organizing tasks into sprints and milestones.
Support team sizes from small startups to large enterprises with proper access controls.
Ensure enterprise-grade security with end-to-end encryption and audit logging features.
Achieve sub-second response times for all user interactions and API endpoints.
Implement comprehensive notification system for task updates and team collaboration events.
Support third-party integrations with popular tools like Slack, JIRA, and GitHub.
Provide detailed analytics and reporting for project managers and team leads.
Enable customizable workflows to match different team methodologies and processes.
"""
        # Find the Goals section and replace it
        import re
        content = re.sub(
            r'(## Goals.*?)(- \[ \].*?\n- \[ \].*?\n- \[ \].*?\n)',
            r'\1' + real_goals + '\n',
            content,
            flags=re.DOTALL
        )
        prd_path.write_text(content, encoding='utf-8')

        # Check readiness again
        result = get_context_readiness(base_dir=self.test_dir)

        # PRD score should now be higher (has ≥10 meaningful lines)
        self.assertGreater(result["files"]["PRD"]["score"], 40,
                          "PRD with real content should score >40%")

    def test_placeholder_content_stays_low_score(self):
        """Just checking checkboxes shouldn't increase score"""
        # Simulate /init
        self.simulate_init_command(project_name="TestApp")

        # Get initial score
        result_before = get_context_readiness(base_dir=self.test_dir)
        initial_score = result_before["files"]["PRD"]["score"]

        # "Edit" PRD by just checking off checkboxes (no real content)
        prd_path = self.docs_dir / "PRD.md"
        content = prd_path.read_text(encoding='utf-8')
        content = content.replace('- [ ]', '- [x]')  # Check all boxes
        prd_path.write_text(content, encoding='utf-8')

        # Check readiness again
        result_after = get_context_readiness(base_dir=self.test_dir)
        new_score = result_after["files"]["PRD"]["score"]

        # Score should not significantly increase (still capped at ~40%)
        self.assertLessEqual(new_score, 40,
                            "Checking boxes shouldn't unlock higher scores")
        self.assertEqual(result_after["status"], "BOOTSTRAP",
                        "System should stay in BOOTSTRAP mode")

    def test_template_stub_marker_present(self):
        """Verify templates still have the stub marker after /init processing"""
        # Simulate /init
        self.simulate_init_command(project_name="TestProject")

        # Check that all created docs still have the stub marker
        for filename in ["PRD.md", "SPEC.md", "DECISION_LOG.md"]:
            path = self.docs_dir / filename
            content = path.read_text(encoding='utf-8')
            self.assertIn('ATOMIC_MESH_TEMPLATE_STUB', content,
                         f"{filename} should retain stub marker after /init")


class TestEdgeCases(unittest.TestCase):
    """Edge case tests for stub detection"""

    def setUp(self):
        """Create temporary project directory"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()

    def tearDown(self):
        """Clean up temporary directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    def test_non_stub_file_uses_normal_scoring(self):
        """Files without stub marker should use original scoring logic"""
        # Create a PRD WITHOUT the stub marker (user-created from scratch)
        prd_content = """# Product Requirements Document: Custom Project

## Goals
- Improve system performance and reduce latency
- Add real-time collaboration features today
- Enhance security with better encryption
- Support mobile platforms and tablets
- Integrate with third party services
- Reduce deployment complexity significantly

## User Stories
- As a developer, I can deploy easily
- As a user, I can collaborate
- As an admin, I can monitor
- As a manager, I can report
- As a team lead, I can assign
- As a stakeholder, I can review

## Success Metrics
- 90% user satisfaction rating
- 2 second page load time
- Zero critical vulnerabilities
"""
        prd_path = self.docs_dir / "PRD.md"
        prd_path.write_text(prd_content, encoding='utf-8')

        result = get_context_readiness(base_dir=self.test_dir)

        # Non-stub file should score normally (has bullets, headers, length)
        # Should get: 10 (exists) + 30 (headers) + 20 (bullets) = 60%+
        self.assertGreater(result["files"]["PRD"]["score"], 40,
                          "Non-stub file should use normal scoring")

    def test_removing_stub_marker_enables_normal_scoring(self):
        """Removing stub marker from template should enable normal scoring"""
        # Start with a template
        template_path = Path(__file__).parent.parent / "library" / "templates" / "PRD.template.md"
        content = template_path.read_text(encoding='utf-8')

        # Remove the stub marker
        content = content.replace('<!-- ATOMIC_MESH_TEMPLATE_STUB -->', '')
        content = content.replace('{{PROJECT_NAME}}', 'TestProject')
        content = content.replace('{{DATE}}', '2025-01-01')
        content = content.replace('{{AUTHOR}}', 'Test')

        prd_path = self.docs_dir / "PRD.md"
        prd_path.write_text(content, encoding='utf-8')

        result = get_context_readiness(base_dir=self.test_dir)

        # Without stub marker, should score normally
        # Has all headers (30%) + bullets (20%) + exists (10%) + length (20%) = 80%
        self.assertGreaterEqual(result["files"]["PRD"]["score"], 80,
                               "Removing stub marker should enable normal scoring")


if __name__ == '__main__':
    unittest.main()
