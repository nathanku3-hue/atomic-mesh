# PYTHON BACKEND ARCHITECTURE STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. Project Structure

### Recommended Layout
```
/src
  /app                   # Application entry, config
    __init__.py
    main.py              # FastAPI app instance
    config.py            # Settings, env loading
    
  /api                   # API Layer (Routers)
    /v1
      /auth
        router.py
        schemas.py
      /users
        router.py
        schemas.py
        
  /services              # Business Logic Layer
    auth_service.py
    user_service.py
    
  /repositories          # Data Access Layer
    user_repository.py
    
  /models                # Database Models
    user.py
    
  /core                  # Shared Utilities
    security.py
    exceptions.py
    dependencies.py

/tests
  /unit
  /integration
```

---

## 2. Layer Responsibilities

### API Layer (Routers)
- HTTP request/response handling only
- Input validation via Pydantic schemas
- No business logic
- Calls services

```python
# ✅ Correct
@router.post("/users")
async def create_user(user: UserCreate, service: UserService = Depends()):
    return await service.create(user)
```

### Service Layer
- Business logic
- Orchestrates repositories
- Transaction management
- No HTTP concepts

```python
# ✅ Correct
class UserService:
    def __init__(self, repo: UserRepository = Depends()):
        self.repo = repo
    
    async def create(self, data: UserCreate) -> User:
        # Business logic here
        return await self.repo.insert(data)
```

### Repository Layer
- Database operations only
- No business logic
- Raw queries or ORM calls

---

## 3. Dependency Injection

### Rules
- Use FastAPI's `Depends()` for all dependencies
- Never instantiate services inside routers
- Use abstract base classes for testing

```python
# ✅ Correct
def get_user_service(repo: UserRepository = Depends()) -> UserService:
    return UserService(repo)

@router.get("/users/{id}")
async def get_user(id: int, service: UserService = Depends(get_user_service)):
    return await service.get_by_id(id)
```

---

## 4. Type Hints

### Rules
- ALL functions must have type hints
- Use `Optional[T]` for nullable parameters
- Use `list[T]` (Python 3.9+) or `List[T]`

```python
# ✅ Correct
async def get_user(user_id: int) -> Optional[User]:
    ...

def process_items(items: list[Item]) -> dict[str, int]:
    ...
```

---

## 5. Error Handling

### Custom Exceptions
```python
# /core/exceptions.py
class AppException(Exception):
    def __init__(self, message: str, code: str, status: int = 400):
        self.message = message
        self.code = code
        self.status = status

class NotFoundError(AppException):
    def __init__(self, resource: str):
        super().__init__(f"{resource} not found", "NOT_FOUND", 404)

class ValidationError(AppException):
    def __init__(self, message: str):
        super().__init__(message, "VALIDATION_ERROR", 400)
```

### Exception Handler
```python
@app.exception_handler(AppException)
async def app_exception_handler(request, exc: AppException):
    return JSONResponse(
        status_code=exc.status,
        content={"error": exc.code, "message": exc.message}
    )
```

---

## 6. Logging

### Rules
- Use `logging` module, never `print()`
- Configure structured logging (JSON in production)
- Include correlation IDs for request tracing

```python
import logging
logger = logging.getLogger(__name__)

# ✅ Correct
logger.info("User created", extra={"user_id": user.id})

# ❌ Wrong
print(f"User created: {user.id}")
```

---

## 7. Async/Await

### Rules
- Use `async def` for I/O-bound operations
- Use thread pool for CPU-bound operations
- Never mix sync DB calls in async routes

```python
# ✅ Correct - Async DB call
async def get_users():
    return await database.fetch_all(query)

# ✅ Correct - CPU-bound in thread pool
import asyncio
from concurrent.futures import ThreadPoolExecutor

async def process_image(data: bytes):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, cpu_bound_process, data)
```
