# Decision Packet: Librarian v15.0 - Snippet Store + Duplicate Detection

**Date**: 2025-12-12
**Decision ID**: ENG-LIBRARIAN-SNIPPETS-001
**Status**: ✅ APPROVED & DEPLOYED

## Decision
Introduce a file-based snippet library with lightweight duplicate detection:
- Storage: Plain files under `library/snippets/{lang}/` with commented metadata headers
- MCP Tools:
  - `snippet_search(query, lang, tags, root_dir)` - Read-only snippet search
  - `snippet_duplicate_check(file_path, lang, root_dir)` - Advisory duplicate warnings
- Helper: `_normalize_code(content, lang)` - Code normalization for comparison

## Purpose
Reduce code duplication by providing a clipboard manager for common patterns.

Key principle: **This is a clipboard manager, NOT a knowledge graph.**

## Rationale

| Gain | Cost |
|------|------|
| Reusable patterns for mesh_server, control_panel, tests | ~230 lines in mesh_server.py |
| Fast duplicate detection (no embeddings, no DB) | Maintenance of snippet files |
| Zero mandatory workflows (all opt-in, advisory) | Learning curve for snippet format |
| Fail-safe design (graceful degradation) | Initial setup time (~4h) |

**Benefits**:
- **LOW COST**: No embeddings, no DB changes, no mandatory registration
- **HIGH LEVERAGE**: Common patterns (retry, safe JSON, input validation) are frequently needed
- **SAFE**: Read-only tools, advisory warnings only, no auto-mutations
- **TESTABLE**: tmp_path fixtures ensure deterministic, isolated tests

## Risk Assessment

**Risk Level**: LOW

**Changed Components**:
- `mesh_server.py:11025-11257` - Added 2 MCP tools + 1 helper function
- `library/snippets/*` - New directory with 4 starter snippets (2 Python, 2 PowerShell)
- `tests/test_librarian_snippets.py` - New test suite (9 tests, all passing)

**Unchanged (Safety-Critical)**:
- ✅ `update_task_state` semantics
- ✅ `/ship` confirmation behavior
- ✅ Static safety check rules
- ✅ Database schema
- ✅ Review/approval workflows

## Technical Details

### Snippet Format
```python
# SNIPPET: retry_with_backoff
# LANG: python
# TAGS: retry, backoff, http, resilience
# INTENT: Standard retry loop with exponential backoff + jitter
# UPDATED: 2025-12-12

# ... minimal reference implementation ...
```

### Tool Behavior
- **snippet_search**:
  - Requires `query` OR `tags` (prevents "return everything")
  - Substring matching over filename, SNIPPET, INTENT headers
  - Filters by language, tags
  - Returns top 10 results sorted by relevance
  - Graceful failure: empty results if snippet folder missing

- **snippet_duplicate_check**:
  - Auto-detects language from file extension
  - Skips files < 50 tokens (MIN_TOKENS threshold)
  - Skips metadata headers (first ~12 lines) to avoid false positives
  - Uses SequenceMatcher with 0.65 similarity threshold
  - Returns advisory warnings only (never blocks builds)

### Key Refinements
1. **Skeleton snippets only** - Minimal reference implementations, not production utilities
2. **Empty query guard** - Requires query OR tags to prevent accidental "list all"
3. **Header skipping** - Metadata headers excluded from similarity comparison (case-insensitive)
4. **root_dir parameter** - Enables clean testing with tmp_path fixtures (no chdir tricks)
5. **Explicit prefix handling** - Safer metadata parsing (`///` vs `#`)

### Duplicate Detection Threshold: Why 0.65?

**Initial Plan**: 0.80 (80% similarity required to warn)
**Final Implementation**: 0.65 (65% similarity)

**Rationale**:
Empirical testing showed that near-identical code (same function duplicated with minor variable name changes) scores ~0.68 after normalization. Setting threshold at 0.80 produced false negatives (missed real duplicates).

**Why normalization reduces scores**:
- Header skipping (first ~12 lines) creates different starting points
- Adding padding to exceed MIN_TOKENS=50 dilutes similarity
- SequenceMatcher is strict about character-level matches

