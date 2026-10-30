#!/usr/bin/env bash
#
# Fixture para workflow/scripts/backlog-status.sh: monta um repo com um caso por status,
# roda o script em modo git-only e confere cada linha. Também confere que nada foi escrito.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/workflow/scripts/backlog-status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

R="${TMP}/proj"
D="${R}/artifacts/stories"
g() { git -C "${R}" "$@" >/dev/null; }

story() {
    local id="$1" prio="$2" created="$3" extra="${4:-}"
    cat <<EOF
---
id: ${id}
type: story
title: Story ${id}
development: fixture
generated_by: product-manager
schema_version: 1
created: ${created}
${extra}---

### ${id}

**Priority**: ${prio}
**Estimate**: 3
EOF
}

checkpoint() {
    printf -- '---\nid: %s\ntype: checkpoint\nstatus: in-progress\n---\n## SDLC STATUS\n- [x] Implementation\n- [%s] Merge Request\n' "$1" "$2"
}

git init -q -b main "${TMP}/remote.git" --bare
git init -q -b main "${R}"
g config user.email t@t; g config user.name t
g remote add origin "${TMP}/remote.git"
mkdir -p "${D}"

story STORY-001-merged       "Must Have"   2026-01-01 > "${D}/STORY-001-merged.md"
story STORY-002-group        "Should Have" 2026-01-01 > "${D}/STORY-002-group.md"
story STORY-003-wip          "Must Have"   2026-01-01 > "${D}/STORY-003-wip.md"
story STORY-004-planned      "Should Have" 2026-01-01 > "${D}/STORY-004-planned.md"
printf -- '---\ntype: technical-analysis\n---\n' > "${D}/STORY-004-planned-technical-analysis.md"
story STORY-005-pending      "Must Have"   2026-01-01 > "${D}/STORY-005-pending.md"
story STORY-007-old          "Must Have"   2026-01-01 > "${D}/STORY-007-old.md"
story STORY-008-new          "Could Have"  2099-01-01 "supersedes: [STORY-007-old]
" > "${D}/STORY-008-new.md"
story STORY-011-short-cp     "Should Have" 2026-01-01 > "${D}/STORY-011-short-cp.md"
printf -- '---\ntype: baseline-report\n---\n' > "${D}/STORY-001-merged-baseline.md"
printf '# Backlog\n| [[STORY-001-merged]] | [[STORY-002-group]] | STORY-003 | STORY-004 | STORY-005 | STORY-007 | STORY-008 | STORY-011 |\n' \
    > "${D}/BACKLOG-SUMMARY-fixture.md"
g add -A; g commit -qm "docs: add stories"
# Critério 3: o id aparece numa mensagem de commit, mas a story nunca foi feita.
g commit -q --allow-empty -m "docs: add STORY-005-pending"

# DONE por merge commit com a branch no assunto.
g checkout -qb feat/STORY-001-merged
checkpoint STORY-001-merged " " > "${D}/STORY-001-merged-checkpoint.md"
g add -A; g commit -qm "feat: one"
g checkout -q main; g merge -q --no-ff -m "Merge branch 'feat/STORY-001-merged'" feat/STORY-001-merged
g branch -qd feat/STORY-001-merged

# Critério 2: commit de grupo, sem branch nem o id exato — DONE pelo checkpoint em <ref>.
checkpoint STORY-002-group "x" > "${D}/STORY-002-group-checkpoint.md"
g add -A; g commit -qm "feat: STORY-001..003 batch"
g push -q origin main

# IN-PROGRESS: worktree com checkpoint aberto.
g worktree add -q -b feat/STORY-003-wip "${TMP}/wt-003" origin/main
checkpoint STORY-003-wip " " > "${TMP}/wt-003/artifacts/stories/STORY-003-wip-checkpoint.md"
git -C "${TMP}/wt-003" add -A; git -C "${TMP}/wt-003" -c user.email=t@t -c user.name=t commit -qm wip

