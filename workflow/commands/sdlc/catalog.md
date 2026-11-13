---
description: Project catalog (artifacts/catalog/) — help | init | check | lookup | path | refresh
argument-hint: [help|init|check|lookup <termos>|path [--to] <termos>|refresh] [<sub-projeto>] [<entradas>]
---

# /catalog — Project Catalog

Deterministic entry to the **catalog** skill: what exists in this project and where — features,
their canonical sources and semantics, and the contracts between sub-projects. Each catalog
belongs to one sub-project; in an umbrella, `check`, `refresh` and `init` with no sub-project
named cover all of them, and a sub-project named right after the mode scopes that one command
(the session's active sub-project is not changed). `lookup` and `path` use the active one.

## Action

**`$ARGUMENTS` = `help`** → print the section **Guia de uso** below verbatim and stop. No tool
call, no skill, no agent: it is a reference card.

Otherwise use the **catalog** skill with the mode in **$ARGUMENTS** (empty → `check`):

| $ARGUMENTS | Mode |
|---|---|
| `init [<sub-projeto>]` | create a catalog — at the umbrella root, lists the sub-projects without one and asks which; asks how many batches run in parallel |
| `check [<sub-projeto>]` | where each checkout stands, stale entries, broken references, contract mismatches, possible undeclared mirrors — each with the refresh to run |
| `lookup <termos>` | entries matching the terms, canonical sources first |
| `path <termos\|id>` | the route of an interface across the sub-projects, and what each hop handles (`--to <id>`: who reaches it) |
| `refresh [<sub-projeto>] [<entradas>]` | re-verify entries against the code — the named ones (paths under `artifacts/catalog/`, or `providers`), or, with none, the ones `check` points at, asking which sub-projects at the root |

> **Note:** `catalog` is a Skill (runs in the main context, which has the Task tool), not a
> subagent — do not invoke it via `Task(subagent_type=...)`. It delegates every write to
> `catalog-keeper`.

## Before `init`

- The bootstrap lands on a dedicated branch (`docs/catalog-bootstrap` from the integration
  branch, in a worktree the script prepares), as one reviewable MR — never on a story branch.
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
  /sdlc:catalog init [<sub>]       cria o catálogo (uma vez); na raiz, lista os sub-projetos
                                   sem catálogo e pergunta quais
  /sdlc:catalog check [<sub>]      estado de cada checkout, entradas desatualizadas, referências
                                   quebradas, divergências de contrato, possíveis espelhos —
                                   cada achado com o refresh a rodar
  /sdlc:catalog lookup <termos>    o que já existe sobre um assunto (fontes canônicas primeiro)
  /sdlc:catalog path <termos|id>   por onde passa uma interface entre os sub-projetos e o que
                                   cada etapa trata (ex.: web → gateway → api → banco)
  /sdlc:catalog path --to <id>     quem chega até ela — o impacto de mudá-la
  /sdlc:catalog refresh [<sub>] [<entradas>]
                                   reverifica entradas contra o código: as nomeadas (ou
                                   `providers`), ou, sem nenhuma, as que o check apontou —
                                   na raiz, pergunta de quais sub-projetos

  NUM GUARDA-CHUVA, NA RAIZ (sem /sdlc:project)
    check, refresh e init cobrem todos os sub-projetos. Antes, o script busca o remoto e
    mostra onde cada checkout está; os que estão só atrás da branch de integração, limpos,
    ele oferece atualizar (fast-forward) — e pergunta. Checkout em outra branch ou com
    alterações nunca é tocado: pode ser o trabalho de outra sessão.
    Um nome depois do modo restringe só aquele comando:  /sdlc:catalog refresh web
    refresh e init escrevem num worktree docs/... de cada sub-projeto, nunca no checkout.

PRIMEIRA VEZ (init)
  1. Na raiz:  /sdlc:catalog init   (ou  /sdlc:catalog init <sub>)
     - mostra quem não tem catálogo e pergunta quais criar; um catálogo que só existe no
       remoto é para atualizar o checkout, nunca para recriar
     - cria a branch docs/catalog-bootstrap num worktree
     - pergunta quantos lotes em paralelo: a escolha muda velocidade, não qualidade
  2. Num guarda-chuva, faça todos os sub-projetos que conversam entre si: o cruzamento de
     contratos só funciona entre catálogos que existem.
  3. Revise, commite e faça o MR de docs/catalog-bootstrap para a branch de integração.
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
  - lookup com "espelhado por: <irmão>" → outro sub-projeto repete esta regra de propósito;
    mudar aqui exige mudar lá. Do lado do espelho, o check marca STALE quando o dono mudou.
  - check com "possible undeclared mirror" → uma linha canônica diz, em texto, que copia
    algo de um irmão, sem a referência que o check confere. A linha "(remedy)" traz o
    refresh pronto; o catalog-keeper decide se é espelho e o declara. Nas entradas que a
    story tocou, ele resolve sozinho no fim da story.

CAMINHO ENTRE SUB-PROJETOS (automático)
  O caminho não é escrito em lugar nenhum: o script o calcula a cada consulta a partir dos
  contratos e features dos catálogos irmãos. Um proxy ou gateway é um contrato curinga
  (ex.: http.ANY./api/v1/*); quem passa por ele é deduzido, nunca anotado à mão.
  O lookup que o architect já roda mostra o caminho e o que cada etapa trata.

MUDANÇAS GRANDES (redesenho de telas, refatoração ampla)
  - Feita por uma story do workflow: nada a fazer. O tech-lead divide a atualização do
    catálogo em lotes paralelos quando a story toca muitas entradas; telas que deixaram
    de existir têm a entrada apagada, telas que só mudaram de arquivo são reapontadas.
  - Feita fora do workflow: o /sdlc:catalog check diz qual caminho seguir, na linha
    "(remedy)" de cada sub-projeto —
      até 30% das entradas atingidas  →  /sdlc:catalog refresh <sub> <entradas>
      acima de 30%                    →  /sdlc:catalog init <sub> (recriar; os limites
                                         antigos das entradas já não batem com o código)

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
