<!-- Context: development/backend/python/project-structure | Priority: high | Version: 1.0 | Updated: 2026-07-02 -->

# Python Backend — Project Structure Standard

**Purpose**: Defines the mandatory project structure for all new Python backend services.
Python has two dominant, incompatible conventions — pick ONE based on the Stack Detection
Cheatsheet below and follow it consistently. Do not mix layouts within a project.

---

## Stack Detection Cheatsheet

| File Present | Stack Indicator |
|------|----------------|
| `pyproject.toml` | Modern Python project (PEP 621) |
| `requirements.txt` | Legacy pip dependencies |
| `manage.py` / `settings.py` / `wsgi.py` | Django → use **Layout B** |
| `main.py` + FastAPI import | FastAPI → use **Layout A** |
| `app.py` + Flask import | Flask → use **Layout A** |
| `alembic/` | SQLAlchemy + Alembic migrations (Layout A) |
| `dependencies: motor` | MongoDB via Motor (async ODM) |
| `asgi.py` | ASGI server (Uvicorn/Hypercorn) |

---

## Layout A: FastAPI / Flask — Layered Service Style

```
project-root/
├── app/
│   ├── main.py                      # Entry point: creates app, includes routers, mounts middleware
│   ├── config.py                    # pydantic-settings: env-driven configuration
│   ├── dependencies.py              # Shared Depends() providers (DB session, auth, current user)
│   │
│   ├── api/
│   │   └── routers/
│   │       └── [domain]_router.py   # HTTP routes; request/response wiring; calls services
│   │
│   ├── services/
│   │   └── [domain]_service.py      # Business logic, orchestration, validation
│   │
│   ├── repositories/
│   │   └── [domain]_repository.py   # Data access (SQLAlchemy queries), no business logic
│   │
│   ├── schemas/
│   │   └── [domain]_schema.py       # Pydantic models: request/response contracts
│   │
│   ├── models/
│   │   └── [domain]_model.py        # SQLAlchemy ORM models
│   │
│   └── core/
│       ├── logging.py               # structlog/loguru setup
│       └── exceptions.py            # Custom exceptions + FastAPI exception handlers
│
├── alembic/
│   ├── versions/                    # Migration scripts
│   └── env.py
│
├── tests/
│   └── test_[domain].py             # pytest tests (unit + integration, httpx TestClient)
│
├── alembic.ini
├── pyproject.toml
├── Dockerfile
└── README.md
```

## Layout B: Django — App-Based MVT

```
project-root/
├── project/                         # Project package (settings, root urls)
│   ├── settings.py                  # Or settings/{base,dev,prod}.py split
│   ├── urls.py                      # Root URLconf, includes each app's urls
│   ├── wsgi.py / asgi.py
│   │
│   └── apps/
│       └── [app]/                   # One Django app per business domain
│           ├── models.py            # Django ORM models
│           ├── serializers.py       # DRF serializers: request/response validation
│           ├── views.py             # DRF ViewSets / APIView (business logic entry point)
│           ├── urls.py              # App-level URLconf
│           ├── admin.py             # Django admin registration
│           ├── apps.py              # AppConfig
│           └── migrations/          # Django migrations (auto-generated, do not hand-edit)
│
├── [app]/tests.py  (or tests/test_[app].py)   # pytest-django tests
├── manage.py
├── pyproject.toml
├── Dockerfile
└── README.md
```

---

## Startup Flow (FastAPI)

```
main.py
  └─→ Settings()                     # pydantic-settings reads env vars / .env
  └─→ create_app(settings)
       ├─→ FastAPI(title=..., lifespan=...)
       ├─→ register middleware (CORS, request logging, error handlers)
       ├─→ include_router() for each domain router under /api/v1
       │    └─→ endpoints declare Depends() for DB session, auth, services
       └─→ register exception handlers (core/exceptions.py)
  └─→ uvicorn.run(app, host, port)   # or Docker CMD ["uvicorn", "app.main:app"]
```

---

## Key Patterns

### Pydantic Schemas (Request/Response Validation)

```python
class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)

class UserResponse(BaseModel):
    id: int
    email: EmailStr
    model_config = ConfigDict(from_attributes=True)  # read from ORM objects
```

### SQLAlchemy Models + Alembic Migrations

```python
class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(unique=True, index=True)
```

- Generate migrations: `alembic revision --autogenerate -m "add users"`
- Apply: `alembic upgrade head`. Never hand-edit applied migrations.

### Django ORM + Migrations

```python
class User(models.Model):
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
```

- Generate: `python manage.py makemigrations [app]`
- Apply: `python manage.py migrate`. Migrations are committed, never hand-edited after merge.

### Dependency Injection

- **FastAPI**: `Depends()` for DB sessions, auth, and service instances — declared in
  `dependencies.py`, injected into router function signatures.
- **Django**: no DI container — cross-cutting config lives in `settings.py` and is accessed
  via `django.conf.settings`; app-level wiring lives in `apps.py`.

### Configuration via Environment Variables

```python
class Settings(BaseSettings):
    database_url: str
    redis_url: str = "redis://localhost:6379"
    model_config = SettingsConfigDict(env_file=".env")
```

- FastAPI/Flask: `pydantic-settings` (preferred) or `python-decouple`.
- Django: `django-environ` or `python-decouple` reading into `settings.py`.

### Structured Logging

```python
import structlog
logger = structlog.get_logger()
logger.info("user_created", user_id=user.id, email=user.email)
```

- Use `structlog` or `loguru`. Never bare `print()`. Always log with contextual key-value pairs, not interpolated strings.

---

## Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| Files/modules | `snake_case.py` | `user_service.py` |
| Functions/variables | `snake_case` | `get_user_by_id()` |
| Classes | `PascalCase` | `UserService`, `UserModel` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_RETRIES` |
| Pydantic schemas | `PascalCase` + intent suffix | `UserCreate`, `UserResponse` |
| Django apps | `snake_case` | `apps/user_profile/` |
| FastAPI routers | `snake_case` + `_router` | `user_router.py` |

---

## When Creating a New Project

1. Run Stack Detection Cheatsheet to confirm framework (or ask if greenfield).
2. **FastAPI/Flask**: create `app/main.py`, `app/config.py`, `alembic/` skeleton.
3. **Django**: create project via `django-admin startproject`, then `python manage.py startapp [name]` per domain.
4. For each business domain: FastAPI → router + service + repository + schema + model; Django → models.py + serializers.py + views.py + urls.py.
5. Wire configuration through `pydantic-settings` (FastAPI/Flask) or `settings.py` + `django-environ` (Django). Never hardcode secrets.
6. Set up structured logging (`structlog`/`loguru`) before writing business logic.
7. Create `tests/` (or per-app `tests.py`) with `pytest` (+ `pytest-django` for Django) targeting ≥90% coverage.

---

## Related Context

- **API Design Principles** → `../standards/api-design.md`
- **Code Quality** → `../standards/code-quality.md`
- **Clean Code** → `../standards/clean-code.md`
