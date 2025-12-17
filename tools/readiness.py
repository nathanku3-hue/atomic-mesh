#!/usr/bin/env python3
"""
Lightweight context readiness checker for Atomic Mesh BOOTSTRAP mode.
v15.0: Fast heuristic (<10ms) - NO heavy imports, NO LLM dependencies.

Usage:
    python tools/readiness.py

Returns:
    JSON with status, scores, and missing elements
"""

import os
import re
import json
from pathlib import Path
from difflib import SequenceMatcher


def is_meaningful_line(line):
    """
    Determines if a line contains real user content (not template placeholders).

    Returns False for:
    - Blank lines
    - Header-only lines (## ...)
    - Lines with placeholder patterns ([...], {{...}})
    - Unchecked checkboxes (- [ ])
    - Lines with < 4 words
    - Bold-only labels (**...**)
    - Blockquotes (> ...)
    - Italic-only lines (*...*)
    - Horizontal rules (---)
    """
    line = line.strip()

    # Skip blank lines
    if not line:
        return False

    # Skip header-only lines
    if re.match(r'^#{1,6}\s+', line):
        return False

    # Skip horizontal rules
    if re.match(r'^-{3,}$', line):
        return False

    # Skip blockquotes (template instructions)
    if line.startswith('>'):
        return False

    # Skip bold-only labels (e.g., **What are we building?**)
    if re.match(r'^\*\*[^*]+\*\*:?$', line):
        return False

    # Skip italic-only lines (e.g., *Template version: 15.0*)
    if re.match(r'^\*[^*]+\*$', line):
        return False

    # Skip lines with template placeholders
    if re.search(r'\{\{.*?\}\}', line) or re.search(r'\[.*?\]', line):
        return False

    # Skip unchecked checkboxes
    if re.match(r'^[\s]*[-*]\s+\[\s*\]', line):
        return False

    # Skip lines with < 4 words
    words = line.split()
    if len(words) < 4:
        return False

    return True


def normalize_for_comparison(content: str) -> str:
    """
    Normalize content for template similarity comparison.
    Strips metadata, dates, placeholders, and collapses whitespace.
    """
    # Remove stub marker
    content = content.replace('<!-- ATOMIC_MESH_TEMPLATE_STUB -->', '')
    # Remove HTML comments
    content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)
    # Remove dates (YYYY-MM-DD)
    content = re.sub(r'\d{4}-\d{2}-\d{2}', '', content)
    # Remove placeholder patterns {{...}}
    content = re.sub(r'\{\{[^}]+\}\}', '', content)
    # Remove numeric IDs in table rows (e.g., | 001 |, | 1734567890 |)
    content = re.sub(r'\|\s*\d+\s*\|', '| |', content)
    # Collapse whitespace
    content = re.sub(r'\s+', ' ', content)
    return content.strip().lower()


def get_template_similarity(content: str, template_path: Path) -> float:
    """
    Compare content against a template using SequenceMatcher.
    Returns similarity ratio (0.0 to 1.0).
    """
    if not template_path.exists():
        return 0.0

    try:
        template_content = template_path.read_text(encoding='utf-8')
        norm_content = normalize_for_comparison(content)
        norm_template = normalize_for_comparison(template_content)

        # Use SequenceMatcher for fast similarity check
        return SequenceMatcher(None, norm_content, norm_template).ratio()
    except Exception:
        return 0.0


