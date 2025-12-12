# Domain Rules (Constitution)

This file defines the **inviolable constraints** that the Product Owner must enforce during ingestion.
Any raw input that violates these rules will be **REJECTED**.

---

## Architecture Rules

1. **TypeScript/JavaScript Only** - No other backend languages unless explicitly approved
2. **No Auto-Retry Logic** - All retry decisions must be human-initiated
3. **Explicit Error Handling** - Silent failures are forbidden

## Security Rules

4. **No Raw SQL** - All database queries must use parameterized queries or ORM
5. **No Secrets in Code** - All credentials via environment variables
6. **Input Validation Required** - All user inputs must be validated before processing

## Process Rules

7. **One Feature Per Task** - Atomic units of work only
8. **Tests Required** - No feature ships without corresponding tests
9. **Documentation Mandatory** - API changes require updated docs

## Performance Rules

10. **Pagination Required** - No unbounded queries returning all records
11. **Timeout Limits** - All external calls must have explicit timeouts

---

*Last Updated: 2024-12-07*
*Version: 1.0*
