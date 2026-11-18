#!/usr/bin/env bash
#
# tree-status.sh — o `git status --porcelain` que decide se a árvore de uma story está limpa.
#
# As stories aprovadas e ainda não começadas ficam soltas em artifacts/stories/ do checkout
# (com backup em docs/stories-*), e cada uma entra na integração pelo MR dela. Numa story
# construída no próprio checkout, as outras estão na mesma árvore: o status cru as mostra, e
# a Check 4, o merge-request-creator e o git-merge-guard recusariam o merge — ou alguém as
# commitaria no MR errado. Aqui ficam de fora só os arquivos soltos de OUTRAS stories; os
# desta story, e qualquer outra mudança, continuam aparecendo.
#
# A story é a da branch (feat/<id> ou fix/<id>). Fora de uma branch de story, é o status cru.
#
# uso: tree-status.sh [tree]      vazio = limpa

set -uo pipefail

TREE="${1:-.}"
branch="$(git -C "${TREE}" branch --show-current 2>/dev/null)"
id=""
[[ "${branch}" =~ ^(feat|fix)/(STORY-.+)$ ]] && id="${BASH_REMATCH[2]}"

git -C "${TREE}" status --porcelain --untracked-files=all | while IFS= read -r line; do
    if [[ -n "${id}" && "${line}" == '?? artifacts/stories/'* ]]; then
        base="$(basename "${line:3}" .md | sed -E 's/-r[0-9]+$//; s/-(checkpoint|technical-analysis|code-analysis|ux-spec|test-report|qa-report|code-review|cost-report|impl-report[A-Za-z0-9_-]*)$//')"
        [[ "${base}" == STORY-* && "${base}" != "${id}" ]] && continue
    fi
    printf '%s\n' "${line}"
done