def has_real_decisions(content: str) -> bool:
    """
    Check if DECISION_LOG has real decision rows beyond the bootstrap init row.

    Returns True if:
    - There are decision rows with Type != INIT (new format)
    - There are multiple decision rows (more than just the init row)
    - There's a decision row with a non-bootstrap Decision text

    Returns False if:
    - Only the init row exists
    - File matches template structure with no additions

    Handles both old format (5 cols) and new format (8 cols):
    - Old: | ID | Date | Decision | Context | Status |
    - New: | ID | Date | Type | Decision | Rationale | Scope | Task | Status |
    """
    # Find all table rows under ## Records
    # Table row pattern: | ID | ... |
    # Skip header row and separator row
    table_row_pattern = r'^\|\s*(\d+|\w+)\s*\|'

    lines = content.split('\n')
    in_records_section = False
    decision_rows = []

    for line in lines:
        line_stripped = line.strip()

        # Detect ## Records section
        if re.match(r'^##\s*Records', line_stripped, re.IGNORECASE):
            in_records_section = True
            continue

        # Exit section on next ## header
        if in_records_section and re.match(r'^##\s+', line_stripped):
            break

        # Skip if not in records section
        if not in_records_section:
            continue

        # Skip table header and separator
        if '| ID |' in line or re.match(r'^\|[-\s|]+\|$', line_stripped):
            continue

        # Check for data rows
        if re.match(table_row_pattern, line_stripped):
            # Parse the row to extract columns
            parts = [p.strip() for p in line_stripped.split('|') if p.strip()]

            if len(parts) >= 3:
                # Detect format by checking if 3rd column looks like a Type (INIT, ARCH, etc.)
                # or like a Decision text
                col_3 = parts[2] if len(parts) > 2 else ''

                # New format types: INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE
                new_format_types = {'INIT', 'SCOPE', 'ARCH', 'API', 'DATA', 'SECURITY', 'UX', 'PERF', 'OPS', 'TEST', 'RELEASE'}

                if col_3.upper() in new_format_types:
                    # New 8-column format: | ID | Date | Type | Decision | ...
                    row_type = col_3.upper()
                    row_decision = parts[3] if len(parts) > 3 else ''
                else:
                    # Old 5-column format: | ID | Date | Decision | Context | Status |
                    row_type = ''  # No type column in old format
                    row_decision = col_3  # 3rd column is Decision

                decision_rows.append({
                    'type': row_type,
                    'decision': row_decision
                })

    # No decision rows found
    if not decision_rows:
        return False

    # Check for real decisions (not just bootstrap)
    for row in decision_rows:
        decision_lower = row['decision'].lower()

        # Skip bootstrap init rows
        if row['type'] == 'INIT':
            if 'project initialized' in decision_lower or 'bootstrap' in decision_lower:
                continue

        # Old format: check decision text for bootstrap patterns
        if not row['type']:
            # If decision mentions "project initialized" or bootstrap, skip it
            if 'project initialized' in decision_lower:
                continue
            if decision_lower.startswith('bootstrap'):
                continue

        # Found a real decision
        return True

    # Only bootstrap rows exist
    return False


