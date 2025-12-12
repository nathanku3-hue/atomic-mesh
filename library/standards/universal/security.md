# UNIVERSAL SECURITY STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. Secrets Management

### Rules
- **NEVER** commit secrets to git
- Use `.env` files for all credentials
- Add `.env` to `.gitignore` immediately
- Use `.env.example` as a template (no real values)

### Implementation
```python
# Python
import os
secret = os.getenv("API_KEY")
```

```typescript
// TypeScript/Node
const secret = process.env.API_KEY;
```

### Tripwires (Auto-Reject if Found)
- `sk-...` (OpenAI keys)
- `AKIA...` (AWS keys)
- `postgres://...` with passwords
- `mongodb+srv://...` with passwords
- Hardcoded JWT secrets

---

## 2. Input Validation

### Rules
- ALL API inputs must be validated before processing
- Use schema validation, not manual checks
- Reject invalid input with 400, not 500

### Implementation
```python
# Python - Use Pydantic
from pydantic import BaseModel, validator

class UserInput(BaseModel):
    email: str
    age: int
    
    @validator('age')
    def age_must_be_positive(cls, v):
        if v < 0:
            raise ValueError('must be positive')
        return v
```

```typescript
// TypeScript - Use Zod
import { z } from 'zod';

const UserSchema = z.object({
  email: z.string().email(),
  age: z.number().positive()
});
```

---

## 3. SQL Injection Prevention

### Rules
- **NEVER** concatenate user input into SQL strings
- Always use parameterized queries or ORM

### Forbidden Pattern
```python
# ❌ NEVER DO THIS
query = f"SELECT * FROM users WHERE id = {user_id}"
```

### Correct Pattern
```python
# ✅ Python - Parameterized
cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
```

```typescript
// ✅ TypeScript - Prisma ORM
const user = await prisma.user.findUnique({ where: { id: userId } });
```

---

## 4. Authentication & Password Handling

### Password Rules
- Hash with `bcrypt` (min 12 rounds) or `Argon2`
- **NEVER** use MD5 or SHA1 for passwords
- MD5 is acceptable ONLY for checksums/cache keys

### Implementation
```python
# Python
import bcrypt
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt(12))
```

```typescript
// TypeScript
import bcrypt from 'bcrypt';
const hashed = await bcrypt.hash(password, 12);
```

### Session Rules
- Use secure, httpOnly cookies for session tokens
- Set `SameSite=Strict` or `SameSite=Lax`
- JWT tokens should expire within 24 hours
- Refresh tokens should be rotated on use

---

## 5. Authorization

### Rules
- Check permissions on EVERY protected endpoint
- Use middleware for common auth checks
- Never trust client-provided user IDs

### Pattern
```typescript
// ✅ Correct - Get user from session
const userId = session.user.id;

// ❌ Wrong - Trust client input
const userId = req.body.userId;
```

---

## 6. Error Handling

### Rules
- Never expose stack traces to clients in production
- Log detailed errors server-side
- Return generic error messages to clients

### Implementation
```python
# Python
try:
    result = dangerous_operation()
except Exception as e:
    logger.error(f"Operation failed: {e}")
    raise HTTPException(status_code=500, detail="An error occurred")
```

---

## 7. Rate Limiting

### Rules
- Apply rate limits to all public endpoints
- Stricter limits on auth endpoints (login, signup)
- Log rate limit violations

### Recommended Limits
- General API: 100 req/min
- Auth endpoints: 10 req/min
- Password reset: 3 req/hour

---

## 8. CORS Configuration

### Rules
- Never use `Access-Control-Allow-Origin: *` in production
- Whitelist specific origins
- Only allow necessary methods and headers

---

## Audit Checklist

Before approving any code:
- [ ] No hardcoded secrets
- [ ] All inputs validated
- [ ] SQL queries parameterized
- [ ] Passwords hashed with bcrypt/Argon2
- [ ] Auth checks on protected routes
- [ ] No stack traces in client responses
