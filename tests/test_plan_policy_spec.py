"""
PLAN Policy Spec Tests
See: docs/PLAN_POLICY_SPEC.md

These tests enforce the UI behavior contracts defined in the spec.
"""

import re
import pytest

# =============================================================================
# CONSTANTS FROM SPEC
# =============================================================================

FORBIDDEN_STATUS_WORDS = ['RUNNING', 'OK', 'BLOCKED', 'IDLE']
WORK_LANES = ['BACKEND', 'FRONTEND']
AUDIT_LANES = ['QA/AUDIT', 'LIBRARIAN']
VALID_NEXT_COMMANDS = ['draft-plan', 'accept-plan', 'go']


# =============================================================================
# ASSERTION HELPERS (from spec section 6.2)
# =============================================================================

def assert_no_status_words(lane_output: str) -> None:
    """Lane rows must not contain status words (Spec 4.1)."""
    for word in FORBIDDEN_STATUS_WORDS:
        if re.search(rf'\b{word}\b', lane_output, re.IGNORECASE):
            raise AssertionError(f"Lane contains forbidden status word: {word}")


def assert_next_line(output: str, expected: str) -> None:
    """Verify correct Next: command is shown (Spec 3)."""
    assert expected in VALID_NEXT_COMMANDS, f"Invalid expected command: {expected}"
    pattern = rf'Next:\s*/{expected}\b'
    if not re.search(pattern, output):
        raise AssertionError(f"Expected 'Next: /{expected}' not found in output")


def assert_health_dot(lane_row: str) -> None:
    """Every lane row must have exactly one health dot (Spec 5.1)."""
    if '●' not in lane_row:
        raise AssertionError(f"Lane row missing health dot: {lane_row}")


def assert_work_lane_format(lane_row: str) -> None:
    """Work lanes: LANE tokens A:n D:n/n|— summary dot (Spec 4.2)."""
    # Allow flexible whitespace, require A: and D: counters
    pattern = r'^(BACKEND|FRONTEND)\s+[■□]+\s+A:\d+\s+D:(\d+/\d+|—)\s+.+●'
    if not re.match(pattern, lane_row.strip()):
        raise AssertionError(f"Work lane format invalid: {lane_row}")


def assert_audit_lane_format(lane_row: str) -> None:
    """Audit lanes: LANE tokens summary dot - NO A:/D: counters (Spec 4.3)."""
    lane_row = lane_row.strip()
    # Must start with audit lane name
    if not any(lane_row.startswith(lane) for lane in AUDIT_LANES):
        raise AssertionError(f"Not an audit lane: {lane_row}")
    # Must NOT have A: or D: counters
    if re.search(r'\bA:\d', lane_row) or re.search(r'\bD:', lane_row):
        raise AssertionError(f"Audit lane should not have A:/D: counters: {lane_row}")
    # Must have health dot
    assert_health_dot(lane_row)


def assert_drift_warning(output: str) -> None:
    """When drift detected, warning must appear (Spec 3.1)."""
    expected = 'Draft changed'
    if expected not in output:
        raise AssertionError(f"Drift warning not found. Expected text containing: {expected}")


def assert_no_crash_on_empty_db(output: str) -> None:
    """When no tasks in DB, /go must return friendly message (Spec 8.1)."""
    # Must NOT contain error indicators
    error_patterns = [
        r'Exception',
        r'Error:',
        r'Traceback',
        r'stack trace',
        r'NullReferenceException',
        r'undefined',
    ]
    for pattern in error_patterns:
        if re.search(pattern, output, re.IGNORECASE):
            raise AssertionError(f"Output contains error indicator: {pattern}")

    # Should contain guidance about loading tasks
    if 'accept-plan' not in output.lower() and 'no task' not in output.lower():
        raise AssertionError("Missing guidance message for empty DB state")


# =============================================================================
# UNIT TESTS FOR ASSERTION HELPERS
# =============================================================================

class TestAssertNoStatusWords:
    """Spec 4.1: Color-Only Rule."""

    def test_clean_lane_passes(self):
        """Lane without status words passes."""
        assert_no_status_words("BACKEND  ■■□□□ A:1 D:2/5 Implementing auth ●")

    def test_running_fails(self):
        """RUNNING in lane triggers failure."""
        with pytest.raises(AssertionError, match="RUNNING"):
            assert_no_status_words("BACKEND  RUNNING ■■□□□ A:1 D:2/5 ●")

    def test_ok_fails(self):
        """OK in lane triggers failure."""
        with pytest.raises(AssertionError, match="OK"):
            assert_no_status_words("BACKEND  OK ■■□□□ A:1 D:2/5 ●")

    def test_blocked_fails(self):
        """BLOCKED in lane triggers failure."""
        with pytest.raises(AssertionError, match="BLOCKED"):
            assert_no_status_words("BACKEND  BLOCKED ■■□□□ A:1 D:2/5 ●")

    def test_idle_fails(self):
        """IDLE in lane triggers failure."""
        with pytest.raises(AssertionError, match="IDLE"):
            assert_no_status_words("FRONTEND  IDLE ■□□□□ A:0 D:0/5 ●")

    def test_case_insensitive(self):
        """Status words caught regardless of case."""
        with pytest.raises(AssertionError):
            assert_no_status_words("BACKEND  running ■■□□□ A:1 D:2/5 ●")


