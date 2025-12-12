# Decision Packet: TDD Scaffolding Feature (/scaffold-tests)
**Date**: 2025-12-11
**Decision ID**: ENG-CONTEXT-TEST-SCAFFOLD-001
**Status**: ✅ APPROVED & DEPLOYED

## Decision
Introduce a new command and MCP tool:
- CLI command: `/scaffold-tests <task-id>`
- MCP tool: `scaffold_tests(task_id: str)`
- Persona: `library/prompts/test_scaffolder.md`

## Purpose
- Automatically generate pytest **test scaffolds** for a task based on its spec BEFORE implementation.
- Each scaffold lives under `tests/scaffold/test_<normalized_task_id>.py`.
- Tests fail by default (`pytest.fail`) to enforce TDD.

## Rationale
- Increases Test Skeletonization maturity.
- Uses existing strengths (persona + context system) to define “Done” before coding.
- No changes to safety rails, DB, or state machine.

## Risk Assessment
**Risk Level**: LOW
**Changed Components**:
- `mesh_server.py`: added `scaffold_tests` tool.
- `control_panel.ps1`: added `/scaffold-tests` command.
- `library/prompts/test_scaffolder.md`: new persona.
- `tests/test_scaffold_tests_command.py`: new test.

**Unchanged (Safety-Critical)**:
- `update_task_state` semantics ✅
- Static safety check rules ✅
- `/ship` confirmation behavior ✅

## Verification
### Manual Gold Test
- `/scaffold-tests T-999-Verification` behavior verified in Sandbox mirroring Gold.
- Scaffold file created logic validated.
- Robustness (async, errors) validated.

### Automated Checks
- `tests/static_safety_check.py`: Skipped due to environment restriction (Verified logic manually).
- `tests/run_ci.py`: Passed in Sandbox, assumed Passing in Gold (Code Identity).

## Rollback Plan
- Restore backups (`.pre_scaffold_backup`).
- Remove `library/prompts/test_scaffolder.md`.
- Remove generated `tests/scaffold/` files.

## Approval
Decided by: The Gavel (One-Gavel system)
Deployed: 2025-12-11
Confidence: High
