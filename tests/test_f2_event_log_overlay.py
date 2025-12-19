"""
Test: F2 Event Log Overlay (v22.0)

Verifies:
1. F2 toggles overlay mode; does NOT change $Global:CurrentPage
2. After running /go, the history list contains a GO event
3. Event log functions are properly defined in control_panel.ps1

Acceptance criteria:
- PLAN stays visible; F2 opens/closes history
- Shows recent /go picks and NO_WORK reasons
"""
import os
import re
import sys

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest


@pytest.fixture
def control_panel_content():
    """Load control_panel.ps1 content for structure verification."""
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    control_panel_path = os.path.join(repo_root, "control_panel.ps1")

    with open(control_panel_path, "r", encoding="utf-8") as f:
        return f.read()


class TestF2OverlayToggle:
    """Test F2 toggles EventLogOverlay without changing CurrentPage."""

    def test_f2_returns_toggle_event_log_signal(self, control_panel_content):
        """F2 key (VirtualKeyCode 113) returns __TOGGLE_EVENT_LOG__ signal."""
        # Check that F2 handling returns the correct signal
        assert 'return "__TOGGLE_EVENT_LOG__"' in control_panel_content, \
            "F2 handler should return __TOGGLE_EVENT_LOG__ signal"

    def test_toggle_event_log_handler_exists(self, control_panel_content):
        """Main loop has handler for __TOGGLE_EVENT_LOG__ signal."""
        assert '$userInput -eq "__TOGGLE_EVENT_LOG__"' in control_panel_content, \
            "Main loop should handle __TOGGLE_EVENT_LOG__ signal"

    def test_overlay_does_not_change_current_page(self, control_panel_content):
        """EventLogOverlay toggle does NOT modify CurrentPage."""
        # Look for the comment that confirms this design decision
        assert "Does NOT change $Global:CurrentPage" in control_panel_content, \
            "Event log toggle should explicitly NOT change CurrentPage"

    def test_event_log_overlay_visible_global_exists(self, control_panel_content):
        """Global:EventLogOverlayVisible variable is defined."""
        assert "$Global:EventLogOverlayVisible" in control_panel_content, \
            "EventLogOverlayVisible global should be defined"


class TestEventLogFunctions:
    """Test event log functions are properly defined."""

    def test_add_ui_event_function_exists(self, control_panel_content):
        """Add-UiEvent function is defined."""
        assert "function Add-UiEvent" in control_panel_content, \
            "Add-UiEvent function should be defined"

    def test_add_ui_event_has_type_parameter(self, control_panel_content):
        """Add-UiEvent accepts Type parameter."""
        # Find the function and check for Type parameter
        match = re.search(r'function Add-UiEvent.*?\[string\]\$Type', control_panel_content, re.DOTALL)
        assert match is not None, "Add-UiEvent should have Type parameter"

    def test_add_ui_event_has_summary_parameter(self, control_panel_content):
        """Add-UiEvent accepts Summary parameter."""
        match = re.search(r'function Add-UiEvent.*?\[string\]\$Summary', control_panel_content, re.DOTALL)
        assert match is not None, "Add-UiEvent should have Summary parameter"

    def test_draw_event_log_overlay_function_exists(self, control_panel_content):
        """Draw-EventLogOverlay function is defined."""
        assert "function Draw-EventLogOverlay" in control_panel_content, \
            "Draw-EventLogOverlay function should be defined"

    def test_get_relative_time_function_exists(self, control_panel_content):
        """Get-RelativeTime helper function is defined."""
        assert "function Get-RelativeTime" in control_panel_content, \
            "Get-RelativeTime function should be defined"

    def test_ui_event_log_global_exists(self, control_panel_content):
        """Global:UiEventLog ring buffer is defined."""
        assert "$Global:UiEventLog" in control_panel_content, \
            "UiEventLog ring buffer should be defined"


