# CODE REVIEW STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. Review Checklist

### Functionality
- [ ] Code does what the ticket/PR describes
- [ ] Edge cases are handled
- [ ] Error handling is appropriate
- [ ] No obvious bugs or logic errors

### Security (Refer to security.md)
- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] SQL injection prevented
- [ ] Auth/authz properly implemented

### Code Quality
- [ ] Follows project style guidelines
- [ ] No code duplication (DRY)
- [ ] Functions are focused (Single Responsibility)
- [ ] Variable/function names are descriptive
- [ ] No commented-out code

### Performance
- [ ] No obvious N+1 queries
- [ ] Large data sets are paginated
- [ ] Expensive operations are cached where appropriate
- [ ] No blocking operations in async code

### Testing
- [ ] Unit tests added for new logic
- [ ] Edge cases tested
- [ ] Tests are meaningful (not just for coverage)

### Documentation
- [ ] Complex logic has comments
- [ ] Public APIs have docstrings
- [ ] README updated if needed

---

## 2. Review Priority by Task Type

### CRITICAL Tasks
1. **Security First**: Check security.md compliance
2. **Auth Flows**: Verify token handling, session management
3. **Data Mutations**: Verify validation and authorization
4. **External APIs**: Check for rate limiting, error handling

### Standard Tasks
1. **Functionality**: Does it work?
2. **Code Quality**: Is it clean?
3. **Testing**: Is it tested?

### RELAXED Tasks (Exploratory/POC)
1. **Functionality Only**: Does it demonstrate the concept?
2. Skip style/test requirements

---

## 3. Review Comments

### Blocking (Must Fix)
```
🔴 BLOCKING: SQL injection vulnerability - must use parameterized query
```

### Suggestion (Should Fix)
```
🟡 SUGGESTION: Consider extracting this into a helper function for reuse
```

### Nitpick (Optional)
```
🟢 NITPICK: Variable name could be more descriptive (userInfo -> authenticatedUser)
```

### Question (Need Clarification)
```
❓ QUESTION: Why is this check needed? Could you add a comment explaining?
```

### Praise
```
👍 Nice use of the factory pattern here!
```

---

## 4. Review Response Guidelines

### For Authors
- Respond to every comment
- Explain decisions, don't just "fixed"
- Push fixes in separate commits for easy re-review
- Request re-review after addressing all comments

### For Reviewers
- Be constructive, not destructive
- Explain why, not just what
- Offer alternatives when criticizing
- Approve when issues are minor

---

## 5. Auto-Reject Triggers

Immediately request changes if you see:

### Security
- Hardcoded credentials
- SQL string concatenation
- Missing auth checks on protected routes
- MD5/SHA1 used for passwords

### Quality
- Console.log / print() in production code
- Ignored errors (empty catch blocks)
- Magic numbers without explanation
- Copy-pasted code blocks

### Process
- Missing tests for business logic
- PR too large (>500 lines, should be split)
- Merge conflicts present
