# Attribution Rules (_default.md)

## Purpose
Define how to track and attribute the origin of ideas, code, and decisions.

---

## Source Attribution Format

### Task-Level Attribution
Every task MUST include a `source` field:

```json
{
  "source": {
    "origin": "architect | po | worker | external | thesis",
    "author": "@username",
    "reference": "optional: meeting date | ticket | paper title"
  }
}
```

### Origin Types
| Origin | Description | Example |
|--------|-------------|---------|
| `architect` | Architect designed the solution | Breakdown of Blueprint |
| `po` | Product Owner requested feature | User story |
| `worker` | Worker proposed improvement | Refactor suggestion |
| `external` | External source (client, partner) | Client feedback |
| `thesis` | Novel idea/algorithm | New caching strategy |

---

## Thesis Tagging

### When to Tag as Thesis
- New algorithm or data structure
- Novel architecture pattern
- Original research or experiment
- First implementation of a concept in the codebase

### Thesis Format
```json
{
  "thesis": true,
  "thesis_summary": "Implemented braided stream scheduling for parallel task execution",
  "thesis_author": "@architect",
  "thesis_reference": "Based on internal research, no external source"
}
```

---

## THESIS_LOG.md Format

```markdown
### [YYYY-MM-DD] Thesis: {Title}
- **Author**: @username
- **Task**: #{TaskID}
- **Summary**: {One-line description}
- **Impact**: {How this changes the system}
- **Reference**: {Paper/Article/Meeting if applicable}
```

---

## When Attribution is Ambiguous

If the source is unclear:
1. Default to `origin: "worker"` (the implementer)
2. Add note: `"attribution_note": "Source unclear, defaulting to implementer"`
3. Flag for Architect review in next standup

---

## Integration with PROJECT_HISTORY.md

Every entry should include the Source field:
```markdown
- **Source**: @architect (Blueprint #42) | @po (User Story US-101) | Thesis
```
