# DOMAIN CONSTITUTION (Non-Negotiable)

> **This file defines the "Closed World" for this project.**
> Violating any rule in this document is a CRITICAL FAILURE.

---

## 1. The Closed World Assumption

You are strictly prohibited from using external knowledge not found in the following source files:
- `docs/CODE_BOOK.md` - The authoritative source of business logic
- `docs/TECH_STACK.md` - Approved technologies and libraries
- `docs/ACTIVE_SPEC.md` - Current implementation requirements

### Behavior When Knowledge is Missing

If a logic path is not defined in the above documents:
1. **DO NOT** improvise or use "common sense"
2. **DO NOT** infer from similar patterns in other domains
3. **MUST** raise an explicit error: `"Undefined Domain State: [description]"`
4. **MUST** log for human review

---

## 2. The Citation Protocol

Every core logic function MUST include a Docstring citing the specific Section of CODE_BOOK.md it implements.

### Required Format

```python
def calculate_penalty(days_late: int, amount: float) -> float:
    """
    @citation 4.2.3
    
    Implements: Section 4.2.3 - Late Payment Penalties
    Logic: 1.5% per day, capped at 15% maximum
    
    Edge Cases Defined:
    - days_late = 0 → No penalty
    - days_late > 10 → Cap at 15%
    """
    ...
```

### Verification

The system will:
1. Parse all `@citation` tags
2. Verify the cited section exists in CODE_BOOK.md
3. REJECT code with missing or invalid citations

---

## 3. Forbidden Patterns (Anti-Patterns)

### 3.1 No "User Convenience" Features

Do NOT add features that make the system "nicer" unless explicitly requested:
- ❌ Auto-retry mechanisms
- ❌ Friendly error messages (unless spec defines exact text)
- ❌ Default values for missing inputs
- ❌ "Smart" input parsing or normalization

### 3.2 No Performance Optimization

Do NOT optimize for performance if it sacrifices accuracy:
- ❌ Rounding for speed
- ❌ Caching that could serve stale data
- ❌ Approximations instead of exact calculations

### 3.3 No Edge Case Invention

Do NOT handle edge cases that CODE_BOOK.md defines as "Impossible":
- If the book says "Amount is always positive" → No negative handling
- If the book says "Date is always valid" → No date validation

---

## 4. Approved Libraries (Whitelist)

See `docs/TECH_STACK.md` for the complete list.

The following are ALWAYS approved (Python standard library):
- `os`, `sys`, `json`, `typing`, `datetime`, `time`, `re`
- `math`, `decimal`, `collections`, `pathlib`
- `functools`, `itertools`, `enum`, `dataclasses`
- `csv`, `hashlib`, `uuid`, `logging`

Any library NOT in TECH_STACK.md or the above list is **FORBIDDEN**.

To request a new library:
1. Add it to TECH_STACK.md with justification
2. Get explicit approval
3. Document why alternatives are insufficient

---

## 5. Traceability Requirements

For every implementation:
1. **Decision** must map to **Citation**
2. All mappings logged to `audit/TRACEABILITY_MATRIX.csv`
3. Violations logged to `docs/incidents/COMPLIANCE_REPORT.md`

This enables:
- Auditor review of all decisions
- Rollback to specific rule interpretations
- Evidence for regulatory compliance

---

## 6. Incident Handling

When a compliance violation is detected:

| Severity | Response |
|----------|----------|
| **CRITICAL** | Block deployment, immediate escalation |
| **HIGH** | Block merge, require fix before proceed |
| **MEDIUM** | Warning, proceed with logging |
| **LOW** | Informational, document for review |

---

## 7. Domain-Specific Rules

*Add your project-specific constraints below:*

### 7.1 [Your Domain Rule Here]
<!-- 
Example for Tax Software:
- All monetary calculations use Decimal, not float
- All dates in ISO 8601 format
- Fiscal year boundaries: April 1 - March 31
-->

### 7.2 [Your Domain Rule Here]

---

**Last Updated:** 2024-12-06  
**Version:** 1.0.0  
**Enforced By:** Atomic Mesh v9.0 Compliance Suite
