# Vibe Coding V4.0 Uranium Master - Implementation Plan

## Architecture: File-Based Prompt Compiler

**Status:** ✅ IMPLEMENTED

---

## Changes Made

### New Files Created

| File | Purpose |
|------|---------|
| `AGENTS.md` | Global constitution (v1.0) |
| `LESSONS_LEARNED.md` | Anti-regression lessons |
| `skills/_default.md` | Fallback skill pack |
| `skills/frontend.md` | Frontend lane checklist |
| `skills/backend.md` | Backend lane checklist |
| `skills/security.md` | Security lane checklist |
| `skills/ux.md` | UX/A11y lane checklist |
| `skills/data.md` | Data lane checklist |
| `skills/qa.md` | QA lane checklist |

### Controller Updates

| Function | Purpose |
|----------|---------|
| `expand_task_context()` | Prompt compiler - injects skill pack |
| `append_lesson_learned()` | Auto-append to LESSONS_LEARNED.md |

### Config Added

```python
SKILLS_DIR = "skills"           # Skill pack directory
MAX_SKILL_CHARS = 2000          # Truncation limit
LESSONS_FILE = "LESSONS_LEARNED.md"
```

---

## Refined Features (High ROI)

| # | Feature | Status |
|---|---------|--------|
| 1 | Concise skill packs (~50 lines) | ✅ |
| 2 | Fallback skill pack (`_default.md`) | ✅ |
| 3 | Goal truncation (MAX_SKILL_CHARS) | ✅ |
| 4 | Graceful validation + logging | ✅ |
| 5 | Fallback message for workers | ✅ |
| 6 | Auto-append lessons on rejection | ✅ |

---

## Compiled Prompt Flow

```
User Goal: "Fix login"
        ↓
┌─ Prompt Compiler ──────────────────────┐
│  1. Find skills/{lane}.md              │
│  2. Fallback to _default.md if missing │
│  3. Truncate if > 2000 chars           │
│  4. Append to task goal                │
│  5. Update context_files               │
└────────────────────────────────────────┘
        ↓
Worker sees:
  Goal: Fix Login.
  
  --- FRONTEND SKILLS (frontend.md) ---
  ## MUST
  - Handle Loading States
  - Handle Error States
  ...
```

---

## Verification

- [ ] Syntax check passes
- [ ] CI passes
- [ ] Test skill injection
