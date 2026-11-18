#!/usr/bin/env bash
#
# base-branch.sh — a branch de integração de um repo: para onde vai o MR e de onde nasce a
# branch de uma story. Cada repo tem a sua (main num, alpha noutro), e um nome fixo no prompt
# manda o MR para o lugar errado.
#
# Sem registro, regra (a mesma do catalog): entre as branches longas do origin, a de merge-base mais próximo
# de HEAD. A branch atual vence o empate — main e alpha no mesmo commit não dizem para onde vai
# o MR, o checkout diz. Uma feature branch nunca é base.
#
# Não faz fetch: quem chama decide se precisa do remoto atual.
#
# uso: base-branch.sh [dir]     imprime o nome (sem origin/); exit 1 se não achar

set -uo pipefail

DIR="${1:-.}"
cur="$(git -C "${DIR}" branch --show-current 2>/dev/null)"

# A branch de story grava de onde nasceu (tech-lead): essa resposta vale mais que a história,
# que não distingue duas bases no mesmo commit.
recorded="$(git -C "${DIR}" config "branch.${cur}.base" 2>/dev/null || true)"
if [[ -n "${cur}" && -n "${recorded}" ]]; then printf '%s\n' "${recorded}"; exit 0; fi
first=""
[[ "${cur}" =~ ^(main|master|trunk|develop|dev|next|alpha|beta|stable|release)$ ]] && first="origin/${cur}"

best="" bestn=""
for ref in ${first} origin/HEAD origin/main origin/master origin/trunk origin/develop origin/dev \
           origin/next origin/alpha origin/beta origin/stable origin/release; do
    git -C "${DIR}" rev-parse -q --verify "${ref}^{commit}" >/dev/null || continue
    mb="$(git -C "${DIR}" merge-base HEAD "${ref}" 2>/dev/null)" || continue
    n="$(git -C "${DIR}" rev-list --count "${mb}..HEAD")"
    if [[ -z "${bestn}" || "${n}" -lt "${bestn}" ]]; then best="${ref}"; bestn="${n}"; fi
done
[[ "${best}" == "origin/HEAD" ]] && best="$(git -C "${DIR}" rev-parse --abbrev-ref origin/HEAD)"
[[ -n "${best}" ]] || exit 1
printf '%s\n' "${best#origin/}"
