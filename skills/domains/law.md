# Domain: LAW
# Purpose: Legal Compliance, Audit Trails, and Privacy

## DIRECTIVE
This system handles sensitive legal data. "Code is Evidence." Every action must be logged, traceable, and immutable.

## MUST (Absolute Rules)
- [LAW-01] **Immutable Usage** -> (Rationale: Chain of Custody) -> (Code Implication: Use `INSERT` only for records. Never `UPDATE` critical fields.)
- [LAW-02] **Soft Deletes** -> (Rationale: Evidence Preservation) -> (Code Implication: Use `is_deleted` flag or move to archive table. NEVER `DELETE FROM`.)
- [LAW-03] **Audit Trail** -> (Rationale: Accountability) -> (Code Implication: Logs must include `who`, `what`, `when`, `why` (reason code).)
- [LAW-04] **Privacy** -> (Rationale: Attorney-Client Privilege) -> (Code Implication: Encrypt all PII/Case Data at rest.)

## AVOID
- [LAW-AV-01] **Logs in Console** -> (Rationale: Leakage) -> (Code Implication: No `console.log` of case data.)
- [LAW-AV-02] **Hardcoded Actors** -> (Rationale: Bias) -> (Code Implication: No hardcoded user roles in logic.)

## OUTPUT EXPECTATIONS
Code must include comments citing the Rule ID (e.g., `// LAW-01: Using append-only log`).
