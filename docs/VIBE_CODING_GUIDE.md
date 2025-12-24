# Vibe Coding System - Complete Implementation Guide

## Overview
The Vibe Coding system is now production-ready with guaranteed task delivery. This document provides a complete reference for the Architect-Worker contract.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     VIBE CODING SYSTEM                      │
│                         (v24.2)                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
         ┌────────────────────────────────────────┐
         │        ARCHITECT (Brain)               │
         │  - Supervision Gate (Risk Assessment)  │
         │  - Task Planning & Dispatch            │
         │  - Worker Monitoring                   │
         │  - Review & Approval                   │
         └────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
         ┌──────────────────┐  ┌──────────────────┐
         │  BACKEND WORKER  │  │ FRONTEND WORKER  │
         │  - Quality Veto  │  │  - UI Standards  │
         │  - Sandbox Mode  │  │  - A11y Checks   │
         │  - Test-First    │  │  - Responsive    │
         └──────────────────┘  └──────────────────┘
                    │                   │
                    └─────────┬─────────┘
                              ▼
                    ┌──────────────────┐
                    │   SQLite DB      │
                    │  - tasks         │
                    │  - task_messages │
                    │  - decisions     │
                    └──────────────────┘
```

---

## Artifact Inventory

| Artifact | Location | Purpose |
|----------|----------|---------|
| **Architect SOP** | `library/prompts/architect_sop.md` | Brain system prompt with supervision gate |
| **Backend Worker SOP** | `library/prompts/backend_worker_sop.md` | Worker system prompt with quality veto |
| **Brain SOP** | `library/prompts/brain_sop.md` | Orchestrator monitoring guide (v24.2) |
| **Worker SOP** | `library/prompts/worker.md` | Worker execution guide (v24.1) |
| **Schema Migration** | `migrations/v24_1_schema_migration.sql` | Database setup script |

---

## Decision Matrix (Architect)

### Supervision Gate
| Complexity | Risk | Mode | Action |
|------------|------|------|--------|
| Low (UI tweak) | Low (Patch) | **AUTO-DISPATCH** | Create task immediately |
| High (Refactor) | Low (Feature) | **PLANNING** | Output JSON → Wait for "Go" |
| Any | High (Auth/Schema) | **STRICT** | Output JSON → Assign @audit first |

### High Risk Definition
Tasks involving:
- **Core Logic**: Auth, Payments, Sessions, Data Deletion
- **Schema**: Database migrations, table alterations
- **Architecture**: New infrastructure, significant refactoring
- **Release**: Production deployment, stable branch changes

---

## Worker Execution Loop

### Standard Flow
```
1. claim_task(task_id, worker_id) → Get atomic lease
2. Read context_files
3. Quality Gate: Veto if instruction forces bad pattern
4. Test-First: Run tests (expect red)
5. Implementation: Write clean code
6. Verification: Run acceptance_checks
7. submit_for_review_with_evidence() → Include test results
```

### Critical Triggers

#### Quality Veto
**When:** Instruction forces tech debt or suboptimal pattern  
**Action:** `ask_clarification()` with proposed alternative

#### Blocker
**When:** Missing dependency or file context  
**Action:** `ask_clarification()` - do not mock or guess

#### Failure
**When:** Test command fails  
**Action:** Fix code, not tests (unless instruction says test is wrong)

---

## Tool Reference (v24.2)

### Worker Tools
| Tool | Purpose | Example |
|------|---------|---------|
| `claim_task` | Atomic claim with lease | `claim_task(42, "@backend", 300)` |
| `renew_lease` | Extend lease | `renew_lease(42, "@backend", 300)` |
| `ask_clarification` | Block on question | `ask_clarification(42, "Which OAuth?", "@backend")` |
| `check_task_status` | Poll for updates | `check_task_status(42)` |
| `submit_for_review` | Submit work | `submit_for_review(42, "Done", "src/auth.ts", "@backend")` |
| `submit_for_review_with_evidence` | Submit with proof | Includes test_cmd, test_result, git_sha |
| `get_task_history` | View conversation | `get_task_history(42, limit=20)` |

### Brain Tools
| Tool | Purpose | Example |
|------|---------|---------|
| `respond_to_blocker` | Unblock worker | `respond_to_blocker(42, "Use Auth0")` |
| `approve_work` | Complete task | `approve_work(42, "LGTM")` |
| `reject_work` | Reject with feedback | `reject_work(42, "Missing tests")` |

### Admin Tools
| Tool | Purpose | Example |
|------|---------|---------|
| `requeue_task` | Reset stuck task | `requeue_task(42, "Worker crashed")` |
| `force_unblock` | Override blocked | `force_unblock(42, "Admin override")` |
| `cancel_task` | Cancel task | `cancel_task(42, "Feature cut")` |
| `sweep_stale_leases` | Batch recovery | `sweep_stale_leases(max_stale_seconds=600)` |

---

## Database Schema (v24.1)

### Core Tables

#### tasks
```sql
- id, type, desc, status, worker_id
- lease_id, lease_expires_at (ownership)
- attempt_count (rejection tracking)
- blocker_msg, manager_feedback (communication)
- worker_output (evidence)
```

#### task_messages
```sql
- id, task_id, role, msg_type, content, created_at
- Stores full conversation history
- Indexed on (task_id, created_at)
```

#### decisions
```sql
- id, task_id, priority, question, status, answer
- Human-in-the-loop for high-risk approvals
- Indexed on (status, priority, created_at)
```

---

## Operational Workflows

### 1. Simple Task (Auto-Dispatch)
```
User: "Fix the typo in login button"
Architect: [Assesses: Low complexity, Low risk]
          → create_task(@frontend, context=[LoginButton.tsx])
