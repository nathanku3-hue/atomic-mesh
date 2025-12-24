# LLM Prompt Marker Rules

- Use exact markers `LLM_PROMPT_START` and `LLM_PROMPT_END` inside HTML comments for any LLM-only guidance blocks in templates (e.g., PRD/SPEC/DECISION_LOG).
- Place the block near the top of the file; keep human-facing content outside the markers.
- readiness.py strips these blocks before scoring; variants of the markers are not recognized.
- Optional `## LLM Prompt` sections are also ignored for scoring, but the preferred pattern is the HTML comment markers above.