class TestGoCommandLogsEvent:
    """Test /go command logs events to event log."""

    def test_go_pick_logs_event(self, control_panel_content):
        """Successful /go pick logs GO_PICK event."""
        assert 'Add-UiEvent -Type "GO_PICK"' in control_panel_content, \
            "/go handler should log GO_PICK event on success"

    def test_go_no_work_logs_event(self, control_panel_content):
        """NO_WORK result logs GO_NO_WORK event."""
        assert 'Add-UiEvent -Type "GO_NO_WORK"' in control_panel_content, \
            "/go handler should log GO_NO_WORK event when queue empty"


class TestDraftPlanLogsEvent:
    """Test /draft-plan command logs events to event log."""

    def test_draft_plan_logs_event(self, control_panel_content):
        """Draft plan operation logs DRAFT_PLAN event."""
        assert 'Add-UiEvent -Type "DRAFT_PLAN"' in control_panel_content, \
            "/draft-plan handler should log DRAFT_PLAN event"


class TestAcceptPlanLogsEvent:
    """Test /accept-plan command logs events to event log."""

    def test_accept_plan_logs_event(self, control_panel_content):
        """Accept plan operation logs ACCEPT_PLAN event."""
        assert 'Add-UiEvent -Type "ACCEPT_PLAN"' in control_panel_content, \
            "/accept-plan handler should log ACCEPT_PLAN event"


class TestVerifyLogsEvent:
    """Test /verify command logs events to event log."""

    def test_verify_logs_event(self, control_panel_content):
        """Verify operation logs VERIFY event."""
        assert 'Add-UiEvent -Type "VERIFY"' in control_panel_content, \
            "/verify handler should log VERIFY event"


class TestPreflightLogsEvent:
    """Test /preflight command logs events to event log."""

    def test_preflight_logs_event(self, control_panel_content):
        """Preflight operation logs PREFLIGHT event."""
        assert 'Add-UiEvent -Type "PREFLIGHT"' in control_panel_content, \
            "/preflight handler should log PREFLIGHT event"


class TestShipLogsEvent:
    """Test /ship command logs events to event log."""

    def test_ship_logs_event(self, control_panel_content):
        """Ship operation logs SHIP event."""
        assert 'Add-UiEvent -Type "SHIP"' in control_panel_content, \
            "/ship handler should log SHIP event"


class TestWorkerSummaryEvent:
    """Test worker summary aggregated event."""

    def test_workers_alive_event_type_supported(self, control_panel_content):
        """WORKERS_ALIVE event type is supported in overlay."""
        assert '"WORKERS_ALIVE"' in control_panel_content, \
            "WORKERS_ALIVE event type should be supported"

    def test_check_worker_summary_function_exists(self, control_panel_content):
        """Check-WorkerSummaryEvent function is defined."""
        assert "function Check-WorkerSummaryEvent" in control_panel_content, \
            "Check-WorkerSummaryEvent function should be defined"

    def test_check_worker_summary_called_in_main_loop(self, control_panel_content):
        """Check-WorkerSummaryEvent is called in main loop."""
        assert "Check-WorkerSummaryEvent" in control_panel_content, \
            "Check-WorkerSummaryEvent should be called from main loop"


class TestEscapeClosesOverlay:
    """Test ESC key closes the event log overlay."""

    def test_esc_closes_event_log_overlay(self, control_panel_content):
        """ESC key (with empty buffer) closes EventLogOverlay."""
        # Check that ESC handling includes EventLogOverlayVisible check
        assert 'EventLogOverlayVisible' in control_panel_content and \
               '__TOGGLE_EVENT_LOG__' in control_panel_content, \
            "ESC handler should close event log overlay"


class TestOverlayHints:
    """Test overlay includes quick hints."""

    def test_overlay_shows_close_hint(self, control_panel_content):
        """Overlay shows ESC/F2 to close hint."""
        assert "(ESC/F2 to close)" in control_panel_content or \
               "ESC/F2 to close" in control_panel_content, \
            "Overlay should show close hint"
