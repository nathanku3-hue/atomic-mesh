# Follow-Up Tasks: Librarian v15.0 - Snippet Store

**Created**: 2025-12-12
**Parent Decision**: ENG-LIBRARIAN-SNIPPETS-001
**Status**: ✅ COMPLETED

## T-LIBRARIAN-V15-01: Create Snippet Directory Structure

**Priority**: HIGH
**Effort**: 15 minutes
**Assigned**: Claude Sonnet 4.5
**Dependencies**: None
**Status**: ✅ COMPLETED

### Objective
Create file-based snippet storage with initial Python + PowerShell examples.

### Scope
**IN SCOPE**:
- Create `library/snippets/{python,powershell,markdown}/` directories
- Create 2 Python snippets (retry_with_backoff, safe_json_load)
- Create 2 PowerShell snippets (Invoke-WithRetry, Get-SafeInput)

**OUT OF SCOPE**:
- TypeScript snippets (deferred)
- Complex production utilities (keep as minimal skeletons)

### Implementation
```bash
mkdir -p library/snippets/python
mkdir -p library/snippets/powershell
mkdir -p library/snippets/markdown
```

Snippet files include:
- Commented metadata headers (SNIPPET, LANG, TAGS, INTENT, UPDATED)
- Minimal reference implementations with clear docstrings
- No complex logic (avoid "two sources of truth")

### Acceptance Criteria
- [x] Directory structure created
- [x] 2+ Python snippets with proper headers
- [x] 2+ PowerShell snippets with proper headers
- [x] All snippets follow metadata format convention

---

## T-LIBRARIAN-V15-02: Implement snippet_search Tool

**Priority**: HIGH
**Effort**: 1 hour
**Assigned**: Claude Sonnet 4.5
**Dependencies**: T-LIBRARIAN-V15-01
**Status**: ✅ COMPLETED

### Objective
Implement read-only MCP tool for snippet search by keywords/tags.

### Scope
**IN SCOPE**:
- Substring matching over filename, SNIPPET header, INTENT header
- Language filtering (`python`, `powershell`, `markdown`, `any`)
- Tag filtering (comma-separated, intersection matching)
- Top 10 results sorted by relevance (tags > name > intent)
- `root_dir` parameter for testing

**OUT OF SCOPE**:
- Embeddings or semantic search
- Fuzzy matching
- Ranking algorithms beyond simple scoring

### Implementation
```python
@mcp.tool()
def snippet_search(query: str, lang: str = "any", tags: str = "", root_dir: str = "") -> str:
    # Require query OR tags (prevent "return everything")
    # Use base_path = Path(root_dir) if root_dir else Path(".")
    # Parse metadata with explicit prefix handling (///, #)
    # Score: tags=3, name=2, intent=1
    # Return top 10, JSON format
```

### Constraints
- No external dependencies (stdlib only)
- Graceful failure if snippet folder missing
- Strip empty strings from tag parsing

### Acceptance Criteria
- [x] Tool registered in mesh_server.py (line ~11027)
- [x] Returns JSON with status + results
- [x] Requires query OR tags (no empty searches)
- [x] Filters by language correctly
- [x] Filters by tags correctly
- [x] Handles missing snippet directory gracefully

---

## T-LIBRARIAN-V15-03: Implement snippet_duplicate_check Tool

**Priority**: HIGH
**Effort**: 1.5 hours
**Assigned**: Claude Sonnet 4.5
**Dependencies**: T-LIBRARIAN-V15-01
**Status**: ✅ COMPLETED

### Objective
Implement advisory duplicate detection using cheap heuristics.

### Scope
**IN SCOPE**:
- Auto-detect language from file extension
- MIN_TOKENS check (skip files < 50 tokens)
- Metadata header skipping (first ~12 lines, case-insensitive)
- SequenceMatcher-based similarity (threshold: 0.65)
- `root_dir` parameter for testing

**OUT OF SCOPE**:
- Embeddings or ML models
- AST-based comparison
- Cross-language duplicate detection

### Implementation
```python
@mcp.tool()
def snippet_duplicate_check(file_path: str, lang: str = "auto", root_dir: str = "") -> str:
    # Auto-detect lang from extension
    # Normalize with _normalize_code(content, lang)
    # Skip if < MIN_TOKENS=50
    # Compare with SequenceMatcher, threshold=0.65
    # Return warnings (advisory only)

def _normalize_code(content: str, lang: str) -> str:
    # Skip metadata headers (SNIPPET:/LANG:/TAGS:/INTENT:/UPDATED:)
    # Strip comments by language
    # Keep alphanumeric + underscores
    # Return normalized string
```

