# Test suite for Librarian v15.0 snippet tools
import sys
import os
import json
from pathlib import Path

# Ensure repo root is in path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import pytest only if available (for pytest runner)
try:
    import pytest
except ImportError:
    pytest = None

from mesh_server import snippet_search, snippet_duplicate_check


# === Fixtures ===

def setup_snippet(tmp_path, lang, snippet_id, content):
    """Helper to create a test snippet file."""
    snippet_dir = tmp_path / "library" / "snippets" / lang
    snippet_dir.mkdir(parents=True, exist_ok=True)
    ext = {"python": ".py", "powershell": ".ps1", "markdown": ".md"}.get(lang, ".txt")
    snippet_file = snippet_dir / f"{snippet_id}{ext}"
    snippet_file.write_text(content, encoding="utf-8")
    return snippet_file


def setup_target_file(tmp_path, filename, content):
    """Helper to create a test target file for duplicate checking."""
    target_file = tmp_path / filename
    target_file.write_text(content, encoding="utf-8")
    return target_file


# === Tests for snippet_search ===

def test_snippet_search_finds_known_snippet(tmp_path):
    """Verify snippet_search finds a known snippet by name."""
    setup_snippet(tmp_path, "python", "retry_helper", """# SNIPPET: retry_helper
# LANG: python
# TAGS: retry, http
# INTENT: Simple retry wrapper
# UPDATED: 2025-12-12

def retry(func):
    pass
""")

    result = snippet_search(query="retry", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["results"]) == 1
    assert data["results"][0]["id"] == "retry_helper"
    assert "retry" in data["results"][0]["tags"]


def test_snippet_search_empty_when_no_snippets(tmp_path):
    """Verify snippet_search returns empty results when no snippets exist."""
    result = snippet_search(query="nonexistent", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["results"]) == 0


def test_snippet_search_requires_query_or_tags(tmp_path):
    """Verify snippet_search requires either query or tags."""
    result = snippet_search(query="", tags="", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["results"]) == 0
    assert "message" in data
    assert "query or tags" in data["message"].lower()


def test_snippet_search_filters_by_language(tmp_path):
    """Verify snippet_search filters by language."""
    setup_snippet(tmp_path, "python", "py_helper", """# SNIPPET: py_helper
# LANG: python
# TAGS: test
# INTENT: Python helper
# UPDATED: 2025-12-12

def test():
    pass
""")

    setup_snippet(tmp_path, "powershell", "ps_helper", """# SNIPPET: ps_helper
# LANG: powershell
# TAGS: test
# INTENT: PowerShell helper
# UPDATED: 2025-12-12

function Test {}
""")

    # Search only Python
    result = snippet_search(query="helper", lang="python", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["results"]) == 1
    assert data["results"][0]["lang"] == "python"


def test_snippet_search_filters_by_tags(tmp_path):
    """Verify snippet_search filters by tags."""
    setup_snippet(tmp_path, "python", "retry_helper", """# SNIPPET: retry_helper
# LANG: python
# TAGS: retry, resilience
# INTENT: Retry wrapper
# UPDATED: 2025-12-12

def retry():
    pass
""")

    setup_snippet(tmp_path, "python", "json_helper", """# SNIPPET: json_helper
# LANG: python
# TAGS: json, parsing
# INTENT: JSON loader
# UPDATED: 2025-12-12

def load_json():
    pass
""")

    # Search by tag
    result = snippet_search(query="", tags="retry", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["results"]) == 1
    assert data["results"][0]["id"] == "retry_helper"


# === Tests for snippet_duplicate_check ===

