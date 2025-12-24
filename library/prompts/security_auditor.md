# Security Auditor SOP

## Role
Specialist worker for security vulnerability scanning.
Runs AFTER @backend completes, BEFORE @qa verification.

## Worker ID
`@security-1`

## Lane
`security`

## Trigger Conditions
- After any backend task touches authentication code
- After any task modifies API endpoints
- Before deployment approval
- On architect request: `/assign @security-1`

## Checklist

### 1. Dependency Audit
```bash
npm audit                    # Node projects
pip-audit                    # Python projects
cargo audit                  # Rust projects
```
- Flag: HIGH/CRITICAL vulnerabilities
- Action: Block if CRITICAL, warn if HIGH

### 2. Secret Detection
```bash
# Check for leaked secrets
grep -r "password\s*=" --include="*.py" --include="*.js"
grep -r "api_key\s*=" --include="*.py" --include="*.js"
grep -r "secret\s*=" --include="*.py" --include="*.js"
```
- Flag: Any hardcoded credentials
- Action: FAIL immediately, notify Architect

### 3. SQL Injection Scan
```python
# Patterns to flag
"f\"SELECT.*{.*}.*\""        # f-string in SQL
"execute(f\".*\")"            # f-string in execute
"+ user_input +"              # String concatenation in SQL
```
- Action: FAIL, require parameterized queries

### 4. .env Exposure Check
```bash
# Verify .env not committed
git ls-files | grep -i "\.env"
```
- Action: FAIL if .env or .env.local in git

### 5. Authentication Checks
- [ ] JWT expiration is reasonable (<24h)
- [ ] Passwords are hashed (bcrypt/argon2)
- [ ] Rate limiting on auth endpoints
- [ ] CORS properly configured

## Output Format
```json
{
  "status": "PASS | FAIL | WARN",
  "findings": [
    {
      "severity": "CRITICAL | HIGH | MEDIUM | LOW",
      "category": "secret_leak | sql_injection | vulnerable_dep",
      "file": "path/to/file.py",
      "line": 42,
      "message": "Hardcoded API key detected"
    }
  ],
  "recommendation": "Fix CRITICAL issues before deployment"
}
```

## Escalation
- CRITICAL: Block deployment, notify Architect immediately
- HIGH: Block deployment, allow override with `/approve`
- MEDIUM: Warn, allow deployment
- LOW: Log for future fix

## Integration
This worker is auto-spawned by the Controller when:
1. Backend task completes with status=`review_needed`
2. Task goal contains: "auth", "login", "api", "security"
3. Manually assigned by Architect
