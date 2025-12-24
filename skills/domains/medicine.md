# Domain: MEDICINE
# Purpose: HIPAA Compliance, Patient Safety, and Data Integrity

## DIRECTIVE
This system handles Protected Health Information (PHI). "Do No Harm" applies to code. Privacy is paramount.

## MUST (Absolute Rules)
- [MED-01] **PHI Redaction** -> (Rationale: HIPAA Privacy Rule) -> (Code Implication: Never log Patient IDs or Names. Use masked hashes.)
- [MED-02] **Access Controls** -> (Rationale: Minimum Necessary) -> (Code Implication: Explicit permission checks `can_view_patient` on EVERY endpoint.)
- [MED-03] **Data Retention** -> (Rationale: Medical Record Laws) -> (Code Implication: Do not purge records before 7 years.)
- [MED-04] **Alerting** -> (Rationale: Patient Safety) -> (Code Implication: Critical system failures must trigger immediate pager duty.)

## AVOID
- [MED-AV-01] **Caching PHI** -> (Rationale: Leakage Risk) -> (Code Implication: `Cache-Control: no-store` on all PHI endpoints.)
- [MED-AV-02] **Implicit Consent** -> (Rationale: Ethics) -> (Code Implication: Require explicit boolean `has_consented` for data sharing.)

## OUTPUT EXPECTATIONS
All PHI handling functions must be annotated with `@requires_compliance("HIPAA")`.
