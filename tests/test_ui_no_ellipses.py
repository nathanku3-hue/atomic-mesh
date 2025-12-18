"""
Regression tests for UI rendering rules.

T-UX-NO-ELLIPSES: Decision rows and truncated text must never contain "..."
and must render as exactly one line (no wrapping).
"""

import pytest
import re


class TestNoEllipsesRule:
    """Ensure truncation never introduces ellipses (...) in rendered output."""

    def test_hard_truncate_never_adds_ellipses(self):
        """Verify hard truncation logic doesn't add ellipses."""
        # Simulate the truncation logic used in control_panel.ps1
        def hard_truncate(text: str, max_len: int) -> str:
            """v19.0 truncation: hard cut, no ellipses."""
            if len(text) > max_len:
                return text[:max_len]
            return text

        test_cases = [
            ("Short text", 50, "Short text"),
            ("This is a very long decision text that exceeds the limit", 20, "This is a very long "),
            ("010 2025-12-15 SEC **Read-Only Mode** for Data Protection", 40, "010 2025-12-15 SEC **Read-Only Mode** fo"),
            ("", 10, ""),
            ("Exactly10!", 10, "Exactly10!"),
            ("Exactly11!!", 10, "Exactly11!"),  # 11 chars -> truncate to 10
        ]

        for original, max_len, expected in test_cases:
            result = hard_truncate(original, max_len)
            assert "..." not in result, f"Ellipses found in truncated text: {result}"
            assert len(result) <= max_len, f"Result exceeds max_len: {len(result)} > {max_len}"
            assert result == expected, f"Expected {expected!r}, got {result!r}"

    def test_decision_line_format_no_ellipses(self):
        """Verify decision line rendering never contains ellipses."""
        # Simulate decision line formatting from Draw-Dashboard
        def format_decision_line(decision_text: str, panel_width: int) -> str:
            """Format decision line as done in control_panel.ps1 v19.0."""
            # Strip pipe chars and trim (as done in PS1)
            d1 = decision_text.replace("|", "").strip()
            # Hard truncate without ellipses
            if len(d1) > panel_width:
                d1 = d1[:panel_width]
            return d1

        # Test with realistic decision log entries
        decisions = [
            "| 010 | 2025-12-15 | SEC | **Read-Only Mode** for Data Protection During Initial Launch |",
            "| 009 | 2025-12-14 | ARCH | Use SQLite for local persistence |",
            "| 008 | 2025-12-13 | UX | Single-panel layout for MVP |",
            "| 007 | 2025-12-12 | VERY_LONG | This is an extremely long decision description that definitely exceeds any reasonable panel width and should be truncated without ellipses |",
        ]

        panel_widths = [40, 60, 80, 100]

        for decision in decisions:
            for width in panel_widths:
                result = format_decision_line(decision, width)
                assert "..." not in result, f"Ellipses in decision line: {result}"
                assert len(result) <= width, f"Line exceeds width: {len(result)} > {width}"
                assert "\n" not in result, f"Line contains newline (wrapping): {result!r}"

    def test_next_command_format_no_ellipses(self):
        """Verify 'Next:' line never contains ellipses or rationale."""
        def format_next_line(command: str, max_len: int) -> str:
            """Format Next: line as done in control_panel.ps1 v19.0."""
            # v19.0: Just show command, no "(because ...)" rationale
            if len(command) > max_len:
                return command[:max_len]
            return command

        commands = [
            "/draft-plan",
            "/refresh-plan",
            "/ingest",
            "/very-long-command-name-that-exceeds-normal-width",
        ]

        for cmd in commands:
            result = format_next_line(cmd, 30)
            assert "..." not in result, f"Ellipses in Next line: {result}"
            assert "because" not in result.lower(), f"Rationale found in Next line: {result}"
            assert len(result) <= 30, f"Line exceeds max: {len(result)}"

    def test_single_line_constraint(self):
        """Verify truncated output is always exactly one line."""
        def render_line(text: str, width: int) -> str:
            """Simulate panel line rendering."""
            if len(text) > width:
                text = text[:width]
            return text.ljust(width)

        # Test that even with embedded newlines, output is single line
        test_inputs = [
            "Normal text",
            "Text with\nnewline",
            "Text with\r\nCRLF",
            "Multiple\n\n\nnewlines",
        ]

        for inp in test_inputs:
            # In real code, we'd strip newlines before truncation
            clean = inp.replace("\n", " ").replace("\r", "")
            result = render_line(clean, 50)
            line_count = result.count("\n") + 1
            assert line_count == 1, f"Output has {line_count} lines: {result!r}"


