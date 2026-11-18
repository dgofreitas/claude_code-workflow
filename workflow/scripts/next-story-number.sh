#!/usr/bin/env bash
#
# next-story-number.sh — o próximo número livre de story num repo.
#
# `ls artifacts/stories/` só vê esta máquina. Com vários devs no mesmo repo, as stories
# aprovadas e ainda não começadas de outro dev estão no backup dele (docs/stories-*), e as em
# andamento numa branch feat/fix já enviada — nenhuma no checkout local. Contar só o local dá a
# dois devs o mesmo número. Aqui entram o checkout, todas as branches do origin (após fetch) e
# os nomes das branches.
#
# Ainda sobra a janela entre dois PMs rodando ao mesmo tempo antes de qualquer backup; o slug no
# id mantém os arquivos distintos, e o número repetido aparece no Master como ambiguidade.
#
# uso: next-story-number.sh [dir]     imprime STORY-NNN

set -uo pipefail

DIR="${1:-.}"
SD="artifacts/stories"
git -C "${DIR}" fetch -q origin 2>/dev/null || true

max="$({
    ls "${DIR}/${SD}" 2>/dev/null
    git -C "${DIR}" for-each-ref --format='%(refname)' refs/remotes/origin refs/heads \
        | while read -r ref; do git -C "${DIR}" ls-tree --name-only "${ref}" "${SD}/" 2>/dev/null; done
    git -C "${DIR}" for-each-ref --format='%(refname:short)' refs/remotes/origin refs/heads
} | grep -oE 'STORY-[0-9]+' | sed 's/STORY-0*//' | grep -E '^[0-9]+$' | sort -n | tail -1)"

printf 'STORY-%03d\n' "$(( ${max:-0} + 1 ))"
