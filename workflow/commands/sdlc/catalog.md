---
description: Project catalog (artifacts/catalog/) — help | init | check | lookup | refresh
argument-hint: [help|init|check|lookup <termos>|refresh <entradas>]
---

# /catalog — Project Catalog

Deterministic entry to the **catalog** skill: what exists in this project and where — features,
their canonical sources and semantics, and the contracts between sub-projects. In an umbrella,
set the sub-project first (`/sdlc:project <name>`); the catalog belongs to one sub-project.

## Action

**`$ARGUMENTS` = `help`** → print the section **Guia de uso** below verbatim and stop. No tool
call, no skill, no agent: it is a reference card.

Otherwise use the **catalog** skill with the mode in **$ARGUMENTS** (empty → `check`):

| $ARGUMENTS | Mode |
|---|---|
| `init` | create the catalog for the active project — asks how many batches run in parallel |
| `check` | stale entries, broken references, contract mismatches with sibling catalogs |
| `lookup <termos>` | entries matching the terms, canonical sources first |
| `refresh <entradas>` | re-verify named entries against the code (paths under `artifacts/catalog/`, or `providers` for every provider contract) |

> **Note:** `catalog` is a Skill (runs in the main context, which has the Task tool), not a
> subagent — do not invoke it via `Task(subagent_type=...)`. It delegates every write to
> `catalog-keeper`.

## Before `init`

- The active project's checkout is on a dedicated branch (e.g. `docs/catalogo` from the
  integration branch): the bootstrap lands as one reviewable MR, never on a story branch.
- The catalog only takes effect for stories once that MR is merged into the branch stories
  start from — the tech-lead's catalog step looks for `artifacts/catalog/INDEX.md` in the
  story's own tree.

The per-story update is not run from here: the tech-lead does it after review, on every story.

## Guia de uso

```text
CATÁLOGO DO PROJETO — /sdlc:catalog
====================================

O QUE É
  Um mapa do código do projeto, em artifacts/catalog/: cada funcionalidade (o que faz,
  onde vive), a FONTE CANÔNICA de cada regra de domínio (a única função que calcula a
  posição, o câmbio, a chave de cache...) com a SEMÂNTICA do valor (unidade, moeda, fuso,
  qual data), e os CONTRATOS entre sub-projetos (rotas, coleções, eventos, env).

  Serve para os agentes não reimplementarem uma regra que já existe, não corrigirem só
  uma das cópias de um defeito e não lerem um valor com o significado errado.
  Ele DESCREVE o código. Como escrever código novo continua em .claude/context/.

COMANDOS
  /sdlc:catalog help               este guia
  /sdlc:catalog init               cria o catálogo do projeto ativo (uma vez)
  /sdlc:catalog check              entradas desatualizadas, referências quebradas e
                                   divergências de contrato com os irmãos
  /sdlc:catalog lookup <termos>    o que já existe sobre um assunto (fontes canônicas primeiro)
  /sdlc:catalog refresh <entradas> reverifica entradas contra o código
                                   (use `providers` para todos os contratos fornecidos)

  Num guarda-chuva, escolha o sub-projeto antes: /sdlc:project <nome>

PRIMEIRA VEZ (init)
  1. Deixe o sub-projeto atualizado com a branch de integração (ex.: alpha).
  2. /sdlc:project <nome>  →  /sdlc:catalog init
     - ele cria uma branch docs/catalogo (num worktree, se o checkout estiver em outra)
     - pergunta quantos lotes em paralelo: a escolha muda velocidade, não qualidade
  3. Num guarda-chuva, faça todos os sub-projetos que conversam entre si: o cruzamento de
     contratos só funciona entre catálogos que existem.
  4. Revise, commite e faça o MR de docs/catalogo para a branch de integração.
     O catálogo só passa a valer nas stories DEPOIS desse merge.

NO DIA A DIA (automático, você não faz nada)
  - architect / code-analyzer consultam o catálogo antes de explorar o código e escrevem
    "## Fontes Canônicas" na technical-analysis.
  - Os desenvolvedores usam essas fontes; o code-reviewer bloqueia (Major) quem recalcula
    um valor que tem fonte canônica ou o usa com a semântica errada.
  - No fim de cada story (depois do review aprovado), o tech-lead atualiza o catálogo no
    mesmo MR. Se o diff não tocou nada catalogado, custa zero.
  - O merge só acontece com o catálogo em dia (item CATALOG do checkpoint).

O QUE OBSERVAR
  - Início da sessão: "Catálogo X: N entradas desatualizadas" → alguém mudou código fora
    do workflow. Rode /sdlc:catalog check e aceite o refresh.
  - Relatório final da story, linha "Catalog:":
      MISMATCH / SEMANTIC MISMATCH "NOVO nesta story" → a story mudou um contrato que um
      sub-projeto irmão usa. Decida no GATE-MR se pode ir assim.
      "já existia" → divergência antiga entre os projetos; vale abrir uma story.
  - lookup com "⚠ STALE" → a entrada pode estar velha; confirme no código.

MUDANÇAS GRANDES (redesenho de telas, refatoração ampla)
  - Feita por uma story do workflow: nada a fazer. O tech-lead divide a atualização do
    catálogo em lotes paralelos quando a story toca muitas entradas; telas que deixaram
    de existir têm a entrada apagada, telas que só mudaram de arquivo são reapontadas.
  - Feita fora do workflow: o /sdlc:catalog check diz qual caminho seguir —
      até 30% das entradas atingidas  →  /sdlc:catalog refresh <entradas>
      acima de 30%                    →  /sdlc:catalog init (recriar; os limites antigos
                                         das entradas já não batem com o código)

QUANDO USAR O REFRESH
  - Uma entrada se mostrou errada (ex.: lista um campo que o código não produz).
  - As regras do catalog-keeper mudaram depois que o catálogo foi criado.
  - Algumas entradas desatualizadas de uma vez (até ~30% do catálogo).

ONDE FICA
  artifacts/catalog/INDEX.md            índice (gerado — não edite à mão)
  artifacts/catalog/overview.md         o projeto em uma tela
  artifacts/catalog/features/*.md       funcionalidades + fontes canônicas
  artifacts/catalog/contracts/*.md      interfaces fornecidas e consumidas
  O catálogo é commitado no repositório do projeto e revisado no MR, como o código.
```
