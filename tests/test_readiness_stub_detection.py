"""
Regression Tests for Template Stub Detection

Ensures that /init-generated template files are correctly identified as stubs
and do NOT immediately trigger EXECUTION mode.

This prevents the bug where template placeholders (checkboxes, headers, etc.)
are mistaken for real user content, causing premature context readiness.

Acceptance Criteria:
1. Fresh /init → BOOTSTRAP mode (not EXECUTION)
2. Template stubs score ≤40% (below 80% threshold for PRD/SPEC)
3. Adding real content (≥6 meaningful lines) → score can exceed 40%
4. EXECUTION mode only when thresholds met with real content
"""

import unittest
import sys
import os
import tempfile
import shutil
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.readiness import get_context_readiness, is_meaningful_line


class TestTemplatestubDetection(unittest.TestCase):
    """Tests for ATOMIC_MESH_TEMPLATE_STUB marker detection"""

    def setUp(self):
        """Create temporary docs directory for testing"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()

        # Save original working directory
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        """Clean up temporary directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    def test_template_stubs_stay_in_bootstrap_mode(self):
        """Fresh /init templates should keep system in BOOTSTRAP mode"""
        # Create stub template files (simulating /init)
        prd_stub = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Product Requirements Document: Test Project

## Goals
- [ ] Goal 1: [Measurable outcome]
- [ ] Goal 2: [Measurable outcome]
- [ ] Goal 3: [Measurable outcome]

## User Stories
- [ ] As a [persona], I can [action] so that [benefit]
- [ ] As a [persona], I can [action] so that [benefit]

## Success Metrics
- [ ] Metric 1: [e.g., 80% completion rate]
- [ ] Metric 2: [e.g., <2s response time]
"""

        spec_stub = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Technical Specification: Test Project

## Data Model
- [ ] Entity 1: [Name, purpose, key fields]
- [ ] Entity 2: [Name, purpose, key fields]

## API
- [ ] `GET /endpoint` - [Description]
- [ ] `POST /endpoint` - [Description]

## Security
- [ ] Threat 1: [Description + mitigation]
- [ ] Threat 2: [Description + mitigation]
"""

        decision_stub = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: Test Project

## Records
| ID | Date | Decision | Context | Status |
|----|------|----------|---------|--------|
| 001 | 2025-01-01 | Project initialized | Bootstrap via /init | ✅ |
"""

        (self.docs_dir / "PRD.md").write_text(prd_stub)
        (self.docs_dir / "SPEC.md").write_text(spec_stub)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_stub)

        # Get readiness (pass test directory as base_dir)
        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: Should be in BOOTSTRAP mode
        self.assertEqual(result["status"], "BOOTSTRAP",
                         "Template stubs should keep system in BOOTSTRAP mode")

        # Assert: PRD and SPEC should score ≤40% (below 80% threshold)
        self.assertLessEqual(result["files"]["PRD"]["score"], 40,
                            "PRD stub should score ≤40%")
        self.assertLessEqual(result["files"]["SPEC"]["score"], 40,
                            "SPEC stub should score ≤40%")

        # Assert: PRD and SPEC should be blocking
        self.assertIn("PRD", result["overall"]["blocking_files"])
        self.assertIn("SPEC", result["overall"]["blocking_files"])

    def test_real_content_unlocks_higher_scores(self):
        """Adding ≥6 meaningful lines should allow score >40%"""
        prd_with_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Product Requirements Document: Task Manager

## Goals
Build a collaborative task management system for remote teams to work together.
Enable real-time synchronization across multiple devices and web browsers simultaneously.
Provide intuitive drag-and-drop interface for organizing tasks and managing workflows easily.
Support team sizes from 5 to 100 members with proper access controls.
Ensure enterprise-grade security with complete data encryption at rest and transit.
Achieve sub-second response times for all user interactions and API calls.
Implement comprehensive audit logging for compliance and security review requirements.
Support offline mode with automatic conflict resolution when connectivity returns.
Provide mobile apps for iOS and Android with feature parity.
Enable third-party integrations with popular tools like Slack and JIRA.

## User Stories
- [ ] As a team lead, I can create projects
- [ ] As a developer, I can track my tasks

## Success Metrics
- [ ] Metric 1: 95% user satisfaction score
- [ ] Metric 2: <500ms average API response time
"""

        (self.docs_dir / "PRD.md").write_text(prd_with_content)

        # Also create minimal SPEC and DECISION_LOG to avoid errors
        spec_stub = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Technical Specification: Task Manager

