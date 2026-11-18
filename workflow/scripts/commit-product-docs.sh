#!/usr/bin/env bash
#
# commit-product-docs.sh — versiona a camada de produto de um guarda-chuva.
#
# Num guarda-chuva (raiz cujos sub-diretórios são repos git próprios), visão, personas, NFRs,
# épicos e BACKLOG-SUMMARY descrevem o produto inteiro e moram na raiz. Nenhum MR de story
# passa por lá, então quem os escreve (product-owner, product-manager) roda isto ao terminar.
#
# Vários devs publicam na mesma branch da raiz, então antes de ler (--pull) e antes de publicar
# o script traz o que os outros já enviaram, por rebase. Cada development tem os próprios
# arquivos e o rebase é limpo; o mesmo arquivo editado por dois é conflito de verdade: o rebase
# é desfeito e o aviso diz qual.
#
# Projeto único: não faz nada — lá esses docs entram no commit da branch da story.
# Nunca é gate: qualquer problema vira aviso e exit 0. Roda da raiz da sessão.
#
# uso: commit-product-docs.sh <development-slug>   versiona e publica
#      commit-product-docs.sh --pull               só traz o que os outros publicaram

set -uo pipefail

warn() { printf 'product-docs: aviso: %s\n' "$*"; exit 0; }

DEV="${1:-}"
[[ -n "${DEV}" ]] || { echo "uso: commit-product-docs.sh <development-slug> | --pull" >&2; exit 1; }

subs=""
for d in */; do [[ -e "${d}.git" ]] && subs="${subs} ${d%/}"; done
if [[ -z "${subs}" ]]; then
    echo "product-docs: projeto único — os documentos seguem no commit da story"
    exit 0
fi

# Um .git que não é repo (esqueleto sem HEAD) ou um repo pai acima da raiz dão o mesmo
# resultado: commitar aqui não versionaria o que está nesta raiz.
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ "${top}" == "$(pwd -P)" ]] \
    || warn "a raiz do guarda-chuva não é um repositório git; a camada de produto fica sem versão. Para versionar: git init aqui e ponha no .gitignore os sub-projetos (${subs# })"

# Rebase sobre o upstream; em conflito, desfaz e avisa. Devolve 1 sem upstream.
syncUp() {
    git rev-parse -q --verify '@{u}' >/dev/null 2>&1 || return 1
    if ! git pull -q --rebase --autostash >/dev/null 2>&1; then
        local conflicted
        conflicted="$(git diff --name-only --diff-filter=U 2>/dev/null | paste -sd ' ')"
        git rebase --abort 2>/dev/null
        warn "outro dev publicou mudanças em ${conflicted:-arquivos} que este clone também mudou; nada foi enviado. Resolva com git pull --rebase na raiz"
    fi
    return 0
}

if [[ "${DEV}" == "--pull" ]]; then
    if syncUp; then echo "product-docs: raiz em dia com $(git rev-parse --abbrev-ref '@{u}')"
    else echo "product-docs: sem upstream; nada a trazer"; fi
    exit 0
fi

paths=()
for p in artifacts/product artifacts/epics; do [[ -d "${p}" ]] && paths+=("${p}"); done
# A lista de sub-projetos (instalador) é o que deixa um clone novo da raiz montar o guarda-chuva.
[[ -f subprojects.tsv ]] && paths+=(subprojects.tsv)
[[ ${#paths[@]} -gt 0 ]] || { echo "product-docs: nada em artifacts/product nem artifacts/epics"; exit 0; }

git add -- "${paths[@]}" || warn "git add falhou"
# Os arquivos, não os diretórios: um diretório vazio é pathspec que o git não conhece e
# derruba o commit. Com pathspec, o commit leva só isto, mesmo com outra coisa no stage.
mapfile -d '' files < <(git diff --cached --name-only -z -- "${paths[@]}")
if [[ ${#files[@]} -eq 0 ]]; then
    echo "product-docs: nada novo para versionar"
    exit 0
fi
git commit -q -m "docs(product): ${DEV}" -- "${files[@]}" || warn "git commit falhou; os arquivos ficaram no stage"
echo "product-docs: $(git log -1 --format='%h %s')"

if syncUp; then
    git push -q 2>/dev/null || warn "push falhou; o commit ficou só local"
    echo "product-docs: enviado para $(git rev-parse --abbrev-ref '@{u}')"
else
    echo "product-docs: sem upstream; o commit ficou só local"
fi