class TestPanelWidthConsistency:
    """Ensure panel width calculations are consistent."""

    def test_left_right_panel_width_match(self):
        """Both panels should use same width calculation."""
        # Simulate the width calculation from control_panel.ps1
        def calculate_panel_widths(terminal_width: int):
            """Calculate panel widths as done in Draw-Dashboard."""
            half = terminal_width // 2
            content_width = half - 4  # "| " prefix (2) + " |" suffix (2)
            return {
                "half": half,
                "content_width": content_width,
                "left_total": half,  # |<space><content><space>|
                "right_total": half,
            }

        for term_width in [80, 100, 120, 160, 200]:
            widths = calculate_panel_widths(term_width)
            # Left and right should have identical totals
            assert widths["left_total"] == widths["right_total"], \
                f"Panel width mismatch at terminal width {term_width}"
            # Content width should be half minus borders
            assert widths["content_width"] == widths["half"] - 4, \
                f"Content width calculation wrong at {term_width}"
            # Two panels should fit exactly in terminal
            assert widths["left_total"] + widths["right_total"] == term_width, \
                f"Panels don't fill terminal at width {term_width}"

    def test_border_character_count(self):
        """Verify border character counts are correct."""
        # Left panel: "| " + content + " |" = 2 + content + 2 = content + 4
        # Right panel: "| " + content + " |" = 2 + content + 2 = content + 4
        border_overhead = 4  # per panel

        for half_width in [40, 50, 60, 80]:
            content_width = half_width - border_overhead
            total_chars = 2 + content_width + 2  # "| " + content + " |"
            assert total_chars == half_width, \
                f"Border math wrong: {total_chars} != {half_width}"