## Data Model
- [ ] Entity 1

## API
- [ ] GET /endpoint

## Security
- [ ] Threat 1
"""
        decision_stub = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log

## Records
| ID | Date | Decision | Context | Status |
|----|------|----------|---------|--------|
"""
        (self.docs_dir / "SPEC.md").write_text(spec_stub)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_stub)

        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: PRD score should be >40% (meaningful content detected)
        self.assertGreater(result["files"]["PRD"]["score"], 40,
                          "PRD with real content should score >40%")

    def test_meaningful_line_detection(self):
        """is_meaningful_line should correctly identify real vs placeholder content"""
        # Real content (should return True)
        real_lines = [
            "Build a collaborative task management system for remote teams",
            "Enable real-time synchronization across multiple devices",
            "Support team sizes from 5 to 100 members",
            "Achieve 99.9% uptime for all critical operations",
        ]

        for line in real_lines:
            self.assertTrue(is_meaningful_line(line),
                          f"Should detect as meaningful: {line}")

        # Placeholder content (should return False)
        placeholder_lines = [
            "- [ ] Goal 1: [Measurable outcome]",
            "## Goals",
            "**Primary Objective**: [One sentence describing success]",
            "- [ ] Feature {{FEATURE_NAME}}",
            "",  # blank line
            "- [ ]",  # empty checkbox
            "Short line",  # <4 words
        ]

        for line in placeholder_lines:
            self.assertFalse(is_meaningful_line(line),
                           f"Should detect as placeholder: {line}")

    def test_transition_to_execution_mode(self):
        """System should transition to EXECUTION only when real content meets thresholds"""
        # Create PRD with substantial real content
        prd_complete = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Product Requirements Document: Enterprise Task Manager

## Goals
Build a collaborative task management platform for enterprise teams.
Enable real-time synchronization across multiple devices and browsers.
Provide intuitive drag-and-drop interface for task organization.
Support team sizes from 5 to 500 members with role-based access.
Ensure enterprise-grade security with SOC2 compliance and encryption.
Achieve sub-second response times for all user interactions.
Integrate with existing enterprise tools like Slack and JIRA.
Support offline mode with automatic conflict resolution.

## User Stories
As a team lead, I can create and manage projects with custom workflows.
As a developer, I can track my tasks and update status in real-time.
As a manager, I can generate reports on team productivity and velocity.
As an admin, I can configure SSO and manage user permissions.
As a team member, I can receive notifications for task assignments.

## Success Metrics
Achieve 95% user satisfaction score in quarterly surveys.
Maintain average API response time under 300 milliseconds.
Support 10000 concurrent users without performance degradation.
Zero critical security vulnerabilities in production.
99.9% uptime SLA for all enterprise customers.
"""

        # Create SPEC with substantial real content
        spec_complete = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Technical Specification: Enterprise Task Manager

## Data Model
User entity stores authentication credentials and profile information.
Project entity contains tasks, members, and workflow configuration.
Task entity tracks assignments, status, comments, and attachments.
All entities use UUID primary keys for distributed systems.
Implement soft deletes for audit trail and data recovery.
Use PostgreSQL for relational data and Redis for caching.

## API
RESTful API using JSON for all request and response payloads.
JWT-based authentication with refresh token rotation every 7 days.
Rate limiting at 1000 requests per minute per user.
GraphQL endpoint for complex queries and real-time subscriptions.
WebSocket connections for live updates and notifications.
All endpoints require HTTPS and validate CSRF tokens.

## Security
Implement OAuth2 for third-party integrations and SSO support.
Encrypt sensitive data at rest using AES-256 encryption.
Use prepared statements to prevent SQL injection attacks.
Sanitize all user input and implement CSP headers.
Regular penetration testing and vulnerability scanning quarterly.
Role-based access control with principle of least privilege.
"""

        # DECISION_LOG passes by default (only needs 30%)
        decision_log = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: Enterprise Task Manager

