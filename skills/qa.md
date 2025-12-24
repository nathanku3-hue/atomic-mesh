# Lane: QA

## MUST
- Verify all acceptance criteria from task
- Test edge cases and error scenarios
- Check for regressions in related features
- Validate across target browsers/devices
- Document test results with evidence

## MUST NOT
- Mark done without testing
- Skip mobile/responsive testing
- Ignore console errors/warnings
- Trust "it works on my machine"

## Test Categories
| Category | Check |
|----------|-------|
| Happy Path | Core functionality works |
| Edge Cases | Empty, null, max values |
| Error States | Invalid input, network failures |
| Regression | Related features still work |
| Performance | No obvious slowdowns |

## Acceptance Checks
- [ ] Criteria: All acceptance criteria verified
- [ ] Edge Cases: Tested empty/null/max inputs
- [ ] Errors: Error states handled gracefully
- [ ] Evidence: Screenshots/logs provided