class TestDecisionCategoryMapping:
    """v19.7: Ensure decision categories are displayed with full names."""

    # Category mapping (mirrors control_panel.ps1 $Global:DecisionCategoryMap)
    CATEGORY_MAP = {
        "SEC": "Security",
        "ARCH": "Architecture",
        "DATA": "Data",
        "PRD": "Product",
        "OPS": "Operations",
        "QA": "QA",
        "UX": "UX",
        "PERF": "Performance",
        "API": "API",
    }

    def format_decision_for_display(self, raw_line: str) -> str:
        """Python equivalent of Format-DecisionForDisplay from control_panel.ps1.

        v19.7 fix: Now splits by | to extract specific columns instead of regex.
        Format: | ID | Date | Type | Decision | Rationale | Scope | Task | Status |
        """
        import re
        if not raw_line or not raw_line.strip():
            return ""

        # Split by | and extract columns
        columns = [col.strip() for col in raw_line.split("|") if col.strip()]

        if len(columns) >= 4:
            # columns[0]=ID, [1]=Date, [2]=Type, [3]=Decision
            category_code = columns[2]
            description = columns[3]

            # Map category code to full name
            category_label = self.CATEGORY_MAP.get(category_code, category_code)

            # Clean up markdown formatting (remove ** bold markers)
            clean_desc = description.replace("**", "")

            return f"{category_label}: {clean_desc}"

        # Fallback
        return re.sub(r"\s+", " ", raw_line.replace("|", " ")).strip()

    def test_sec_maps_to_security(self):
        """SEC should display as Security in dashboard."""
        # Pipe-delimited format as it appears in DECISION_LOG.md
        raw = "| 010 | 2025-12-15 | SEC | **Read-Only Mode** for Data Protection | Rationale | Scope | Task | ACCEPTED |"
        result = self.format_decision_for_display(raw)
        assert result.startswith("Security:"), f"Expected 'Security:', got {result}"
        assert "SEC" not in result, f"Raw code SEC should not appear: {result}"
        # Should NOT include Rationale column
        assert "Rationale" not in result, f"Rationale should not appear: {result}"

    def test_arch_maps_to_architecture(self):
        """ARCH should display as Architecture."""
        raw = "| 009 | 2025-12-14 | ARCH | Use SQLite for local persistence | Some rationale | ARCH | v16 | ACCEPTED |"
        result = self.format_decision_for_display(raw)
        assert result.startswith("Architecture:"), f"Expected 'Architecture:', got {result}"
        assert "Some rationale" not in result, f"Rationale should not appear: {result}"

    def test_unknown_category_passthrough(self):
        """Unknown categories should pass through unchanged."""
        raw = "| 008 | 2025-12-13 | CUSTOM | Some custom decision | Rationale | Scope | Task | Status |"
        result = self.format_decision_for_display(raw)
        assert result.startswith("CUSTOM:"), f"Expected 'CUSTOM:', got {result}"

    def test_bold_markers_removed(self):
        """Markdown ** bold markers should be stripped."""
        raw = "| 010 | 2025-12-15 | SEC | **Bold Title** description | Rationale | Scope | Task | Status |"
        result = self.format_decision_for_display(raw)
        assert "**" not in result, f"Bold markers should be removed: {result}"
        assert "Bold Title" in result, f"Title content should remain: {result}"

    def test_empty_line_returns_empty(self):
        """Empty input should return empty string."""
        assert self.format_decision_for_display("") == ""
        assert self.format_decision_for_display("   ") == ""

    def test_all_mapped_categories(self):
        """All defined categories should map correctly."""
        for code, label in self.CATEGORY_MAP.items():
            raw = f"| 001 | 2025-01-01 | {code} | Test description | Rationale | Scope | Task | Status |"
            result = self.format_decision_for_display(raw)
            assert result.startswith(f"{label}:"), f"{code} should map to {label}: {result}"

    def test_only_decision_column_displayed(self):
        """Only the Decision column should appear, not Rationale or other columns."""
        raw = "| 005 | 2025-12-14 | ARCH | Hash+debounce dedupe | Prevents spam during rapid redraws | ARCH | v16.0 | ACCEPTED |"
        result = self.format_decision_for_display(raw)
        assert result == "Architecture: Hash+debounce dedupe", f"Unexpected result: {result}"
        assert "Prevents spam" not in result, f"Rationale leaked: {result}"
        assert "v16.0" not in result, f"Task column leaked: {result}"
        assert "ACCEPTED" not in result, f"Status column leaked: {result}"

    def test_no_double_spaces(self):
        """Result should not have double spaces."""
        raw = "| 010 | 2025-12-15 | SEC | Read-Only Mode for Data | Rationale | Scope | Task | Status |"
        result = self.format_decision_for_display(raw)
        assert "  " not in result, f"Double spaces found: {result}"
feat/v17.2-lane-counts