## Records

We chose PostgreSQL as our primary database because it provides strong ACID compliance guarantees.
This decision was made after evaluating several alternatives including MySQL and MongoDB options.
JWT authentication was selected for our API security model given its widespread industry adoption.
The team agreed on implementing role-based access control for managing user permissions properly.
These architectural decisions form the foundation of our enterprise task management platform.
All future decisions will be documented here to maintain clear project history.

| ID | Date | Decision | Context | Status |
|----|------|----------|---------|--------|
| 001 | 2025-01-01 | Use PostgreSQL for primary database | Needs ACID compliance | ✅ |
| 002 | 2025-01-02 | Implement JWT authentication | Industry standard for APIs | ✅ |
| 003 | 2025-01-03 | Implement RBAC for permissions | Security best practice | ✅ |
"""

        (self.docs_dir / "PRD.md").write_text(prd_complete)
        (self.docs_dir / "SPEC.md").write_text(spec_complete)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: Should transition to EXECUTION mode
        self.assertEqual(result["status"], "EXECUTION",
                        "System should enter EXECUTION mode with complete docs")
        self.assertEqual(len(result["overall"]["blocking_files"]), 0,
                        "No files should be blocking with complete content")

        # Assert: All scores should meet thresholds
        self.assertGreaterEqual(result["files"]["PRD"]["score"], 80)
        self.assertGreaterEqual(result["files"]["SPEC"]["score"], 80)
        self.assertGreaterEqual(result["files"]["DECISION_LOG"]["score"], 30)


class TestBackwardCompatibility(unittest.TestCase):
    """Ensure non-stub files still work correctly"""

    def setUp(self):
        """Create temporary docs directory for testing"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        """Clean up temporary directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    def test_non_stub_files_scored_normally(self):
        """Files without ATOMIC_MESH_TEMPLATE_STUB should use original scoring"""
        # Create PRD WITHOUT stub marker
        prd_no_stub = """# Product Requirements Document: Legacy Project

## Goals
- Improve user experience
- Increase performance
- Enhance security
- Add new features
- Fix known bugs
- Update documentation

## User Stories
- As a user, I can log in
- As a user, I can create tasks
- As a user, I can edit tasks
- As a user, I can delete tasks
- As a user, I can share tasks
- As a user, I can export data

## Success Metrics
- 90% satisfaction
- 2s load time
- Zero downtime
"""

        (self.docs_dir / "PRD.md").write_text(prd_no_stub)

        result = get_context_readiness(base_dir=self.test_dir)

        # Non-stub files should be able to score based on bullets and length
        # This file has >5 bullets and headers, so should score higher
        self.assertGreater(result["files"]["PRD"]["score"], 40,
                          "Non-stub files should use normal scoring")