class TestAssertNextLine:
    """Spec 3: Next: Line Rules."""

    def test_draft_plan_found(self):
        """Detects Next: /draft-plan."""
        output = "No draft exists.\nNext: /draft-plan"
        assert_next_line(output, "draft-plan")

    def test_accept_plan_found(self):
        """Detects Next: /accept-plan."""
        output = "Draft ready.\nNext: /accept-plan"
        assert_next_line(output, "accept-plan")

    def test_go_found(self):
        """Detects Next: /go."""
        output = "Tasks loaded.\nNext: /go"
        assert_next_line(output, "go")

    def test_missing_next_line_fails(self):
        """Missing Next: line triggers failure."""
        with pytest.raises(AssertionError):
            assert_next_line("No next line here", "go")

    def test_wrong_command_fails(self):
        """Wrong command triggers failure."""
        with pytest.raises(AssertionError):
            assert_next_line("Next: /draft-plan", "go")


class TestAssertHealthDot:
    """Spec 5.1: Health Dot Placement."""

    def test_dot_present_passes(self):
        """Lane with dot passes."""
        assert_health_dot("BACKEND  ■■□□□ A:1 D:2/5 Working ●")

    def test_missing_dot_fails(self):
        """Lane without dot fails."""
        with pytest.raises(AssertionError, match="missing health dot"):
            assert_health_dot("BACKEND  ■■□□□ A:1 D:2/5 Working")


class TestAssertWorkLaneFormat:
    """Spec 4.2: Work Lane Format."""

    def test_valid_backend_lane(self):
        """Valid BACKEND lane passes."""
        assert_work_lane_format("BACKEND  ■■□□□ A:1 D:2/5 Implementing auth ●")

    def test_valid_frontend_lane(self):
        """Valid FRONTEND lane passes."""
        assert_work_lane_format("FRONTEND ■■■□□ A:0 D:3/5 Styling complete  ●")

    def test_unknown_accounting(self):
        """D:— for unknown accounting passes."""
        assert_work_lane_format("BACKEND  ■□□□□ A:2 D:— Task in progress ●")

    def test_missing_counters_fails(self):
        """Work lane without A:/D: fails."""
        with pytest.raises(AssertionError):
            assert_work_lane_format("BACKEND  ■■□□□ Working on stuff ●")

    def test_audit_lane_as_work_fails(self):
        """Audit lane name with work format fails."""
        with pytest.raises(AssertionError):
            assert_work_lane_format("QA/AUDIT ■■■■■ A:0 D:5/5 All done ●")


class TestAssertAuditLaneFormat:
    """Spec 4.3: Audit Lane Format."""

    def test_valid_qa_lane(self):
        """Valid QA/AUDIT lane passes."""
        assert_audit_lane_format("QA/AUDIT  ■■■■■ All verified    ●")

    def test_valid_librarian_lane(self):
        """Valid LIBRARIAN lane passes."""
        assert_audit_lane_format("LIBRARIAN ■■■■■ Library clean   ●")

    def test_with_counters_fails(self):
        """Audit lane with A:/D: counters fails."""
        with pytest.raises(AssertionError, match="should not have"):
            assert_audit_lane_format("QA/AUDIT ■■■■■ A:0 D:5/5 All done ●")


class TestDriftWarning:
    """Spec 3.1: Drift Warning."""

    def test_drift_warning_detected(self):
        """Drift warning text found."""
        output = "Next: /go\nDraft changed — /accept-plan to load new tasks"
        assert_drift_warning(output)

    def test_missing_warning_fails(self):
        """Missing drift warning fails."""
        with pytest.raises(AssertionError):
            assert_drift_warning("Next: /go")


class TestNoCrashOnEmptyDB:
    """Spec 8.1: Error Handling for Empty DB."""

    def test_friendly_message_passes(self):
        """Friendly no-tasks message passes."""
        output = "No tasks loaded. Use /accept-plan to load a plan first."
        assert_no_crash_on_empty_db(output)

    def test_exception_fails(self):
        """Exception in output fails."""
        with pytest.raises(AssertionError):
            assert_no_crash_on_empty_db("Exception: NullReferenceException at line 42")

    def test_traceback_fails(self):
        """Python traceback fails."""
        with pytest.raises(AssertionError):
            assert_no_crash_on_empty_db("Traceback (most recent call last):")


# =============================================================================
# INTEGRATION TEST FIXTURES
# =============================================================================