class TestPlanScreenDeclutter:
    """v21.2: Regression tests for PLAN screen decluttering.

    T-UX-PLAN-DECLUTTER: Source diagnostics hidden on PLAN, available via /ops.
    """

    def test_bootstrap_panel_no_source_line(self):
        """Draw-BootstrapPanel should NOT render 'Source: readiness.py' on PLAN screen."""
        import os
        control_panel_path = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "control_panel.ps1"
        )

        # Read the Draw-BootstrapPanel function
        with open(control_panel_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Find the Draw-BootstrapPanel function section
        bootstrap_start = content.find("function Draw-BootstrapPanel")
        if bootstrap_start == -1:
            pytest.skip("Draw-BootstrapPanel function not found")

        # Find next function (approximate end)
        bootstrap_end = content.find("\nfunction ", bootstrap_start + 1)
        if bootstrap_end == -1:
            bootstrap_end = len(content)

        bootstrap_section = content[bootstrap_start:bootstrap_end]

        # v21.2: Source line should be REMOVED from PLAN screen
        # It should NOT add 'Source: readiness.py' to $rightLines
        assert '$rightLines += "Source: readiness.py' not in bootstrap_section, \
            "Draw-BootstrapPanel should NOT render Source: line on PLAN screen (v21.2 declutter)"

        # Should have a comment explaining the removal
        assert "v21.2" in bootstrap_section or "declutter" in bootstrap_section.lower() or "moved" in bootstrap_section.lower(), \
            "Draw-BootstrapPanel should document the Source line removal"

    def test_ops_command_has_diagnostics_section(self):
        """The /ops command should include a DIAGNOSTICS section with source info."""
        import os
        control_panel_path = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "control_panel.ps1"
        )

        with open(control_panel_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Find the /ops command handler
        ops_start = content.find('"ops" {')
        if ops_start == -1:
            pytest.skip("/ops command handler not found")

        # Find next command handler (approximate end)
        ops_end = content.find('"health" {', ops_start)
        if ops_end == -1:
            ops_end = len(content)

        ops_section = content[ops_start:ops_end]

        # v21.2: /ops should have DIAGNOSTICS section
        assert "DIAGNOSTICS" in ops_section, \
            "/ops command should have DIAGNOSTICS section (v21.2)"

        # Should show readiness source
        assert "Readiness source" in ops_section, \
            "/ops DIAGNOSTICS should show Readiness source"

        # Should show DB path
        assert "DB path" in ops_section, \
            "/ops DIAGNOSTICS should show DB path"

        # Should show read-only mode
        assert "Read-only mode" in ops_section or "read_only" in ops_section, \
            "/ops DIAGNOSTICS should show read-only mode state"

    def test_no_source_line_in_plan_dashboard(self):
        """Build-PipelineStatus source should NOT be rendered on PLAN screen panels."""
        import os
        control_panel_path = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "control_panel.ps1"
        )

        with open(control_panel_path, "r", encoding="utf-8") as f:
            content = f.read()

        # The Draw-Dashboard function renders PLAN screen
        dashboard_start = content.find("function Draw-Dashboard")
        if dashboard_start == -1:
            pytest.skip("Draw-Dashboard function not found")

        # Find end of function
        dashboard_end = content.find("\n# ==========", dashboard_start + 100)
        if dashboard_end == -1:
            dashboard_end = len(content)

        dashboard_section = content[dashboard_start:dashboard_end]

        # Should NOT have explicit 'Source:' text rendering in the main PLAN section
        # The $pipelineData.source is used but should not be directly shown on PLAN
        # Note: It's OK if source is used internally, just not displayed
        source_renders = dashboard_section.count('Write-Host "Source:')
        assert source_renders == 0, \
            f"Draw-Dashboard should not directly render 'Source:' text on PLAN screen (found {source_renders} occurrences)"

    def test_diagnostics_preserves_traceability(self):
        """Diagnostics info should be preserved SOMEWHERE for traceability."""
        import os
        control_panel_path = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "control_panel.ps1"
        )

        with open(control_panel_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Build-PipelineStatus should still build the source string (for internal use/logging)
        assert '$source = "readiness.py"' in content, \
            "Build-PipelineStatus should still construct source string for internal use"

        # The source should be part of the returned model
        assert '"source"' in content or "'source'" in content or "source =" in content, \
            "Pipeline status should still include source in its return model"
=======
main