def test_duplicate_check_warns_for_similar_code(tmp_path):
    """Verify snippet_duplicate_check warns for near-duplicate code."""
    # Create snippet
    setup_snippet(tmp_path, "python", "retry_helper", """# SNIPPET: retry_helper
# LANG: python
# TAGS: retry
# INTENT: Retry wrapper
# UPDATED: 2025-12-12

import time

def retry_function(func, max_attempts=3):
    for attempt in range(max_attempts):
        try:
            return func()
        except Exception as e:
            if attempt == max_attempts - 1:
                raise
            time.sleep(1)
""")

    # Create similar target file (must be > 50 tokens after normalization)
    # Copy the exact snippet code twice to ensure high similarity + enough tokens
    target_file = setup_target_file(tmp_path, "my_retry.py", """import time

def retry_function(func, max_attempts=3):
    for attempt in range(max_attempts):
        try:
            return func()
        except Exception as e:
            if attempt == max_attempts - 1:
                raise
            time.sleep(1)

def another_retry(func, max_attempts=3):
    for attempt in range(max_attempts):
        try:
            return func()
        except Exception as e:
            if attempt == max_attempts - 1:
                raise
            time.sleep(1)
""")

    result = snippet_duplicate_check(str(target_file), lang="python", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK", f"Status error: {data}"
    assert len(data["warnings"]) > 0, f"Expected warnings but got: {data}"
    # Production threshold is 0.65
    assert data["warnings"][0]["similarity"] >= 0.65


def test_duplicate_check_no_warnings_for_unique_code(tmp_path):
    """Verify snippet_duplicate_check doesn't warn for unique code."""
    # Create snippet
    setup_snippet(tmp_path, "python", "retry_helper", """# SNIPPET: retry_helper
# LANG: python
# TAGS: retry
# INTENT: Retry wrapper
# UPDATED: 2025-12-12

def retry_function():
    pass
""")

    # Create completely different target file
    target_file = setup_target_file(tmp_path, "unique.py", """# Completely different code
class MyUniqueClass:
    def __init__(self):
        self.value = 42

    def process_data(self, data):
        return data * 2

    def calculate_sum(self, numbers):
        return sum(numbers)
""")

    result = snippet_duplicate_check(str(target_file), lang="python", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["warnings"]) == 0


def test_duplicate_check_skips_small_files(tmp_path):
    """Verify snippet_duplicate_check skips files with < 50 tokens."""
    # Create snippet
    setup_snippet(tmp_path, "python", "small_snippet", """# SNIPPET: small_snippet
# LANG: python
# TAGS: test
# INTENT: Small snippet
# UPDATED: 2025-12-12

def test():
    pass
""")

    # Create small target file (< 50 tokens)
    target_file = setup_target_file(tmp_path, "small.py", """def test():
    pass
""")

    result = snippet_duplicate_check(str(target_file), lang="python", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["warnings"]) == 0
    assert "message" in data
    assert "too small" in data["message"].lower()


def test_snippet_search_handles_empty_tags_gracefully(tmp_path):
    """Verify snippet_search handles empty tag strings gracefully (no empty strings in output)."""
    setup_snippet(tmp_path, "python", "test_helper", """# SNIPPET: test_helper
# LANG: python
# TAGS:
# INTENT: Test helper
# UPDATED: 2025-12-12

def test():
    pass
""")

    result = snippet_search(query="test", root_dir=str(tmp_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    if len(data["results"]) > 0:
        # Tags should be an empty list, not [""]
        assert data["results"][0]["tags"] == [] or all(t for t in data["results"][0]["tags"])


# === Standalone runner ===

if __name__ == "__main__":
    import tempfile

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)

            print("Running Librarian v15.0 snippet tests...")
            print()

            tests = [
                ("snippet_search finds known snippet", test_snippet_search_finds_known_snippet),
                ("snippet_search returns empty when no snippets", test_snippet_search_empty_when_no_snippets),
                ("snippet_search requires query or tags", test_snippet_search_requires_query_or_tags),
                ("snippet_search filters by language", test_snippet_search_filters_by_language),
                ("snippet_search filters by tags", test_snippet_search_filters_by_tags),
                ("duplicate_check warns for similar code", test_duplicate_check_warns_for_similar_code),
                ("duplicate_check no warnings for unique code", test_duplicate_check_no_warnings_for_unique_code),
                ("duplicate_check skips small files", test_duplicate_check_skips_small_files),
                ("snippet_search handles empty tags", test_snippet_search_handles_empty_tags_gracefully),
            ]

            passed = 0
            failed = 0

            for name, test_func in tests:
                try:
                    # Create a fresh tmp directory for each test
                    with tempfile.TemporaryDirectory() as test_tmpdir:
                        test_tmp = Path(test_tmpdir)
                        test_func(test_tmp)
                        print(f"✅ {name}")
                        passed += 1
                except AssertionError as e:
                    print(f"❌ {name}:")
                    print(f"   {e}")
                    failed += 1
                except Exception as e:
                    print(f"❌ {name}: {type(e).__name__}: {e}")
                    failed += 1

            print()
            print(f"Results: {passed} passed, {failed} failed")

            if failed > 0:
                sys.exit(1)
            else:
                print("All tests passed!")
                sys.exit(0)

    except Exception as e:
        print(f"❌ Test setup error: {e}")
        sys.exit(1)
