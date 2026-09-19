---
name: container-dev
description: Standardize container-based development for projects using docker compose. Use when running docker compose, building images, debugging service startup, or deciding dev vs prod mode. Triggers: container, compose, docker, dev mode, build image, deploy local.
---

# Container Development

## Default mode: DEV

When working with containers/compose/builds in this project, **always use DEV mode by default**. Only use production mode if the user explicitly requests it (e.g., "modo produção", "production mode", "build prod", "deploy prod").

## Project pattern

- `docker-compose.yml` — base, production-ready.
- `docker-compose.override.yml` — auto-loaded in dev. Use this for dev-only changes.
- `docker-compose.prod.yml` — explicit production overrides (load with `-f`).

## Correct dev commands

```bash
# Start dev stack (auto-loads override)
docker compose up -d

# View logs
docker compose logs -f [service]

# Rebuild dev image after dependency change
docker compose up -d --build [service]

# Stop everything
docker compose down
```

## Common mistakes to avoid

1. **Never run prod builds for dev debugging.** Use the dev override.
2. **Never put `VITE_*` in `docker-compose.yml`.** Vite vars are build-time. In dev they live in `docker-compose.override.yml`.
3. **Never edit `docker-compose.yml` for dev-only tweaks.** Use the override.
4. **Do not expose DB/cache ports to host in prod.** Only nginx exposes `8088:80`.

## Dev deployment checklist

- [ ] `.env` exists and is gitignored
- [ ] `docker compose config` is valid
- [ ] All services `healthy` in `docker compose ps`
- [ ] Frontend loads at `http://localhost:8088`
- [ ] API reachable via nginx at `/api/v1/health`
- [ ] No `VITE_API_URL` absolute `http://localhost/api/v1` in built bundle

## Prod only when asked

If user asks for production:

```bash
# Build prod images
bash docker build --target development -t {project}/frontend:x.y.z -f frontend/Dockerfile .
bash docker build --target development -t {project}/backend:x.y.z -f backend/Dockerfile .

# Start prod stack explicitly
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
