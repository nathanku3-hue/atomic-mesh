# Lane: Backend

## MUST
- Use parameterized queries (NEVER string concatenation)
- Return consistent error response format
- Log errors with context (request ID, user ID)
- Validate all request inputs
- Use environment variables for config

## MUST NOT
- Store secrets in code
- Return stack traces to clients
- Use raw SQL without parameterization
- Create functions > 50 lines
- Ignore connection pooling

## Patterns
```python
# ✅ Good: Parameterized query
cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))

# ❌ Bad: String interpolation
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")  # SQL INJECTION!

# ✅ Good: Error response
return {"error": "Not found", "code": "USER_NOT_FOUND"}, 404

# ❌ Bad: Exposing internals
return {"error": str(traceback.format_exc())}, 500  # SECURITY RISK!
```

## Acceptance Checks
- [ ] Security: No SQL injection vulnerabilities
- [ ] Validation: All inputs validated/sanitized
- [ ] Errors: Consistent error response format
- [ ] Logging: Errors logged with context
