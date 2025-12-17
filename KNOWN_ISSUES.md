# Known Issues - v18.0

## Deferred Test Failures (7 total)

These tests are failing but do not block v18.0 release. They test extraction patterns
and template content that are outside the core accept-plan + scheduler scope.

### test_plan_quality.py (3 failures)

| Test | Issue | Impact |
|------|-------|--------|
| `test_extracts_table_format` | API endpoint extraction from markdown tables | Extraction only, no runtime impact |
| `test_extracts_function_definitions` | Function definition extraction patterns | Extraction only, no runtime impact |
| `test_extracts_code_block_format` | Data entity extraction from code blocks | Extraction only, no runtime impact |

**Root cause**: Extraction regex patterns need refinement for edge cases.
**Scope**: Plan generation quality, not accept/scheduler integrity.
**Fix timeline**: v18.1

### test_template_anchors.py (4 failures)

| Test | Issue | Impact |
|------|-------|--------|
| `test_prd_template_anchors` | Template story extraction missing 'desc' key | Template content format |
| `test_decision_log_template_anchors` | No non-INIT decisions in template | Template content |
| `test_templates_pass_sufficiency_gate` | Cascading from above failures | Template validation |
| `test_templates_produce_quality_plan` | Cascading from above failures | Template validation |

**Root cause**: Template files need content updates to match extraction expectations.
**Scope**: Template validation only, no runtime impact on accept/scheduler.
**Fix timeline**: v18.1

---

## v18.0 Test Summary

| Category | Passed | Failed | Notes |
|----------|--------|--------|-------|
| SQLite accept-plan | 17 | 0 | Core functionality |
| Braided scheduler | 13 | 0 | Core functionality |
| Extraction/templates | - | 7 | Deferred to v18.1 |
| **Total** | **270** | **7** | |

## What v18.0 Delivers

1. SQLite as single source of truth for tasks
2. Idempotent plan acceptance (source_plan_hash, task_signature)
3. Lane normalization and priority parsing (P:URGENT=0, P:HIGH=5)
4. Execution class classification (exclusive/parallel_safe/additive)
5. Braided stream scheduler with round-robin across lanes
6. Priority preemption (URGENT/HIGH bypass rotation)
7. Atomic task claiming (prevents double-claim)
8. Dependency gating with unknown-dep blocking