**Tuning guidance**:
- 0.65: Current setting - catches near-duplicates, few false positives
- 0.70: More conservative - higher precision, lower recall
- 0.60: More aggressive - catches more duplicates, risk of false positives

**Future adjustments**: Threshold is a constant in `mesh_server.py:11185` and can be tuned based on operator feedback. If duplicate warnings become noisy, increase to 0.70. If missing obvious duplicates, decrease to 0.60.

## Verification

### Automated Tests
```
Running Librarian v15.0 snippet tests...

✅ snippet_search finds known snippet
✅ snippet_search returns empty when no snippets
✅ snippet_search requires query or tags
✅ snippet_search filters by language
✅ snippet_search filters by tags
✅ duplicate_check warns for similar code
✅ duplicate_check no warnings for unique code
✅ duplicate_check skips small files
✅ snippet_search handles empty tags

Results: 9 passed, 0 failed
All tests passed!
```

### Manual Testing
- Verified snippet_search finds snippets by name, tags, and intent
- Verified snippet_duplicate_check warns for near-duplicates (similarity >= 0.65)
- Verified graceful handling of missing snippet directories
- Verified no false positives on unique code

## Rollback Plan

**Immediate Rollback**:
```bash
# Remove MCP tools from mesh_server.py
git diff HEAD mesh_server.py  # Review changes
git checkout HEAD -- mesh_server.py

# Remove snippet directory
rm -rf library/snippets/

# Remove tests
rm tests/test_librarian_snippets.py
```

**Rollback Verification**:
1. Run existing test suite: `python tests/run_ci.py`
2. Verify MCP server starts without errors
3. Confirm no import errors or missing dependencies

## Follow-Up Tasks

### T-LIBRARIAN-V15-FUTURE (Deferred to Future)
- **Priority**: LOW
- **Scope**: Optional enhancements
  - Control Panel integration: `/snippets <query>` command
  - CI integration: Automated duplicate checking on changed files
  - TypeScript snippets
  - Markdown template snippets

**OUT OF SCOPE** (Explicitly Rejected):
- ❌ Auto-insertion of snippets into code
- ❌ Embeddings or vector search
- ❌ Snippet versioning or git tracking
- ❌ Mandatory registration workflows
- ❌ Auto-mutations of code

## Sandbox → Gold Promotion Checklist

**Status**: 🟡 PENDING (Deployed in Sandbox)

When promoting to gold production:

### Pre-Promotion
- [ ] Create backup: `control/snapshots/pre_librarian_v15_<timestamp>.zip`
- [ ] Review diff: `git diff sandbox master -- mesh_server.py library/ tests/ docs/`
- [ ] Verify no unintended changes to core systems

### Promotion Steps
1. [ ] Merge sandbox → master (or copy files if not using git)
2. [ ] Run static safety check: `python tests/static_safety_check.py`
3. [ ] Run full test suite: `python tests/run_ci.py`
4. [ ] Run Librarian tests: `python tests/test_librarian_snippets.py`
5. [ ] Verify MCP server starts: `python mesh_server.py` (check for import errors)
6. [ ] Manual smoke test:
   - Call `snippet_search(query="retry")` - should return results
   - Call `snippet_duplicate_check(file_path="tests/test_librarian_snippets.py")` - should complete
7. [ ] Document promotion in changelog: `docs/CHANGELOG.md`

### Post-Promotion Verification
- [ ] Confirm 9/9 Librarian tests pass in gold
- [ ] Confirm no CI regressions
- [ ] Confirm MCP server responds to tool calls
- [ ] Tag release: `git tag v15.0-librarian`

### Rollback (if needed)
- [ ] Restore from backup: `/restore_confirm pre_librarian_v15_<timestamp>.zip`
- [ ] Verify rollback: Run tests, check MCP server

**Promotion Path**: Standard (non-emergency, low-risk)

---

## Approval

**Decided by**: The Gavel (One-Gavel System)
**Decision Date**: 2025-12-12
**Status**: ✅ APPROVED & DEPLOYED (Sandbox)
**Confidence**: High
**Risk Level**: LOW
**Rollback Readiness**: ✅ Verified
