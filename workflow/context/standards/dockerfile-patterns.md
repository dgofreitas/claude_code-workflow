<!-- Context: standards/dockerfile-patterns | Priority: high | Version: 1.0 | Updated: 2026-05-07 -->

# Dockerfile Patterns — Production-grade Multi-stage Builds

**Purpose**: Define mandatory Dockerfile patterns for Node.js backends and Vite frontends. Covers multi-stage builds, non-root execution, signal handling, healthchecks, and build-arg strategy.

**When to use**: Every Dockerfile in the project. These patterns are non-negotiable for production images.

---

## Mandatory Principles

1. **Multi-stage**: separar deps, build e runtime → imagem final mínima
2. **Non-root user**: nunca rode como root em produção
3. **dumb-init**: reencaminha sinais (SIGTERM) corretamente para Node.js
4. **Healthcheck**: `HEALTHCHECK` inline + compose `healthcheck:` redundantes (defense-in-depth)
5. **No secrets in layers**: `.env` nunca entra na imagem — use `ENV` em runtime ou Docker secrets
6. **Minimize final layer**: só artefatos de produção + `package.json` mínimo

---

## Node.js Backend — Template

```dockerfile
# ============================================================================
# Stage 1: Base
# ============================================================================
FROM node:20-alpine AS base
RUN apk add --no-cache dumb-init
WORKDIR /app

# ============================================================================
# Stage 2: Development
# ============================================================================
FROM base AS development
COPY backend/package*.json ./
RUN npm install
COPY backend/ .
COPY shared/ /shared/
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8000/health || exit 1
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/main.js"]

# ============================================================================
# Stage 3: Build (prod deps only)
# ============================================================================
FROM base AS build
COPY backend/package*.json ./
RUN npm ci --only=production && npm cache clean --force
COPY backend/ .
COPY shared/ /shared/

# ============================================================================
# Stage 4: Production
# ============================================================================
FROM base AS production
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
COPY --from=build --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs backend/ .
COPY --chown=nodejs:nodejs shared/ /shared/
USER nodejs
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8000/health || exit 1
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/main.js"]
```

**Build targets:**

```bash
# Dev (com devDependencies)
docker build --target development -t myapp/backend:dev -f backend/Dockerfile .

# Prod (não-root, mínimo)
docker build --target production -t myapp/backend:1.0.0 -f backend/Dockerfile .
```

---

## Vite Frontend — Template

```dockerfile
# ============================================================================
# Stage 1: Development (HMR)
# ============================================================================
FROM node:20-alpine AS development
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ .
COPY shared/ ./shared/
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
CMD ["npm", "run", "dev", "--", "--host"]

# ============================================================================
# Stage 2: Build (Vite → /dist)
# ============================================================================
FROM node:20-alpine AS build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ .
COPY shared/ ./shared/

# ⚠️ VITE_* são BUILD-TIME. Precisam ser --build-arg.
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL

RUN npm run lint && npm run build

# ============================================================================
# Stage 3: Production (nginx serving /dist)
# ============================================================================
FROM nginx:alpine AS production
COPY frontend/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1/health || exit 1
CMD ["nginx", "-g", "daemon off;"]
```

**Build com API URL de produção:**

```bash
docker build \
  --target production \
  --build-arg VITE_API_URL=https://api.myapp.com \
  -t myapp/frontend:1.0.0 \
  -f frontend/Dockerfile .
```

---

## Why dumb-init?

Node.js como PID 1 **não propaga SIGTERM** corretamente. Sem dumb-init:

- `docker stop` → Node ignora sinal → força SIGKILL após 10s
- Conexões DB não fecham graciosamente
- Testes de integração com `.close()` vazam

**Com dumb-init:** signals reencaminhados, shutdown graceful.

---

## Non-root User — Why

Root dentro do container + escape de kernel = root no host.

```dockerfile
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
USER nodejs
```

**Regra**: UID ≥ 1000, nunca `USER 0` (root).

---

## Healthcheck Strategy

**Redundância proposital:**

| Camada | Mecanismo |
|--------|-----------|
| Dockerfile | `HEALTHCHECK` — usado por `docker ps` |
| docker-compose | `healthcheck:` + `depends_on: condition: service_healthy` |
| Endpoint HTTP | `/health` no app — `200 OK` só se DB+Redis OK |

**Never** use `curl` no healthcheck de imagem alpine — não vem instalado. Use `wget`.

---

## Layer Caching — Order Matters

**Ordem correta** (invalidation minima):

```dockerfile
# 1. Dependências (muda raramente)
COPY package*.json ./
RUN npm ci

# 2. Source code (muda frequentemente)
COPY src/ ./src/
```

**Errado** (cache busted em cada mudança):

```dockerfile
COPY . .
RUN npm ci  # ← re-run em toda mudança de código
```

---

## .dockerignore — Mandatory

```
node_modules
coverage
dist
.git
.env
.env.*
*.log
__tests__
.tmp
.opencode
```

Sem `.dockerignore` → context build de 500MB+, cache invalidado em mudança trivial.

---

## Common Anti-patterns

| ❌ Evitar | ✅ Correto |
|----------|-----------|
| `FROM node:latest` | `FROM node:20-alpine` (versão fixa) |
| `USER root` / sem `USER` | `USER nodejs` (non-root, UID ≥ 1000) |
| `CMD node src/main.js` | `ENTRYPOINT ["dumb-init", "--"]` + `CMD` |
| Env vars Vite em compose | `--build-arg VITE_*` |
| `COPY . .` no início | `COPY package*.json` → `npm ci` → `COPY src/` |
| `.env` copiado na imagem | Runtime env + Docker secrets |
| Sem `HEALTHCHECK` | Healthcheck em todos os stages |
| `curl` no healthcheck alpine | `wget` (alpine não tem curl por default) |

---

## Related Context

- `stacks/fullstack-containerized.md` · `stacks/nodejs-domain-structure.md` · `standards/security.md`
