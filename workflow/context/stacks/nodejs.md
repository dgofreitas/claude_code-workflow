<!-- Context: development/backend/nodejs/project-structure | Priority: high | Version: 1.0 | Updated: 2026-04-01 -->

# Node.js Backend — Project Structure Standard

**Purpose**: Defines the mandatory project structure for all new Node.js backend services.
All new projects MUST follow this structure. Do not invent alternative patterns.

---

## Directory Layout

```
project-root/
├── config/
│   └── app.json                    # Centralized configuration (ports, DB, Redis, services)
│
├── docs/
│   └── openapi.yml                 # OpenAPI 3.0 spec (used for request/response validation)
│
├── src/
│   ├── main.js                     # Entry point: loads config, creates AppService, starts server
│   │
│   ├── app/
│   │   ├── app-constants.js        # Service name, error codes, constants
│   │   ├── app-service.js          # Express setup: helmet, cors, body-parser, OpenAPI validator, routes
│   │   ├── app-manager.js          # Central coordinator: initializes DB, Redis, all domain managers
│   │   ├── app-router.js           # Base routes (health check, root-level endpoints)
│   │   │
│   │   └── [domain]/               # One directory per business domain (e.g., contact/, mailing/, engine/)
│   │       ├── [domain]-manager.js # Business logic for this domain
│   │       ├── [domain]-router.js  # HTTP routes for this domain
│   │       ├── [domain]-dao.js     # Data Access Object (DB queries)
│   │       └── [domain]-model.js   # Mongoose/DB schema definition
│   │
│   ├── dispatchers/                # Outbound calls to external services
│   │   └── [service]-dispatcher.js # One file per external service
│   │
│   ├── __tests__/                  # Test files
│   │   └── [domain].test.js
│   │
│   └── __mocks__/                  # Test mocks
│       └── [mock-name].js
│
├── Dockerfile
├── package.json
├── README.md
└── CHANGELOG.md
```

---

## Startup Flow

```
main.js
  └─→ loadConfig()                  # Reads config/app.json, applies env overrides
  └─→ new AppService()
       └─→ initialize(config)
            └─→ new AppManager()
                 └─→ appManager.initialize(config)
                      ├─→ Connect to DB (MongoDB)
                      ├─→ Connect to Redis
                      ├─→ Initialize domain managers (ContactManager, MailingManager, etc.)
                      └─→ Initialize dispatchers (external service clients)
            └─→ configure()
                 ├─→ Express app with middlewares (helmet, cors, body-parser, OpenAPI validator)
                 ├─→ Mount routes: /v1/private/* (inter-service, no auth)
                 ├─→ Mount routes: /v1/public/*  (client-facing, with auth middleware)
                 └─→ Error handler middleware
       └─→ app.listen(config.port)
```

---

## Key Patterns

### AppService (Express Setup)

- Creates Express app with security middlewares (helmet, cors)
- Validates ALL requests/responses against `docs/openapi.yml` using `express-openapi-validator`
- Mounts routes in two groups:
  - `/v1/private/*` — inter-service communication (no auth)
  - `/v1/public/*` — client-facing (with JWT auth middleware)
- Centralized error handler at the bottom

### AppManager (Coordinator)

- Central coordinator that owns all domain managers and dispatchers
- Initializes database connection, Redis, and all managers
- Domain managers receive `appManager` reference to access other managers/dispatchers
- Handles cross-domain coordination and events (Redis pub/sub)

### Domain Modules

Each business domain is a self-contained directory under `src/app/[domain]/`:

| File | Responsibility |
|------|----------------|
| `[domain]-router.js` | HTTP route handlers, input extraction, response formatting |
| `[domain]-manager.js` | Business logic, validation, orchestration |
| `[domain]-dao.js` | Database queries (MongoDB/Mongoose) |
| `[domain]-model.js` | Schema definition, indexes |

**Router pattern**:

```javascript
class DomainRouter {
  static getPublicRoutes(appManager) {
    const router = express.Router()
    const manager = appManager.getDomainManager()
    // Define routes...
    return router
  }

  static getPrivateRoutes(appManager) {
    const router = express.Router()
    // Define inter-service routes...
    return router
  }
}
```

**Manager pattern**:

```javascript
class DomainManager {
  constructor(appManager, appDB) {
    this.appManager = appManager
    this.dao = new DomainDAO(appDB.getDb())
  }

  async initialize(appManager) {
    // Post-initialization (after all managers are created)
  }

  // Business methods...
}
```

### Dispatchers (External Services)

- One dispatcher per external service
- Located in `src/dispatchers/[service]-dispatcher.js`
- Encapsulates HTTP calls to other microservices
- Receives `config` in constructor for service URLs

### Configuration

- `config/app.json` holds all configuration: port, DB connection, Redis, service URLs, feature flags
- Environment variables override config values in `main.js` (`process.env.DATABASE_URL || config.db.url`)

### OpenAPI Validation

- API spec lives in `docs/openapi.yml`
- `express-openapi-validator` middleware validates requests AND responses automatically
- In dev mode, Swagger UI is available at `/docs`

---

## Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| Service name | `kebab-case` | `dialer-service` |
| Files | `kebab-case.js` | `mailing-manager.js` |
| Classes | `PascalCase` | `MailingManager` |
| Domain dirs | `kebab-case` | `src/app/mailing/` |
| Constants | `UPPER_SNAKE_CASE` | `SERVICE_NAME` |
| Config file | `app.json` | `config/app.json` |

---

## When Creating a New Project

1. Create `config/app.json` with port, DB, Redis, and service URLs
2. Create `docs/openapi.yml` with the API spec
3. Create `src/main.js` entry point
4. Create `src/app/app-constants.js` with service name and error codes
5. Create `src/app/app-service.js` with Express setup
6. Create `src/app/app-manager.js` as the central coordinator
7. For each business domain, create `src/app/[domain]/` with manager, router, dao, model
8. For each external service dependency, create `src/dispatchers/[service]-dispatcher.js`

---

## Related Context

- **Backend Navigation** → `../../backend-navigation.md`
- **API Design Principles** → `../../principles/api-design.md`
- **Code Quality** → `../../../core/standards/code-quality.md`
- **Clean Code** → `../../principles/clean-code.md`
