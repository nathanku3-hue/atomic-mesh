# Librarian Cache Schema

## Location
```
<ProjectPath>/control/state/librarian_doc_feedback.json
```

## Schema (v1)

```json
{
  "version": 1,
  "generated_at": "2025-12-20T10:00:00Z",
  "overall_quality": 4,
  "confidence": 85,
  "critical_risks": ["missing error handling", "no test coverage"],
  "docs": {
    "PRD": {
      "one_liner": "add goals section",
      "paragraph": "The PRD needs a clear goals section with measurable outcomes."
    },
    "SPEC": {
      "one_liner": "ready",
      "paragraph": ""
    },
    "DECISION_LOG": {
      "one_liner": "add decisions",
      "paragraph": "Document key architectural decisions."
    }
  }
}
```

## Field Reference

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `version` | int | 1 | Schema version |
| `overall_quality` | int | 0-5 | Librarian's quality assessment (0 = not assessed) |
| `confidence` | int | 0-100 | Confidence in assessment (%) |
| `critical_risks` | array | - | List of critical risk strings |
| `docs.{name}.one_liner` | string | - | Short hint (shown in DOCS panel) |
| `docs.{name}.paragraph` | string | - | Detailed feedback (shown on toggle) |

## Tier Mapping Rules

The UI displays a readiness tier based on these rules (evaluated in order):

| Tier | Condition | Header Display |
|------|-----------|----------------|
| **BLOCKED** | `DocsAllPassed = false` | `DOCS` (no indicator) |
| **PASS** | No Librarian data OR `confidence < 50` | `DOCS L:x/5 (PASS)` |
| **REVIEW** | `critical_risks.length > 0` | `DOCS L:x/5! (REVIEW)` |
| **PASS+** | `quality >= 4` AND `confidence >= 80` | `DOCS L:x/5 (PASS+)` |

## Staleness

- Cache is **stale** if file mtime > 10 minutes old
- Stale indicator: `*` appended to hints and header (e.g., `L:4/5*`)
- Stale data is still shown (fail-open), just marked

## Source of Truth

- **Cache writer**: Librarian subagent (out-of-band, not in UI loop)
- **Cache reader**: `tools/snapshot.py` → `get_librarian_feedback()`
- **Tier logic**: `ComputePipelineStatus.ps1` → `Get-DocsReadinessLevel`
