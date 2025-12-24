<!-- ATOMIC_MESH_TEMPLATE_STUB -->
## LLM Prompt (copy/paste into ChatGPT)
- Role: You are a senior engineer triaging the inbox. Be terse, factual, and bias to next actions.
- Input: Use only info in this chat/session and the Context Pack. If data is missing, add `TODO: <question>` and add `ASSUMPTION: <item>` if you must proceed.
- Output: Return markdown only; preserve all headings/sections/tables; do not add new sections or prose before the title.
- Style: Bullet/table-first; log question, hypothesis, next action, owner, due date, and links; tag `DECISION:`, `RISK:`, `OPEN QUESTION:` where relevant.
- Quick start: Copy from here to the end of the file into ChatGPT. Optionally paste recent notes into the Context Pack → Extra context.

### Context Pack
- Project: {{PROJECT_NAME}}
- Repo path: {{REPO_PATH}}
- Stage: INIT | DRAFT | ACCEPT | GO
- Constraints / non-negotiables: TODO:
- Snapshot signals / readiness: TODO:
- Extra context from user or links: TODO:

### Fill Rules (shared)
- Missing info → `TODO: <question>`; assumptions → `ASSUMPTION: <item>`; risks → `RISK: <item>`; decisions → `DECISION: <item>`; unknowns → `OPEN QUESTION: <item>`.
- Each entry needs a clear next action, owner, and due date or `TODO: set due`. Phrase next actions as testable outcomes.
- LLM Output Contract: respond with markdown only; keep headings intact; no additional sections.

### Template Quick Rules (shared)
- Keep bullets short; no fluff.
- If a field is unknown, enter `TODO:` instead of leaving blank.
- Prefer actionable phrasing; link to source notes when available.
- Use consistent tokens: `TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`. For experiment ideas, set Item Type = `EXPERIMENT`.

# INBOX (Temporary)

Drop clarifications, new decisions, and notes here.  
Next: run `/ingest` to merge into PRD/SPEC/DECISION_LOG, then this file will be cleared.

## Entries
| ID | Item Type | Question / Note | Hypothesis | Next Action | Owner | Due | Links |
|----|-----------|-----------------|------------|-------------|-------|-----|-------|
| 001 | OPEN QUESTION | {{question}} | {{hypothesis}} | {{next step}} | {{owner}} | {{date or TODO}} | {{link}} |
| SAMPLE-EXP | EXPERIMENT | Should onboarding tooltip run for new users? | Variant B reduces drop-off | Ship EXP-ONBOARD-01 to 10% new users; log exposure | PM/Eng | {{date}} | spec link |
