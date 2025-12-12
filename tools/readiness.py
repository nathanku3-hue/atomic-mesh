#!/usr/bin/env python3
"""
Lightweight context readiness checker for Atomic Mesh BOOTSTRAP mode.
v13.6: Fast heuristic (<10ms) - NO heavy imports, NO LLM dependencies.

Usage:
    python tools/readiness.py

Returns:
    JSON with status, scores, and missing elements
"""

import os
import re
import json
from pathlib import Path


def get_context_readiness():
    """
    Analyzes Golden Docs (PRD, SPEC, DECISION_LOG) for completeness.

    Scoring Logic (per file):
    - Base: 0%
    - Exists: +10%
    - Length >150 words: +20%
    - Each required header found: +10% (max 50%)
    - >5 bullet points (including checkboxes): +20%

    Thresholds: PRD ≥80%, SPEC ≥80%, DECISION_LOG ≥30%
    """
    # Determine base directory (project root)
    script_dir = Path(__file__).parent
    base_dir = script_dir.parent
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

            # Word count (rough estimate: split by whitespace)
            words = len(content.split())
            length = words

            # Length check: +20% if >150 words
            if words > 150:
                score += 20

            # Header check: +10% per required header (max 50%)
            for header in config["required_headers"]:
                if re.search(re.escape(header), content, re.IGNORECASE | re.MULTILINE):
                    headers_found += 1
                    score += 10
                else:
                    missing_headers.append(header)

            # Bullet check: +20% if >5 bullet points
            # Match lines starting with "- ", "* ", "1. ", or "- [ ]" (checkboxes)
            bullet_lines = re.findall(
                r'^[\s]*(?:[-*]|\d+\.)\s+(?:\[[ xX]\]\s+)?',
                content,
                re.MULTILINE
            )
            bullets_found = len(bullet_lines)
            if bullets_found > 5:
                score += 20

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
    result = get_context_readiness()
    print(json.dumps(result, indent=2))