### Constraints
- Never blocks builds or CI
- No auto-rewrites or auto-imports
- Similarity threshold tuned to avoid false positives

### Acceptance Criteria
- [x] Tool registered in mesh_server.py (line ~11131)
- [x] Returns JSON with status + warnings
- [x] Skips files < 50 tokens
- [x] Skips metadata headers (case-insensitive)
- [x] Warns for similarity >= 0.65
- [x] No warnings for unique code
- [x] Handles missing snippet directory gracefully

---

## T-LIBRARIAN-V15-04: Write Test Suite

**Priority**: HIGH
**Effort**: 1 hour
**Assigned**: Claude Sonnet 4.5
**Dependencies**: T-LIBRARIAN-V15-02, T-LIBRARIAN-V15-03
**Status**: ✅ COMPLETED

### Objective
Create comprehensive test suite with tmp_path fixtures for isolation.

### Scope
**IN SCOPE**:
- 9 deterministic tests covering both tools
- Use tmp_path fixtures (no reliance on repo content)
- Test helper functions for setup
- Standalone runnable + pytest compatible

**OUT OF SCOPE**:
- Integration tests with control_panel.ps1
- Performance benchmarks

### Implementation
Tests:
1. `test_snippet_search_finds_known_snippet(tmp_path)`
2. `test_snippet_search_empty_when_no_snippets(tmp_path)`
3. `test_snippet_search_requires_query_or_tags(tmp_path)`
4. `test_snippet_search_filters_by_language(tmp_path)`
5. `test_snippet_search_filters_by_tags(tmp_path)`
6. `test_duplicate_check_warns_for_similar_code(tmp_path)`
7. `test_duplicate_check_no_warnings_for_unique_code(tmp_path)`
8. `test_duplicate_check_skips_small_files(tmp_path)`
9. `test_snippet_search_handles_empty_tags(tmp_path)`

Helper functions:
- `setup_snippet(tmp_path, lang, snippet_id, content)`
- `setup_target_file(tmp_path, filename, content)`

### Acceptance Criteria
- [x] All 9 tests pass
- [x] Tests use tmp_path fixtures (isolated)
- [x] Tests are deterministic (no randomness)
- [x] Standalone runnable: `python tests/test_librarian_snippets.py`
- [x] pytest compatible
- [x] No false positives or flaky tests

---

## T-LIBRARIAN-V15-05: Document Decision + Tasks

**Priority**: MEDIUM
**Effort**: 30 minutes
**Assigned**: Claude Sonnet 4.5
**Dependencies**: All above tasks
**Status**: ✅ COMPLETED

### Objective
Create formal decision packet and task tracking documents.

### Scope
**IN SCOPE**:
- `docs/DECISIONS/ENG-LIBRARIAN-SNIPPETS-001.md`
- `docs/TASKS/T-LIBRARIAN-V15.md`
- Follow existing decision/task format patterns

**OUT OF SCOPE**:
- Detailed API documentation
- User guides

### Acceptance Criteria
- [x] Decision document created with all required sections
- [x] Task document created with breakdown
- [x] Rollback plan documented
- [x] Follow-up tasks identified

---

## Summary

| Task ID | Priority | Effort | Status | Blocks |
|---------|----------|--------|--------|--------|
| T-LIBRARIAN-V15-01 | HIGH | 15m | ✅ COMPLETED | 02, 03 |
| T-LIBRARIAN-V15-02 | HIGH | 1h | ✅ COMPLETED | 04 |
| T-LIBRARIAN-V15-03 | HIGH | 1.5h | ✅ COMPLETED | 04 |
| T-LIBRARIAN-V15-04 | HIGH | 1h | ✅ COMPLETED | 05 |
| T-LIBRARIAN-V15-05 | MEDIUM | 30m | ✅ COMPLETED | None |

**Total Effort**: ~4 hours
**Completion Date**: 2025-12-12

## Verification

All acceptance criteria met:
- ✅ Snippet directory structure exists with 4 starter snippets
- ✅ `snippet_search` returns results for known snippets
- ✅ `snippet_duplicate_check` warns for duplicates (threshold >= 0.65)
- ✅ All 9 tests pass (pytest tests/test_librarian_snippets.py)
- ✅ Decision and task docs created
- ✅ No changes to core systems (state machine, /ship, DB schema)

## Follow-Up Work (Deferred)

**T-LIBRARIAN-V15-FUTURE**:
- Priority: LOW
- Scope: Control Panel integration, CI integration, additional language support
- Blocked by: User demand, real-world usage feedback