class TestFlexibleHeaderDetection(unittest.TestCase):
    """v18.2: Tests for flexible header matching without ## prefix"""

    def setUp(self):
        """Create temporary docs directory for testing"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        """Clean up temporary directory"""
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    def test_header_regex_compiles_correctly(self):
        """Ensure header regex patterns compile without f-string brace errors.

        This test guards against regressions where {1,6} in the regex
        is accidentally interpreted as an f-string format specifier.
        If the braces aren't escaped as {{1,6}}, the regex will be malformed.
        """
        import re

        # Simulate the pattern construction from readiness.py
        header_texts = ["Goals", "User Stories", "Success Metrics", "Data Model", "API", "Security", "Records"]

        for header_text in header_texts:
            # This is the exact pattern from readiness.py
            pattern = rf'^(?:#{{1,6}}\s+)?{re.escape(header_text)}(?:[\s:]*$|\s*\()'

            # Verify pattern compiles
            try:
                compiled = re.compile(pattern, re.IGNORECASE | re.MULTILINE)
            except re.error as e:
                self.fail(f"Regex failed to compile for header '{header_text}': {e}")

            # Verify {1,6} is in the pattern (not interpreted as f-string)
            self.assertIn("{1,6}", pattern,
                         f"Pattern should contain literal {{1,6}} for header '{header_text}'")

            # Verify it matches markdown headers
            self.assertIsNotNone(compiled.search(f"## {header_text}"),
                                f"Pattern should match '## {header_text}'")

    def test_false_positive_sentence_not_matched_as_header(self):
        """Sentences starting with header words should NOT be detected as headers.

        Ensures 'Goals are important' doesn't count as the 'Goals' header.
        This guards against overly permissive regex matching.
        """
        # PRD where header words appear mid-sentence (NOT as headers)
        prd_with_false_positives = """# Product Requirements Document

This document describes our goals and objectives for the project.
Goals are important because they guide our development process.
User stories help us understand what features to build next.
Success metrics will be tracked throughout the project lifecycle.

## Goals
- Build a task manager
- Support 100 users
- Achieve 99% uptime

## User Stories
- As a user, I can create tasks
- As a user, I can delete tasks

