---
description: Create strategic product vision, personas, epics, roadmap (product-owner)
argument-hint: <description of product or feature request>
---

# /epic — Create Product Strategy and Epics

Delegate to the **product-owner** subagent to create strategic product documentation: vision, personas, OKRs, epics, roadmap, and non-functional requirements.

## Action

Invoke the `product-owner` subagent via the Task tool:

> Analyze and create strategic product artifacts for: **$ARGUMENTS**. Produce vision, personas, epics with KPIs, roadmap, and PM handoff.

## product-owner will

- Load business/technical context via context-scout
- Define product vision and strategy (`artifacts/product/VISION.md`)
- Define personas with JTBD (`artifacts/product/PERSONAS.md`)
- Set OKRs (`artifacts/product/OKRS.md`)
- Create enriched epics (`artifacts/epics/EPIC-XXX.md`)
- Build release roadmap (`artifacts/product/ROADMAP.md`)
- Document non-functional requirements (`artifacts/product/NFRS.md`)
- Produce glossary (`artifacts/product/GLOSSARY.md`)
- Generate PM handoff (`artifacts/product/PM-HANDOFF.md`)

## Output

Complete strategic documentation: Vision & Strategy, Personas (JTBD), Epics (MoSCoW + KPIs + dependencies), Roadmap (MVP → V1.1 → V2.0), NFRs, and PM Handoff.

## Next Step

After approval, run `/story <epic-id>` to have product-manager decompose an approved epic into implementable user stories.
