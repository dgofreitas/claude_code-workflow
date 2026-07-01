<!-- Context: stacks/nodejs-domain-structure | Priority: high | Version: 1.0 | Updated: 2026-05-07 -->

# Node.js Backend — Domain-Driven Modular Structure

**Purpose**: Advanced backend structure for multi-domain Node.js APIs with external integrations. Extends `stacks/nodejs.md` with dispatcher pattern, Mongoose plugins, and cross-domain coordination.

**When to use**: Backends that integrate multiple external services (financial APIs, payment gateways, notification providers) and span 5+ business domains.

---

## Directory Layout

```
backend/
├── config/app.json                       # Central config (ports, DB, services)
├── docs/openapi.yml                      # Contract validated via express-openapi-validator
├── Dockerfile                            # Multi-stage (see standards/dockerfile-patterns.md)
├── jest.setup.js
├── package.json
└── src/
    ├── main.js                           # Entry: loadConfig → AppService → listen
    ├── app/
    │   ├── app-constants.js              # Service name, error codes, enums
    │   ├── app-service.js                # Express setup (helmet, cors, openapi-validator)
    │   ├── app-manager.js                # Central coordinator — owns DBs + all managers
    │   ├── app-router.js                 # Health, root endpoints
    │   │
    │   ├── <domain>/                     # One dir per business domain
    │   │   ├── <domain>-model.js         # Mongoose schema (uses shared plugins)
    │   │   ├── <domain>-dao.js           # DB queries — never exposes Mongoose outside
    │   │   ├── <domain>-manager.js       # Business logic — orchestrates dao + dispatchers
    │   │   ├── <domain>-service.js       # Optional: stateless helpers/transformers
    │   │   ├── <domain>-router.js        # HTTP routes — thin, delegates to manager
    │   │   └── <domain>-constants.js     # Domain-specific constants
    │   │
    │   ├── middleware/                   # Auth, validation, error handler
    │   └── mongoose-plugins/             # Cross-cutting schema plugins (timestamps, soft-delete, audit)
    │
    ├── dispatchers/                      # External integration clients
    │   └── <service>-dispatcher.js       # One file per external service
    │
    ├── shared/                           # Copy of /shared/ via Dockerfile (symlinked at build)
    └── __tests__/                        # Mirror of src/ structure
```

---

## Contract: 5 Files per Domain

**Naming convention is strict** — agents rely on it for discovery:

| File | Responsibility | Rules |
|------|----------------|-------|
| `<domain>-model.js` | Mongoose schema + indexes | Pure schema. No business logic. Apply plugins here. |
| `<domain>-dao.js` | Data access (CRUD, queries) | Returns plain objects, never Mongoose docs. Handles index hints. |
| `<domain>-manager.js` | Business logic | Orchestrates dao + dispatchers + other managers. Transactions live here. |
| `<domain>-router.js` | HTTP routes | Thin. Extract params → call manager → format response. No logic. |
| `<domain>-constants.js` | Enums, error codes | Shared domain constants. Import in router/manager. |

**Optional**: `<domain>-service.js` for stateless transforms (CSV → internal model, etc).

---

## Dispatcher Pattern — External Integrations

**One dispatcher per external service.** Isolates third-party contracts, API keys, retries, rate limits.

```javascript
// src/dispatchers/brapi-dispatcher.js
class BrapiDispatcher {
  constructor(config) {
    this.baseUrl = config.services.brapi.url
    this.token = config.services.brapi.token
    this.client = axios.create({ baseURL: this.baseUrl, timeout: 5000 })
    this.cache = new Map()  // Or Redis via appManager
  }

  async getQuote(ticker) {
    const cached = this.cache.get(ticker)
    if (cached && Date.now() - cached.ts < 60_000) return cached.data
    const { data } = await this.client.get(`/quote/${ticker}`, {
      params: { token: this.token }
    })
    this.cache.set(ticker, { data, ts: Date.now() })
    return data
  }
}
module.exports = BrapiDispatcher
```

**Rules:**

- Dispatchers **never** import managers — dependency flows one way (manager → dispatcher)
- All external calls have timeout, retries (`axios-retry` or custom), circuit breaker
- API keys/secrets injected via constructor, never hardcoded
- Rate limits respected per-dispatcher (token bucket in Redis)

---

## AppManager — Central Coordinator

```javascript
// src/app/app-manager.js
class AppManager {
  async initialize(config) {
    this.db = await connectMongo(config.db)
    this.redis = await connectRedis(config.redis)

    // Instantiate dispatchers (order doesn't matter — no deps)
    this.dispatchers = {
      brapi: new BrapiDispatcher(config),
      coingecko: new CoinGeckoDispatcher(config),
      email: new EmailDispatcher(config)
    }

    // Instantiate managers (inject appManager for cross-domain access)
    this.managers = {
      auth: new AuthManager(this, this.db),
      wallet: new WalletManager(this, this.db),
      crypto: new CryptoManager(this, this.db)
    }

    // Post-init hook (e.g., subscribe to Redis pub/sub)
    for (const m of Object.values(this.managers)) {
      if (m.initialize) await m.initialize(this)
    }
  }
}
```

Each manager gets `appManager` reference — can access `this.appManager.dispatchers.brapi` or `this.appManager.managers.wallet`.

---

## Mongoose Plugins — Cross-cutting Concerns

**Centralize repeating schema behaviors** in `src/app/mongoose-plugins/`:

```javascript
// src/app/mongoose-plugins/audit-plugin.js
module.exports = function auditPlugin(schema) {
  schema.add({
    createdBy: { type: ObjectId, ref: 'User' },
    updatedBy: { type: ObjectId, ref: 'User' }
  })
  schema.pre('save', function() {
    if (this.isNew) this.createdBy = this._user
    this.updatedBy = this._user
  })
}
```

```javascript
// src/app/wallet/wallet-model.js
const walletSchema = new Schema({ ... })
walletSchema.plugin(auditPlugin)
walletSchema.plugin(softDeletePlugin)
walletSchema.plugin(timestampsPlugin)
```

**Common plugins:** `timestamps`, `soft-delete`, `audit`, `versioning`, `tenant-scoping`.

---

## Shared Module — Cross-stack Constants

Constantes usadas em back **e** front ficam em `/shared/` (raiz do repo):

```javascript
// shared/constants/asset-types.js
module.exports = {
  ASSET_TYPES: Object.freeze({
    STOCK: 'STOCK',
    CRYPTO: 'CRYPTO',
    FIXED_INCOME: 'FIXED_INCOME'
  })
}
```

No backend Dockerfile:

```dockerfile
COPY shared/ /shared/             # Copy, não volume — self-contained
```

**Import pattern**: `const { ASSET_TYPES } = require('/shared/constants/asset-types')`

---

## OpenAPI-first Validation

```javascript
// src/app/app-service.js
app.use(OpenApiValidator.middleware({
  apiSpec: './docs/openapi.yml',
  validateRequests: true,
  validateResponses: process.env.NODE_ENV !== 'production'
}))
```

Benefícios: contratos explícitos, validação automática, Swagger UI grátis (`/docs`).

---

## Related Context

- `stacks/fullstack-containerized.md` — container orchestration
- `stacks/nodejs.md` — baseline Node.js structure
- `standards/api-design.md` — REST patterns
- `standards/security.md` — auth middleware, helmet, rate-limit