# UNTRACKED, e checkpoint com id curto (fora de <ref>) de uma story com slug.
story STORY-006-untracked "Should Have" 2026-01-01 > "${D}/STORY-006-untracked.md"
checkpoint STORY-011 " " > "${D}/STORY-011-checkpoint.md"

touch "${TMP}/marker"; sleep 1
OUT="$(bash "${SCRIPT}" --project "${R}")"

fail=0
expect() {
    local id="$1" status="$2" alert="$3" row
    row="$(grep -E "^\| ${id} \|" <<< "${OUT}" || true)"
    if [[ -z "${row}" ]]; then
        [[ "${status}" == "HIDDEN" ]] && { echo "ok   ${id} oculto"; return; }
        echo "FAIL ${id}: linha ausente"; fail=1; return
    fi
    [[ "${status}" == "HIDDEN" ]] && { echo "FAIL ${id}: devia estar oculto"; fail=1; return; }
    if [[ "${row}" == *"| ${status} |"* && "${row}" == *"${alert}"* ]]; then
        echo "ok   ${id} ${status} ${alert}"
    else
        echo "FAIL ${id}: esperado ${status} ${alert} — ${row}"; fail=1
    fi
}

expect STORY-003-wip       IN-PROGRESS "worktree wt-003"
expect STORY-011-short-cp  IN-PROGRESS "checkpoint"
expect STORY-005-pending   PENDING     "MUST-HAVE-AGING"
expect STORY-006-untracked PENDING     "UNTRACKED,NOT-IN-SUMMARY"
expect STORY-008-new       PENDING     "- |"
expect STORY-004-planned   PLANNED     ""
expect STORY-001-merged    HIDDEN      ""
expect STORY-002-group     HIDDEN      ""
expect STORY-007-old       HIDDEN      ""
expect STORY-001-merged-baseline HIDDEN ""

ALL="$(bash "${SCRIPT}" --project "${R}" --all)"
grep -qE '^\| STORY-001-merged \|.*\| DONE \| merge commit' <<< "${ALL}" && echo "ok   STORY-001 DONE (merge commit)" || { echo "FAIL STORY-001 não é DONE"; fail=1; }
grep -qE '^\| STORY-002-group \|.*\| DONE \| checkpoint em origin/main' <<< "${ALL}" && echo "ok   STORY-002 DONE (commit de grupo)" || { echo "FAIL STORY-002 não é DONE"; fail=1; }
grep -qE '^\| STORY-007-old \|.*\| OBSOLETE \|' <<< "${ALL}" && echo "ok   STORY-007 OBSOLETE" || { echo "FAIL STORY-007 não é OBSOLETE"; fail=1; }
grep -q 'forge: git-only' <<< "${OUT}" && echo "ok   forge git-only" || { echo "FAIL forge"; fail=1; }
bash "${SCRIPT}" --project "${R}" --json | head -1 | grep -q '"summary":"Backlog: 3 PENDING' \
    && echo "ok   json" || { echo "FAIL json"; fail=1; }

mkdir -p "${TMP}/.claude/.state/sess-a"; echo proj > "${TMP}/.claude/.state/sess-a/active-project"
( cd "${TMP}" && CLAUDE_CODE_SESSION_ID=sess-a bash "${SCRIPT}" ) | head -1 | grep -q "backlog-status: ${R} " \
    && echo "ok   umbrella: sub-projeto da sessão" || { echo "FAIL umbrella"; fail=1; }
( cd "${TMP}" && CLAUDE_CODE_SESSION_ID=sess-b bash "${SCRIPT}" 2>&1 || true ) | grep -q "umbrella sem sub-projeto" \
    && echo "ok   umbrella: outra sessão não herda" || { echo "FAIL umbrella herdou"; fail=1; }

written="$(find "${R}" "${TMP}/wt-003" "${TMP}/remote.git" -newer "${TMP}/marker" | head -5)"
[[ -z "${written}" ]] && echo "ok   nada escrito" || { echo "FAIL escreveu: ${written}"; fail=1; }

[[ "${fail}" -eq 0 ]] || { printf '\n%s\n' "${OUT}"; exit 1; }
