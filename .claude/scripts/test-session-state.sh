#!/usr/bin/env bash
#
# Fixture para o estado por sessão: git-merge-guard.js num umbrella com dois sub-repos
# (a branch decide o repo, não um arquivo compartilhado) e session-state.js (limpeza
# atrelada ao transcript, linha de retomada).

set -euo pipefail

HOOKS="$(cd "$(dirname "$0")/../.." && pwd)/workflow/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
U="${TMP}/umbrella"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

subrepo() {
    local name="$1"
    git init -q --bare "${TMP}/${name}.git"
    git init -q -b main "${U}/${name}"
    git -C "${U}/${name}" config user.email t@t; git -C "${U}/${name}" config user.name t
    git -C "${U}/${name}" remote add origin "${TMP}/${name}.git"
    git -C "${U}/${name}" commit -q --allow-empty -m init
    git -C "${U}/${name}" push -q -u origin main
}
branch() {   # branch publicada, limpa
    git -C "${U}/$1" checkout -q -b "$2"
    git -C "${U}/$1" commit -q --allow-empty -m "$2"
    git -C "${U}/$1" push -q -u origin "$2"
    git -C "${U}/$1" checkout -q main
}
guard() {    # $1 sessão, $2 comando
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"%s"}' "$2" "$1" \
        | CLAUDE_PROJECT_DIR="${U}" node "${HOOKS}/git-merge-guard.js"
}
state() { mkdir -p "${U}/.claude/.state/$1"; echo "$2" > "${U}/.claude/.state/$1/active-project"; }

mkdir -p "${U}"; git init -q -b main "${U}"
subrepo serverLic; subrepo docker-compose; subrepo teco
branch docker-compose feat/STORY-010-compose
branch serverLic feat/STORY-020-dup; branch docker-compose feat/STORY-020-dup

# O incidente: a sessão está em serverLic, a branch é do docker-compose.
state sess-a serverLic
check "branch de outro sub-projeto é validada no repo dela" \
    '[[ -z "$(guard sess-a "gh pr merge feat/STORY-010-compose --merge")" ]]'

git -C "${U}/docker-compose" checkout -q feat/STORY-010-compose
touch "${U}/docker-compose/sujo.txt"
check "árvore suja no repo dono da branch é negada" \
    'guard sess-a "gh pr merge feat/STORY-010-compose --merge" | grep -q "working tree suja"'
rm "${U}/docker-compose/sujo.txt"; git -C "${U}/docker-compose" checkout -q main

check "branch em dois sub-projetos: desempata pelo projeto da sessão" \
    '[[ -z "$(guard sess-a "gh pr merge feat/STORY-020-dup --merge")" ]]'
state sess-t teco
check "branch em dois sub-projetos, nenhum da sessão: nega" \
    'guard sess-t "gh pr merge feat/STORY-020-dup --merge" | grep -q "mais de um sub-projeto"'
check "branch que não existe: nega" \
    'guard sess-a "gh pr create --head feat/nao-existe --base main" | grep -q "não existe"'
check "sessão sem estado continua funcionando" \
    '[[ -z "$(guard sess-nova "gh pr merge feat/STORY-010-compose --merge")" ]]'

state sess-p serverLic
check "push direto na main do repo da sessão pede confirmação" \
    'guard sess-p "git push origin main" | grep -q "\"ask\""'

# ---------------------------------------------------------------- session-state.js
S="${U}/.claude/.state"
hook() { printf '{"session_id":"%s","transcript_path":"%s","source":"%s"}' "$1" "$2" "$3" \
    | CLAUDE_PROJECT_DIR="${U}" node "${HOOKS}/session-state.js"; }
old() { touch -d "$2 days ago" "${S}/$1"; }

touch "${TMP}/vivo.jsonl"
mkdir -p "${S}/morto" "${S}/recente" "${S}/vivo" "${S}/sem-registro-velho" "${S}/sem-registro-novo"
echo "${TMP}/apagado.jsonl" > "${S}/morto/transcript";   old morto 2
echo "${TMP}/apagado.jsonl" > "${S}/recente/transcript"
echo "${TMP}/vivo.jsonl"    > "${S}/vivo/transcript";    old vivo 40
old sem-registro-velho 40; old sem-registro-novo 10

out="$(hook sess-nova "${TMP}/nova.jsonl" startup)"
check "startup não imprime nada" '[[ -z "${out}" ]]'
check "registra o transcript da sessão" 'grep -qx "${TMP}/nova.jsonl" "${S}/sess-nova/transcript"'
check "apaga o estado cujo transcript sumiu" '[[ ! -d "${S}/morto" ]]'
check "mantém sessão recém-criada sem transcript ainda" '[[ -d "${S}/recente" ]]'
check "mantém sessão de 40 dias com transcript (resume depois de semanas)" '[[ -d "${S}/vivo" ]]'
check "apaga diretório sem registro com mais de 30 dias" '[[ ! -d "${S}/sem-registro-velho" ]]'
check "mantém diretório sem registro com 10 dias" '[[ -d "${S}/sem-registro-novo" ]]'

echo batch-auto > "${S}/vivo/exec-mode"; echo serverLic > "${S}/vivo/active-project"
echo '{"queue":["STORY-1","STORY-2","STORY-3"],"current":1}' > "${S}/vivo/batch-queue.json"
out="$(hook vivo "${TMP}/vivo.jsonl" resume)"
check "resume mostra projeto, modo e fila" \
    '[[ "${out}" == *"projeto: serverLic"* && "${out}" == *"modo: batch-auto"* && "${out}" == *"2 na fila"* ]]'
check "/clear começa do zero, sem linha" '[[ -z "$(hook sess-limpa "${TMP}/limpa.jsonl" clear)" ]]'
check "id inválido não cria nada" '[[ -z "$(hook "../fora" "${TMP}/x.jsonl" startup)" && ! -d "${U}/.claude/fora" ]]'

[[ "${fail}" -eq 0 ]]
