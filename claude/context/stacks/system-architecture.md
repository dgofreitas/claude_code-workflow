# System Architecture & Greenfield Scaffolding

This context file guides the **SystemArchitect** agent when setting up new projects (greenfield). It contains decision frameworks, scaffolding checklists, and references to specialized stacks.

## 1. Architecture Patterns Decision Matrix

| Pattern | When to Choose | Violates (Do NOT choose if) |
|---------|----------------|-----------------------------|
| **Modular Monolith** | Small-to-medium teams, rapid MVP, single deployment unit. | Team > 30 engineers, components have vastly different scale needs. |
| **Microservices** | Independent scaling, polyglot teams, high fault isolation (NFR-AVL). | Small team, strict latency requirements (<10ms between domains). |
| **Serverless** | Sporadic traffic, fast time-to-market, zero ops. | Heavy continuous compute, predictable high load, vendor lock-in forbidden. |

## 2. Tech Stack Matching (NFR-Driven)

When selecting the stack, match technologies to the Non-Functional Requirements (NFRs):

### Backend & Runtime

- **Node.js (Express/Fastify)**: I/O heavy, real-time apps, standard enterprise web. (Ref: `stacks/nodejs.md`)
- **Python (FastAPI)**: AI/ML integration, data processing, rapid prototyping.
- **Go**: High concurrency, low latency, microservices.

### Database (ACID vs Scale)

- **MongoDB**: Default choice. Schema-less, document-heavy, fast iteration. (Only if ACID cross-collection is not critical).
- **PostgreSQL**: Relational data, strong ACID, JSON support.
- **Redis**: Caching, session management, rate limiting.

### Frontend

- **React/Next.js**: SEO critical, complex state, large ecosystem. (Ref: `stacks/react.md`)
- **Vue/Nuxt**: Faster onboarding, simpler state management.

### Infrastructure

- **Docker Compose**: Standard for local dev and single-server deployments. (Ref: `stacks/dockerfile-patterns.md`)
- **Kubernetes**: Required only if NFR-SCL explicitly demands auto-scaling orchestration.

## 3. Greenfield Scaffolding Checklist

When creating the initial project structure, the SystemArchitect (or DevopsSpecialist) MUST generate:

1. **Root Configuration**:
   - `.gitignore` (standard for chosen language)
   - `.env.example` (with all required keys)
   - `docker-compose.yml` (dev environment with DB + Cache)
   - `Dockerfile` (multi-stage)

2. **Directory Structure (Standard)**:

   ```
   src/
   ├── frontend/     # UI layer
   ├── backend/      # API layer
   ├── shared/       # Common types/utils
   ├── docs/         # Documentation
   └── scripts/      # Automation
   ```

3. **Architecture Documentation**:
   - MUST generate `docs/architecture/TECH-STACK.md` containing the approved stack, NFR compliance, and deployment topology.
   - MUST update `context/project/technical-domain.md` and `context/project/decisions-log.md`.
