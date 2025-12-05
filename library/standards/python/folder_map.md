# PYTHON FOLDER STRUCTURE STANDARD
## Atomic Mesh Central Library v1.0

---

## 1. Golden Structure (FastAPI)

```
project-root/
├── src/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py           # App instance, middleware
│   │   └── config.py         # Settings from env
│   │
│   ├── api/
│   │   ├── __init__.py
│   │   └── v1/
│   │       ├── __init__.py
│   │       ├── router.py     # Main router aggregating all
│   │       ├── auth/
│   │       │   ├── router.py
│   │       │   └── schemas.py
│   │       └── users/
│   │           ├── router.py
│   │           └── schemas.py
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── auth_service.py
│   │   └── user_service.py
│   │
│   ├── repositories/
│   │   ├── __init__.py
│   │   └── user_repository.py
│   │
│   ├── models/
│   │   ├── __init__.py
│   │   └── user.py
│   │
│   └── core/
│       ├── __init__.py
│       ├── security.py
│       ├── exceptions.py
│       └── dependencies.py
│
├── tests/
│   ├── __init__.py
│   ├── conftest.py           # Fixtures
│   ├── unit/
│   │   └── test_user_service.py
│   └── integration/
│       └── test_user_api.py
│
├── scripts/
│   ├── seed_db.py
│   └── migrate.py
│
├── alembic/                   # DB migrations (if using)
│   └── versions/
│
├── docs/
│   └── api.md
│
├── .env.example
├── .gitignore
├── pyproject.toml
├── requirements.txt
└── README.md
```

---

## 2. Rules

### Root Level
- Only config files in root (pyproject.toml, .env, README)
- No Python code in root
- No `src` files scattered in root

### Feature-Based Organization
- Group by feature (auth, users, billing)
- NOT by type (all routers together, all services together)

### Forbidden Patterns
- ❌ `utils.py` with 500 lines
- ❌ `models.py` with 50 classes
- ❌ `helpers.py` (too vague)
- ❌ `misc.py` (undefined purpose)

### Migration Rules
- Never delete alembic versions
- Always generate migrations, never edit manually
- Include migration descriptions

---

## 3. Gap Analysis Triggers

The Librarian should flag:

| Pattern | Violation | Action |
|---------|-----------|--------|
| Files in root | `app.py` in root | Move to `src/app/main.py` |
| Fat utils | `utils.py` > 200 lines | Split into `core/` modules |
| Flat structure | All .py in one folder | Create feature folders |
| Missing tests | No `/tests` folder | Create test structure |
| Missing init | Folder without `__init__.py` | Add empty `__init__.py` |
