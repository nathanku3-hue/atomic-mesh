# GIT WORKFLOW STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. Branch Naming

### Pattern
```
<type>/<ticket-id>-<short-description>
```

### Types
- `feature/` - New functionality
- `fix/` - Bug fixes
- `hotfix/` - Production emergency fixes
- `refactor/` - Code restructuring
- `docs/` - Documentation only
- `test/` - Test additions/fixes

### Examples
```
feature/PROJ-123-user-authentication
fix/PROJ-456-login-timeout
hotfix/critical-db-connection
```

---

## 2. Commit Messages

### Format
```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `style:` - Formatting, no code change
- `refactor:` - Code restructuring
- `test:` - Adding tests
- `chore:` - Maintenance

### Examples
```
feat(auth): add JWT refresh token rotation

Implements automatic token rotation on refresh to improve security.
Tokens are invalidated after single use.

Closes #123
```

```
fix(api): handle null user in preferences endpoint

- Added null check before accessing user properties
- Returns 401 if user not found

Fixes #456
```

---

## 3. Pull Request Guidelines

### Title
Use the same format as commit messages:
```
feat(auth): implement OAuth2 login
```

### Description Template
```markdown
## Summary
Brief description of changes.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe tests performed.

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Tests added/updated
- [ ] Documentation updated
```

---

## 4. Protected Branches

### Main/Master
- No direct commits
- Requires PR with at least 1 approval
- Requires passing CI checks
- Requires up-to-date branch

### Development
- Feature branches merge here first
- Can have less strict requirements

---

## 5. Merge Strategy

### Recommended: Squash and Merge
- Keeps main branch history clean
- One commit per feature/fix
- Preserves full history in PR

### When to use Rebase
- Only for syncing feature branches with main
- Never for shared branches

---

## 6. Release Tagging

### Semantic Versioning
```
v<major>.<minor>.<patch>
```

- **Major**: Breaking changes
- **Minor**: New features (backwards compatible)
- **Patch**: Bug fixes

### Examples
```
v1.0.0 - Initial release
v1.1.0 - Added new feature
v1.1.1 - Bug fix
v2.0.0 - Breaking API change
```