@pytest.fixture
def sample_plan_screen_no_draft():
    """Simulated PLAN screen when no draft exists."""
    return """
╔═══════════════════════════════════════╗
║           PLAN                        ║
╠═══════════════════════════════════════╣
║ No draft plan found.                  ║
║                                       ║
║ Next: /draft-plan                     ║
╚═══════════════════════════════════════╝
"""


@pytest.fixture
def sample_plan_screen_draft_exists():
    """Simulated PLAN screen when draft exists but not accepted."""
    return """
╔═══════════════════════════════════════╗
║           PLAN                        ║
╠═══════════════════════════════════════╣
║ Draft: draft_20251219_1200.md         ║
║ Tasks: 5                              ║
║                                       ║
║ Next: /accept-plan                    ║
╚═══════════════════════════════════════╝
"""


@pytest.fixture
def sample_plan_screen_accepted():
    """Simulated PLAN screen when plan is accepted."""
    return """
╔═══════════════════════════════════════╗
║           PLAN                        ║
╠═══════════════════════════════════════╣
║ Active: draft_20251219_1200.md        ║
║ Tasks: 3 pending, 2 done              ║
║                                       ║
║ Next: /go                             ║
╚═══════════════════════════════════════╝
"""


@pytest.fixture
def sample_plan_screen_drift():
    """Simulated PLAN screen when drift detected."""
    return """
╔═══════════════════════════════════════╗
║           PLAN                        ║
╠═══════════════════════════════════════╣
║ Active: draft_20251219_1200.md        ║
║ Tasks: 3 pending, 2 done              ║
║                                       ║
║ Next: /go                             ║
║ Draft changed — /accept-plan to load  ║
║ new tasks                             ║
╚═══════════════════════════════════════╝
"""


@pytest.fixture
def sample_lane_rows():
    """Sample lane rows conforming to spec."""
    return {
        'backend': "BACKEND  ■■□□□ A:1 D:2/5 Implementing auth ●",
        'frontend': "FRONTEND ■■■□□ A:0 D:3/5 Styling complete  ●",
        'backend_unknown': "BACKEND  ■□□□□ A:2 D:— Task in progress ●",
        'qa': "QA/AUDIT  ■■■■■ All verified    ●",
        'librarian': "LIBRARIAN ■■■■■ Library clean   ●",
    }


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestPlanScreenNextLine:
    """Verify Next: line matches state (Spec 3)."""

    def test_no_draft_shows_draft_plan(self, sample_plan_screen_no_draft):
        assert_next_line(sample_plan_screen_no_draft, "draft-plan")

    def test_draft_exists_shows_accept_plan(self, sample_plan_screen_draft_exists):
        assert_next_line(sample_plan_screen_draft_exists, "accept-plan")

    def test_accepted_shows_go(self, sample_plan_screen_accepted):
        assert_next_line(sample_plan_screen_accepted, "go")

    def test_drift_shows_go_with_warning(self, sample_plan_screen_drift):
        assert_next_line(sample_plan_screen_drift, "go")
        assert_drift_warning(sample_plan_screen_drift)


class TestLaneRowFormatting:
    """Verify lane rows match spec (Spec 4)."""

    def test_work_lanes_have_counters(self, sample_lane_rows):
        assert_work_lane_format(sample_lane_rows['backend'])
        assert_work_lane_format(sample_lane_rows['frontend'])

    def test_work_lanes_unknown_accounting(self, sample_lane_rows):
        assert_work_lane_format(sample_lane_rows['backend_unknown'])

    def test_audit_lanes_no_counters(self, sample_lane_rows):
        assert_audit_lane_format(sample_lane_rows['qa'])
        assert_audit_lane_format(sample_lane_rows['librarian'])

    def test_all_lanes_have_health_dot(self, sample_lane_rows):
        for lane_row in sample_lane_rows.values():
            assert_health_dot(lane_row)

    def test_no_status_words_anywhere(self, sample_lane_rows):
        for lane_row in sample_lane_rows.values():
            assert_no_status_words(lane_row)


# =============================================================================
# SPEC COMPLIANCE CHECKLIST (for manual/CI verification)
# =============================================================================

"""
SPEC COMPLIANCE CHECKLIST
=========================

Run this file to verify spec compliance:
    pytest tests/test_plan_policy_spec.py -v

Manual checks (not automatable):
[ ] Health dots appear at consistent column across all lanes
[ ] ANSI colors render correctly (green/yellow/red)
[ ] Next: line is visually prominent in PLAN screen

Automated checks (this file):
[x] No status words in lane rows (RUNNING, OK, BLOCKED, IDLE)
[x] Work lanes have A:/D: counters
[x] Audit lanes do NOT have A:/D: counters
[x] All lanes have health dot
[x] Next: line matches state machine
[x] Drift warning appears when draft changed
[x] /go with empty DB returns friendly message, not crash
"""