Worker: claim_task() → fix → submit_for_review()
Brain: approve_work()
```

### 2. Complex Task (Planning Mode)
```
User: "Add OAuth login"
Architect: [Assesses: High complexity, High risk]
          → Output JSON plan with assumptions
User: "Go"
Architect: create_task(@backend, @qa)
Worker: claim_task() → ask_clarification("Which provider?")
Brain: respond_to_blocker("Use Auth0")
Worker: implement → submit_for_review_with_evidence()
Brain: approve_work()
```

### 3. Quality Veto
```
Worker: [Reads instruction: "Add auth check in every controller"]
Worker: [Quality Gate: This violates DRY, should be middleware]
Worker: ask_clarification("Instruction forces duplication...")
Brain: respond_to_blocker("Approved. Add to context_files: middleware.ts")
Worker: implement clean solution → submit
```

### 4. Rejection Cycle
```
Worker: submit_for_review()
Brain: reject_work("Missing error handling")
Worker: [attempt_count = 1] → fix → resubmit
Brain: reject_work("Still missing edge cases")
Worker: [attempt_count = 2] → fix → resubmit
Brain: reject_work("Needs refactor")
Worker: [attempt_count = 3 → ESCALATED to decisions table]
Human: Reviews → Provides guidance
```

---

## Quality Standards

### Code Quality Checklist
- [ ] All `acceptance_checks` pass
- [ ] No files modified outside `context_files`
- [ ] No new dependencies (unless allowed)
- [ ] Follows project style guide
- [ ] All inputs validated
- [ ] Error handling implemented
- [ ] Type safety enforced
- [ ] Performance optimized
- [ ] Tests written/updated
- [ ] Documentation updated

### Evidence Requirements (High Risk)
- [ ] Test command + result
- [ ] Git commit SHA
- [ ] Files changed list
- [ ] Code coverage metric
- [ ] Performance benchmark (if applicable)

---

## Testing

### Test Coverage
- **Core Workflow**: 9 tests (claim, ask, respond, submit, approve)
- **Edge Cases**: 14 tests (rejection, escalation, concurrency, stale leases)
- **Scheduler Regression**: 26 tests
- **Total**: 49 passing tests

### Running Tests
```bash
# All Worker-Brain tests
pytest tests/test_worker_brain_comm.py tests/test_worker_brain_edge_cases.py -v

# With scheduler regression
pytest tests/test_worker_brain*.py tests/test_braided_scheduler.py -v

# Quick smoke test
pytest tests/test_worker_brain_comm.py::TestFullWorkflow -v
```

---

## Deployment Checklist

### Pre-Production
- [ ] Run full test suite (49 tests)
- [ ] Execute schema migration (`v24_1_schema_migration.sql`)
- [ ] Verify all indexes created
- [ ] Backup existing database
- [ ] Test stale lease sweeper
- [ ] Verify decision queue integration

### Production
- [ ] Deploy with zero-downtime migration
- [ ] Monitor lease expiry rates
- [ ] Set up sweep_stale_leases() cron (every 5 min)
- [ ] Configure MAX_REJECTION_ATTEMPTS (default: 3)
- [ ] Enable audit logging for admin tools
- [ ] Set up alerts for escalated tasks

### Post-Deployment
- [ ] Verify no orphaned tasks
- [ ] Check message log growth rate
- [ ] Monitor rejection/escalation rates
- [ ] Review quality veto frequency
- [ ] Audit decision queue backlog

---

## Troubleshooting

### Common Issues

#### Workers Not Claiming Tasks
- Check `lease_expires_at` - may be stale
- Run `sweep_stale_leases()`
- Verify worker_id matches

#### Tasks Stuck in Blocked
- Query `task_messages` for blocker_msg
- Check if Brain is monitoring blocked queue
- Use `force_unblock()` if needed

#### High Rejection Rate
- Review `attempt_count` distribution
- Check if acceptance_checks are too strict
- Audit quality veto frequency
- Review Architect assumptions

#### Escalation Queue Growing
- Check MAX_REJECTION_ATTEMPTS setting
- Review decision queue priority
- Ensure human review process active

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v24.0 | 2024-12-24 | Initial Worker-Brain communication |
| v24.1 | 2024-12-24 | Added leases, ownership, message log |
| v24.2 | 2024-12-24 | Complete system: approve/reject, evidence, admin tools |
| v1.0 | 2024-12-24 | Vibe Coding Artifact Pack release |

---

## References

- **Implementation**: `mesh_server.py` (lines 1114-2046)
- **Tests**: `tests/test_worker_brain_comm.py`, `tests/test_worker_brain_edge_cases.py`
- **SOPs**: `library/prompts/` directory
- **Migration**: `migrations/v24_1_schema_migration.sql`

---

_Vibe Coding System - Production Ready v1.0_
_Last Updated: 2024-12-24_
