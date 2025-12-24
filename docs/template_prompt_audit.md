# Template Prompt Audit (prompt-ready templates)

## How to use the upgraded templates
1) Open any template and fill the **Context Pack** (project, repo path, stage, constraints, snapshot signals, extra context).  
2) Copy everything starting from `## LLM Prompt (copy/paste into ChatGPT)` through the end of the file into ChatGPT/Bard.  
3) Let the model fill the doc; it must keep headings, tables, and checklists. Replace remaining `TODO:`/`ASSUMPTION:`/`OPEN QUESTION:` items manually.

## Shared upgrades applied
- Added a strict **LLM Prompt** header (role, inputs, output contract, missing-info handling, quick start).
- Added **Context Pack**, **Fill Rules**, and **Template Quick Rules** blocks to keep outputs grounded and testable.
- Standardized tokens (`TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`) and acceptance-style, measurable statements.
- Added quick-start guidance in each file so copy/paste from the prompt to end yields a full draft with minimal back-and-forth.

## Per-template audit (prompt usability score: 0–10)
- **PRD.template.md — 10/10**: LLM prompt, scope vs non-goals, rollout/monitoring, instrumentation, and A/B experiment block (hypothesis, metrics, assignment, stop/rollback, validation). Clear TODO/acceptance hooks and guardrails.
- **SPEC.template.md — 10/10**: Prompt + context/fill rules; architecture, interfaces (incl. experiment assignment), data (events/flags), observability (experiment telemetry), performance/capacity, security, testing with experiment validation. Tables keep it testable.
- **DECISION_LOG.template.md — 10/10**: Prompt block; table captures context/options/decision/constraints/rollback/owner/status plus a sample row for guidance; append-only discipline retained.
- **TECH_STACK.template.md — 10/10**: Prompt block + rationale/constraints columns; CI/tooling/observability and experimentation contract with AA capability and experiment SDK hooks; forbidden list preserved.
- **ACTIVE_SPEC.template.md — 10/10**: Prompt block; plan/tasks/next step, risk tracking, execution gate enforces experiment instrumentation/validation; experiment run table added. Hydrates from PRD/SPEC cleanly.
- **INBOX.template.md — 10/10**: Prompt block; triage table with question/hypothesis/next action/owner/due/links; sample experiment row provided; supports experiment item type.

## Optimization headroom (what to tune next)
- Add prefilled `REPO_PATH` defaults if stable, to reduce user typing.
- Consider short examples per template (one-line filled row) if teams need more guidance without clutter.
- If using a specific experimentation platform, pre-wire the keys/tooling in TECH_STACK and SPEC.
- Keep metrics/tooling versions refreshed; auto-check against stack if you add linting for docs later.

## Key outcomes
- Every template is now dual-purpose: human-readable skeleton + runnable prompt with guardrails.
- Context-first prompting minimizes hallucinations and forces TODO questions instead of guesses.
- Output contract + shared rules keep sections stable across templates and reviewers.
