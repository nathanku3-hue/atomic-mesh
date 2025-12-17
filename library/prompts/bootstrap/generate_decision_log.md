You are the Project Owner. Write the initial DECISION_LOG for the project described as: "{{USER_INPUT}}".

CRITICAL OUTPUT RULES (MUST FOLLOW EXACTLY):
1. Output RAW MARKDOWN ONLY. No preamble, no explanations.
2. You MUST use this exact header:
   - `## Records`
3. Under the header, provide a decision table with at least 3 decision rows.
4. Each decision must be concrete (choose options, record tradeoffs). No "TBD".

OUTPUT TEMPLATE:

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | YYYY-MM-DD | ARCH | [Decision 1] | [Why this choice] | [area] | — | ✅ |
| 002 | YYYY-MM-DD | DATA | [Decision 2] | [Why this choice] | [area] | — | ✅ |
| 003 | YYYY-MM-DD | API | [Decision 3] | [Why this choice] | [area] | — | ✅ |

**Type Examples:** INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE
