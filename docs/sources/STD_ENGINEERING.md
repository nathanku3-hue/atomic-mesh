# Standard Engineering Practices
*The baseline quality rules for all code. Tier B sources - implicit default for plumbing tasks.*

## [STD-SEC-01] No Hardcoded Secrets
**Text:** Never store API keys, passwords, or tokens in code. Use `os.getenv` or a secrets manager.

## [STD-CODE-01] Single Responsibility
**Text:** Functions should do one thing. If a function exceeds 50 lines, refactor.

## [STD-CODE-02] Descriptive Naming
**Text:** Variable and function names must clearly describe their purpose. Avoid abbreviations unless universally understood.

## [STD-ERR-01] Graceful Failure
**Text:** Never use bare `try/except`. Always catch specific exceptions and log the error context.

## [STD-ERR-02] Fail Fast
**Text:** Validate inputs at function boundaries. Return early on invalid state rather than nesting deeply.

## [STD-TEST-01] Test Coverage
**Text:** Every logic branch must have a corresponding test case.

## [STD-TEST-02] Test Independence
**Text:** Tests must not depend on execution order or shared mutable state.

## [STD-DOC-01] Self-Documenting Code
**Text:** Public methods must have docstrings. Complex logic must have inline comments explaining "Why", not "What".

## [STD-PERF-01] No Premature Optimization
**Text:** Write clear code first. Only optimize after profiling identifies actual bottlenecks.

## [STD-ARCH-01] Separation of Concerns
**Text:** Keep I/O, business logic, and presentation in separate layers. Functions should not mix database calls with formatting.
