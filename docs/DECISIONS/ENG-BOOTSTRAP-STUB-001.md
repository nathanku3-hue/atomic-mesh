# ENG-BOOTSTRAP-STUB-001: Template Stub Detection for Bootstrap Mode

**Date**: 2025-12-13
**Status**: ✅ Active
**Context**: Fix bootstrap integrity issue where `/init` templates incorrectly trigger EXECUTION mode

---

## Problem

After running `/init` on a fresh project, the system should display BOOTSTRAP mode with PRD/SPEC/DECISION_LOG readiness bars. However, the readiness scorer was treating generated template files as "complete enough", immediately flipping to EXECUTION mode and hiding the bootstrap panel.

### Root Cause

Templates contain:
- Required headers (## Goals, ## User Stories, etc.)
- Checkbox bullets (- [ ])
- Placeholder text ([...], {{...}})

The heuristic counted these as real content, pushing scores over thresholds:
- PRD template: 10% (exists) + 20% (>150 words) + 30% (headers) + 20% (bullets) = **80%** ✓
- SPEC template: Same calculation = **80%** ✓
- Result: Immediate EXECUTION mode on fresh `/init`

---

## Solution

### 1. Template Stub Marker

Added `<!-- ATOMIC_MESH_TEMPLATE_STUB -->` to the first line of:
- `library/templates/PRD.template.md`
- `library/templates/SPEC.template.md`
- `library/templates/DECISION_LOG.template.md`

### 2. Stub-Aware Scoring Logic

Updated `tools/readiness.py` to detect stub marker and apply different scoring:

**For stub files without real content:**
- Base: 10% (exists)
- Headers: 10% each
- Length bonus: DISABLED
- Bullet bonus: DISABLED
- **Cap: 40% maximum**

**For stub files with ≥6 meaningful lines:**
- Base: 10% (exists)
- Headers: 10% each
- Length bonus: RE-ENABLED if >150 words
- Bullet bonus: RE-ENABLED if >5 bullets
- Extra bonus: +20% if ≥10 meaningful lines
- **Can reach 80%+ threshold**

### 3. Meaningful Line Detection

Added `is_meaningful_line()` function that filters out:
- Blank lines
- Header-only lines (## ...)
- Placeholder patterns ([...], {{...}})
- Unchecked checkboxes (- [ ])
- Lines with <4 words

### 4. Regression Tests

Created `tests/test_readiness_stub_detection.py` with 5 test cases:
1. ✅ Template stubs keep system in BOOTSTRAP mode
2. ✅ Real content (≥6 meaningful lines) unlocks higher scores
3. ✅ Meaningful line detection works correctly
4. ✅ System transitions to EXECUTION only with real content
5. ✅ Non-stub files use original scoring (backward compatibility)

---

## Impact

### Before Fix
```json
{
  "status": "EXECUTION",
  "files": {
    "PRD": {"score": 80},    // Template counted as complete!
    "SPEC": {"score": 80}    // Template counted as complete!
  }
}
```

### After Fix
```json
{
  "status": "BOOTSTRAP",
  "files": {
    "PRD": {"score": 40},    // Stub detected, capped at 40%
    "SPEC": {"score": 40}    // Stub detected, capped at 40%
  }
}
```

### With Real Content (≥10 meaningful lines)
```json
{
  "status": "EXECUTION",
  "files": {
    "PRD": {"score": 80},    // Real content detected, full scoring
    "SPEC": {"score": 80}
  }
}
```

---

## Files Modified

1. `library/templates/PRD.template.md` - Added stub marker
2. `library/templates/SPEC.template.md` - Added stub marker
3. `library/templates/DECISION_LOG.template.md` - Added stub marker
4. `tools/readiness.py` - Added stub detection and meaningful line logic
5. `tests/test_readiness_stub_detection.py` - New regression test suite

---

## Testing

Run regression tests:
```bash
python -m unittest tests.test_readiness_stub_detection -v
```

All 5 tests should pass:
- ✅ test_template_stubs_stay_in_bootstrap_mode
- ✅ test_real_content_unlocks_higher_scores
- ✅ test_meaningful_line_detection
- ✅ test_transition_to_execution_mode
- ✅ test_non_stub_files_scored_normally

---

## Safety Guarantees

1. **No changes to core governance** - Only affects readiness scoring
2. **Backward compatible** - Non-stub files use original scoring
3. **No UI changes required** - Existing BOOTSTRAP/EXECUTION logic works
4. **No schema changes** - Pure scoring logic update
5. **Regression protected** - Comprehensive test coverage

---

## Future Considerations

If DECISION_LOG template becomes more complex and reaches 30% threshold with stubs, apply the same stub marker pattern there (already implemented).

---

**Acceptance Criteria Met:**
- ✅ Fresh /init → BOOTSTRAP mode with readiness bars visible
- ✅ Template stubs score ≤40% (below thresholds)
- ✅ Adding real content (≥6 meaningful lines) allows score >40%
- ✅ EXECUTION mode only when real content meets thresholds
- ✅ Comprehensive regression tests added
- ✅ No changes to update_task_state, /ship, or DB schema
