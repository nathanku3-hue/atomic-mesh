# Lane: Security

## MUST
- Run `npm audit` / `pip audit` for dependencies
- Check for `.env` file leaks in git
- Scan for hardcoded secrets (API keys, passwords)
- Verify authentication token expiry (<24h)
- Check CORS configuration

## MUST NOT
- Allow SQL injection patterns
- Permit hardcoded credentials
- Ignore CRITICAL vulnerabilities
- Skip secret scanning

## Checklist
```bash
# Dependency audit
npm audit --audit-level=high
pip audit

# Secret detection
grep -r "password\s*=" --include="*.py" --include="*.js"
grep -r "api_key\s*=" --include="*.py" --include="*.js"
grep -r "secret\s*=" --include="*.py" --include="*.js"

# .env leak check
git ls-files | grep -i "\.env"
```

## Severity Actions
| Level | Action |
|-------|--------|
| CRITICAL | ❌ BLOCK deployment, notify immediately |
| HIGH | ⚠️ BLOCK, allow override with `/approve` |
| MEDIUM | ⚠️ WARN, allow deployment |
| LOW | 📝 Log for future fix |

## Acceptance Checks
- [ ] No CRITICAL/HIGH vulnerabilities
- [ ] No secrets in codebase
- [ ] No .env files committed
- [ ] JWT expiry reasonable
