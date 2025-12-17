<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Operations Manual (Runbook)

## Quick Start
- **Init:** `{{RUN_CMD}} /init`
- **Plan:** `{{RUN_CMD}} /plan`
- **Work:** `{{RUN_CMD}} /work`

## Triage
- **Logs:** `logs/debug.log` and `logs/decisions.log` (local-only, git-ignored)
- **Health:** Run `{{RUN_CMD}} /ops`

## Release Process
1. Run `/simplify` on pending tasks.
2. Run `/verify` for high-risk items.
3. Run `/ship --confirm`.