def get_context_readiness(base_dir=None):
    """
    Analyzes Golden Docs (PRD, SPEC, DECISION_LOG) for completeness.

    Args:
        base_dir: Optional base directory path (for testing). If None, uses project root.

    Scoring Logic (per file):
    - Base: 0%
    - Exists: +10%
    - Length >150 words: +20%
    - Each required header found: +10% (max 50%)
    - >5 bullet points (including checkboxes): +20%

    Template Stub Detection:
    - If file contains ATOMIC_MESH_TEMPLATE_STUB marker:
      - Still gets exists + headers credit
      - Bullet credit is DISABLED
      - Requires ≥6 meaningful lines to score >40%
      - Meaningful lines = non-placeholder, non-checkbox, ≥4 words

    Thresholds: PRD ≥80%, SPEC ≥80%, DECISION_LOG ≥30%
    """
    # Determine base directory (project root)
    if base_dir is None:
        script_dir = Path(__file__).parent
        base_dir = script_dir.parent
    else:
        base_dir = Path(base_dir)

    docs_dir = base_dir / "docs"

    # File definitions
    files_to_check = {
        "PRD": {
            "path": docs_dir / "PRD.md",
            "threshold": 80,
            "required_headers": ["## Goals", "## User Stories", "## Success Metrics"]
        },
        "SPEC": {
            "path": docs_dir / "SPEC.md",
            "alt_path": docs_dir / "ACTIVE_SPEC.md",
            "threshold": 80,
            "required_headers": ["## Data Model", "## API", "## Security"]
        },
        "DECISION_LOG": {
            "path": docs_dir / "DECISION_LOG.md",
            "threshold": 30,
            "required_headers": ["## Records"]
        }
    }

    results = {}

    for doc_name, config in files_to_check.items():
        # Check if file exists (try alt_path for SPEC)
        file_path = config["path"]
        if not file_path.exists() and "alt_path" in config:
            file_path = config["alt_path"]

        score = 0
        exists = file_path.exists()
        length = 0
        headers_found = 0
        bullets_found = 0
        missing_headers = []

        if not exists:
            # Base case: file doesn't exist
            results[doc_name] = {
                "score": 0,
                "exists": False,
                "length": 0,
                "headers": 0,
                "bullets": 0,
                "missing": config["required_headers"]
            }
            continue

        # File exists: +10%
        score += 10

        # Read and analyze content
        try:
            content = file_path.read_text(encoding='utf-8')

            # Check if this is a template stub
            is_stub = 'ATOMIC_MESH_TEMPLATE_STUB' in content

            # Word count (rough estimate: split by whitespace)
            words = len(content.split())
            length = words

            # Length check: +20% if >150 words (disabled for stubs)
            if words > 150 and not is_stub:
                score += 20

            # Header check: +10% per required header (max 50%)
            # v18.2: Flexible header matching - allows:
            #   - "## Goals" (markdown h2)
            #   - "# Goals" (markdown h1)
            #   - "Goals" (plain text at line start)
            for header in config["required_headers"]:
                # Extract header text without ## prefix
                header_text = header.lstrip('# ').strip()
                # Match: optional 1-6 # chars + optional whitespace + header text
                # Note: {{1,6}} escapes braces in f-string to produce {1,6} in regex
                # Header must be at end of line OR followed by parenthetical (e.g., "API (Internal)")
                # This prevents "Goals are important" from matching as "Goals" header
                pattern = rf'^(?:#{{1,6}}\s+)?{re.escape(header_text)}(?:[\s:]*$|\s*\()'
                if re.search(pattern, content, re.IGNORECASE | re.MULTILINE):
                    headers_found += 1
                    score += 10
                else:
                    missing_headers.append(header)

            # Bullet check: +20% if >5 bullet points (disabled for stubs)
            # v18.2: Match lines starting with:
            #   - "- ", "* ", "1. " (standard bullets)
            #   - "- [ ]", "- [x]" (bulleted checkboxes)
            #   - "[ ]", "[x]" (standalone checkboxes - common in generated docs)
            bullet_lines = re.findall(
                r'^[\s]*(?:(?:[-*]|\d+\.)\s+(?:\[[ xX]\]\s+)?|\[[ xX]\]\s+)',
                content,
                re.MULTILINE
            )
            bullets_found = len(bullet_lines)
            if bullets_found > 5 and not is_stub:
                score += 20

            # For stubs: require meaningful content to unlock higher scores
            if is_stub:
                # v15.0: Special handling for DECISION_LOG
                # Check for real decisions beyond bootstrap init row
                if doc_name == "DECISION_LOG":
                    # DECISION_LOG needs real decision rows to unlock scoring
                    if has_real_decisions(content):
                        # Has real decisions: give credit and allow full scoring
                        # Table rows don't count as bullets, so give explicit credit
                        score += 10  # Bonus for having real decisions
                        if words > 150:
                            score += 20
                        if bullets_found > 5:
                            score += 20
                    else:
                        # Template similarity check (threshold: 0.85)
                        template_path = base_dir / "library" / "templates" / "DECISION_LOG.template.md"
                        similarity = get_template_similarity(content, template_path)

                        # If very similar to template OR no real decisions: cap at 40%
                        if similarity >= 0.85:
                            score = min(score, 40)
                        else:
                            # Not similar to template but no real decisions
                            # Still cap at 40% - need actual decision rows
                            score = min(score, 40)
                else:
                    # PRD and SPEC: use meaningful line detection
                    meaningful_lines = [
                        line for line in content.split('\n')
                        if is_meaningful_line(line)
                    ]
                    meaningful_count = len(meaningful_lines)

                    # Cap stub score at 40% unless ≥6 meaningful lines exist
                    if meaningful_count >= 6:
                        # Treat as real content: re-enable length and bullet bonuses
                        if words > 150:
                            score += 20
                        if bullets_found > 5:
                            score += 20
                        # Additional credit for substantial meaningful content
                        # This ensures docs with prose (not bullets) can still pass
                        if meaningful_count >= 10:
                            score += 20  # Bonus for substantial real content
                    else:
                        # Cap at 40% for stub files without real content
                        score = min(score, 40)

        except Exception as e:
            # File read error - treat as empty but log to stderr
            import sys
            print(f"Warning: Error reading {file_path}: {e}", file=sys.stderr)
            score = 10  # Still gets "exists" credit

        results[doc_name] = {
            "score": min(score, 100),  # Cap at 100%
            "exists": True,
            "length": length,
            "headers": headers_found,
            "bullets": bullets_found,
            "missing": missing_headers
        }

    # Determine overall status
    thresholds = {name: config["threshold"] for name, config in files_to_check.items()}
    blocking_files = [
        name for name, data in results.items()
        if data["score"] < thresholds[name]
    ]

    status = "EXECUTION" if len(blocking_files) == 0 else "BOOTSTRAP"

    return {
        "status": status,
        "files": results,
        "thresholds": thresholds,
        "overall": {
            "ready": status == "EXECUTION",
            "blocking_files": blocking_files
        }
    }


if __name__ == "__main__":
    # Run check and output JSON
    # v14.1: Accept optional base_dir argument for cross-project use
    import sys
    base_dir = sys.argv[1] if len(sys.argv) > 1 else None
    result = get_context_readiness(base_dir=base_dir)
    print(json.dumps(result, indent=2))