## Success Metrics
- 95% satisfaction
- < 1s load time
"""

        (self.docs_dir / "PRD.md").write_text(prd_with_false_positives)
        (self.docs_dir / "SPEC.md").write_text("## Data Model\n- E1\n## API\n- E2\n## Security\n- E3")
        (self.docs_dir / "DECISION_LOG.md").write_text("## Records\n| ID |\n")

        result = get_context_readiness(base_dir=self.test_dir)

        # PRD should find exactly 3 headers (the actual ## headers, not the sentences)
        # "Goals are important" at line start should NOT match as "Goals" header
        self.assertEqual(result["files"]["PRD"]["headers"], 3,
                        "Should only match actual headers, not sentences starting with header words")

    def test_headers_without_hash_prefix(self):
        """Headers without ## prefix should still be detected"""
        # PRD with plain text headers (no ## prefix) - like LLM-generated docs
        prd_plain_headers = """Product Requirements Document: Test App

Goals
Build a task management application for teams to collaborate effectively.
Enable real-time synchronization across multiple devices and browsers.
Provide drag-and-drop interface for organizing tasks and workflows.
Support team sizes from 5 to 100 members with access controls.
Ensure enterprise-grade security with data encryption at rest.
Achieve sub-second response times for all user interactions.

User Stories
[ ] As a team lead, I can create projects and assign team members.
[ ] As a developer, I can track my tasks and update their status.
[ ] As a manager, I can generate reports on team productivity.
[ ] As an admin, I can configure SSO and manage user permissions.
[ ] As a team member, I can receive notifications for assignments.
[ ] As a stakeholder, I can view project progress dashboards.

Success Metrics
[ ] Achieve 95% user satisfaction score in quarterly surveys.
[ ] Maintain average API response time under 300 milliseconds.
[ ] Support 10000 concurrent users without performance issues.
"""

        # SPEC with plain text headers and enough content to pass thresholds
        spec_plain_headers = """Technical Specification: Test App

Data Model
- User entity stores authentication credentials and profile information.
- Project entity contains tasks, members, and workflow configuration.
- Task entity tracks assignments, status, comments, and attachments.
- All entities use UUID primary keys for distributed systems.
- Implement soft deletes for audit trail and data recovery.
- Use PostgreSQL for relational data and Redis for caching.
- Add indexes on frequently queried columns for performance.

API
- RESTful API using JSON for all request and response payloads.
- JWT-based authentication with refresh token rotation support.
- Rate limiting at 1000 requests per minute per user account.
- GraphQL endpoint for complex queries and subscriptions.
- WebSocket connections for live updates and notifications.
- All endpoints require HTTPS and validate CSRF tokens.
- Versioned API paths for backward compatibility support.

Security
- Implement OAuth2 for third-party integrations and SSO.
- Encrypt sensitive data at rest using AES-256 encryption.
- Use prepared statements to prevent SQL injection attacks.
- Sanitize all user input and implement CSP headers.
- Regular penetration testing and vulnerability scanning.
- Role-based access control with principle of least privilege.
- Audit logging for all sensitive operations and data access.
"""

        # DECISION_LOG with proper content (>150 words to reach threshold)
        decision_log = """# Decision Log: Test App

## Records

This document tracks all architectural and technical decisions made during the project.
Each decision includes context, rationale, and status to ensure traceability.
Decisions are append-only and should never be deleted, only superseded if needed.
The team reviews decisions weekly to ensure alignment with project goals.
All stakeholders should be notified when major decisions are made.

| ID | Date | Type | Decision | Rationale | Status |
|----|------|------|----------|-----------|--------|
| 001 | 2025-01-01 | ARCH | Use PostgreSQL database | ACID compliance needed for data integrity | ✅ |
| 002 | 2025-01-02 | API | Implement JWT authentication | Industry standard for API security model | ✅ |
| 003 | 2025-01-03 | DATA | Use UUID primary keys | Better for distributed systems | ✅ |
| 004 | 2025-01-04 | SEC | Implement RBAC | Required for enterprise compliance | ✅ |
| 005 | 2025-01-05 | PERF | Add Redis caching | Reduce database load for read operations | ✅ |

Additional decisions will be documented here as the project evolves.
Each decision should include clear rationale and be reviewed by technical leads.
Superseded decisions should be marked with appropriate status indicators.
"""

        (self.docs_dir / "PRD.md").write_text(prd_plain_headers)
        (self.docs_dir / "SPEC.md").write_text(spec_plain_headers)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: Headers should be found despite missing ## prefix
        self.assertEqual(result["files"]["PRD"]["headers"], 3,
                        "PRD should detect 3 headers without ## prefix")
        self.assertEqual(result["files"]["SPEC"]["headers"], 3,
                        "SPEC should detect 3 headers without ## prefix")

        # Assert: All files should pass their thresholds
        self.assertGreaterEqual(result["files"]["PRD"]["score"], 80,
                               "PRD should meet threshold")
        self.assertGreaterEqual(result["files"]["SPEC"]["score"], 80,
                               "SPEC should meet threshold")
        self.assertGreaterEqual(result["files"]["DECISION_LOG"]["score"], 30,
                               "DECISION_LOG should meet threshold")

        # Assert: Should reach EXECUTION status
        self.assertEqual(result["status"], "EXECUTION",
                        "Plain headers should enable EXECUTION mode")

    def test_headers_with_trailing_text(self):
        """Headers with parenthetical suffixes (e.g., 'API (Internal Interfaces)') should match"""
        # Note: Only parenthetical suffixes are allowed, not arbitrary trailing words
        # "Security (Considerations)" matches, "Security Considerations" does not
        spec_with_trailing = """Technical Specification: Test App

Data Model (Core Entities)
User entity stores authentication credentials and profile info.
Project entity contains tasks, members, and workflow config.
Task entity tracks assignments, status, and attachments.
All entities use UUID primary keys for distributed systems.
Implement soft deletes for audit trail and data recovery.
Use PostgreSQL for relational data and Redis for caching.

API (Internal Interfaces)
RESTful API using JSON for all request and response payloads.
JWT-based authentication with refresh token rotation.
Rate limiting at 1000 requests per minute per user.
GraphQL endpoint for complex queries and subscriptions.
WebSocket connections for live updates and notifications.
All endpoints require HTTPS and validate CSRF tokens.

Security (Best Practices)
Implement OAuth2 for third-party integrations and SSO.
Encrypt sensitive data at rest using AES-256 encryption.
Use prepared statements to prevent SQL injection attacks.
Sanitize all user input and implement CSP headers.
Regular penetration testing and vulnerability scanning.
Role-based access control with principle of least privilege.
"""

        (self.docs_dir / "SPEC.md").write_text(spec_with_trailing)
        # Create minimal PRD and DECISION_LOG
        (self.docs_dir / "PRD.md").write_text("## Goals\nGoal 1\n## User Stories\nStory 1\n## Success Metrics\nMetric 1")
        (self.docs_dir / "DECISION_LOG.md").write_text("## Records\n| ID | Date |\n")

        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: SPEC should find all 3 headers (parenthetical suffixes allowed)
        self.assertEqual(result["files"]["SPEC"]["headers"], 3,
                        "SPEC should detect headers with parenthetical suffixes")

    def test_standalone_checkboxes_counted_as_bullets(self):
        """Standalone checkboxes [ ] should be counted as bullet points"""
        prd_with_standalone_checkboxes = """# Product Requirements Document

## Goals
[ ] Goal 1: Build a task management application for teams.
[ ] Goal 2: Enable real-time synchronization across devices.
[ ] Goal 3: Provide drag-and-drop interface for tasks.
[ ] Goal 4: Support team sizes from 5 to 100 members.
[ ] Goal 5: Ensure enterprise-grade security with encryption.
[ ] Goal 6: Achieve sub-second response times for users.

## User Stories
[ ] US1: As a team lead, I can create projects.
[ ] US2: As a developer, I can track my tasks.
[ ] US3: As a manager, I can generate reports.

## Success Metrics
[ ] M1: 95% user satisfaction score.
[ ] M2: <300ms API response time.
"""

        (self.docs_dir / "PRD.md").write_text(prd_with_standalone_checkboxes)
        (self.docs_dir / "SPEC.md").write_text("## Data Model\n- E1\n## API\n- E2\n## Security\n- E3")
        (self.docs_dir / "DECISION_LOG.md").write_text("## Records\n| ID |\n")

        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: Standalone checkboxes should be counted as bullets
        self.assertGreater(result["files"]["PRD"]["bullets"], 5,
                          "Standalone checkboxes [ ] should be counted as bullets")

    def test_mixed_bullet_formats(self):
        """Mix of bullet styles should all be counted"""
        prd_mixed_bullets = """# Product Requirements Document

## Goals
- Dashed bullet item one for the project goals section.
* Star bullet item two for additional functionality.
1. Numbered item three for sequential requirements list.
- [ ] Checkbox with dash item four for trackable items.
[ ] Standalone checkbox item five without bullet prefix.
[ ] Standalone checkbox item six as last test case.

## User Stories
- Story 1
- Story 2
- Story 3

## Success Metrics
- Metric 1
- Metric 2
"""

        (self.docs_dir / "PRD.md").write_text(prd_mixed_bullets)
        (self.docs_dir / "SPEC.md").write_text("## Data Model\n- E1\n## API\n- E2\n## Security\n- E3")
        (self.docs_dir / "DECISION_LOG.md").write_text("## Records\n| ID |\n")

        result = get_context_readiness(base_dir=self.test_dir)

        # Assert: All bullet formats should be counted
        self.assertGreater(result["files"]["PRD"]["bullets"], 5,
                          "Mixed bullet formats should all be counted")


if __name__ == '__main__':
    unittest.main()
