#!/usr/bin/env bash
#
# version-stories.sh — guarda no remoto as stories de um development assim que o GATE-PM as aprova.
#
# O PM escreve as stories no checkout, fora do git, e cada uma só entra na branch de integração
# pelo MR dela, quando é implementada. Até lá viviam só numa máquina: um `git clean` as apagava,
# e ninguém mais podia assumi-las. Isto as copia para a branch remota docs/stories-<dev>, que é
# só backup: sem MR e sem commit na branch de integração local.
#
# Não pôr as stories na branch de integração é de propósito:
# - com vários devs, o commit local diverge assim que outro MR é mergeado antes (o pull vira
#   merge local, e squash ou fast-forward nem fazem pull);
# - versionadas lá antes de começar, as stories pendentes de um dev aparecem no backlog dos
#   outros, que podem pegá-las;
# - o original continua solto no checkout, e o git recusa o pull que o sobrescreveria, mesmo
#   idêntico.
#
# O checkout não é tocado: o commit é feito num worktree temporário. Rodar de novo para o mesmo
# development soma na mesma branch. Nunca é gate: problema vira aviso e exit 0. Roda da raiz.
#
# uso: version-stories.sh --development <slug>

set -uo pipefail

readonly STORY_DIR="artifacts/stories"
readonly REPORT_RE='-(checkpoint|technical-analysis|code-analysis|ux-spec|test-report|qa-report|code-review|cost-report|impl-report[A-Za-z0-9_-]*)(-r[0-9]+)?\.md$'

usage() { echo "uso: version-stories.sh --development <slug>" >&2; exit 1; }
DEV=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --development)   [[ $# -ge 2 ]] || usage; DEV="$2"; shift 2 ;;
        --development=*) DEV="${1#*=}"; shift ;;
        *) usage ;;
    esac
done
[[ -n "${DEV}" ]] || usage
BR="docs/stories-${DEV}"

say()  { printf 'version-stories: %s\n' "$*"; }
warn() { printf 'version-stories: aviso: %s\n' "$*"; }

isLongLived() { [[ "$1" =~ ^(main|master|trunk|develop|dev|next|alpha|beta|stable|release)$ ]]; }

# Base da branch de backup: a branch de integração pela regra do catalog (merge-base mais
# próximo de HEAD entre as longas). Só define de onde a branch nasce; não há MR.
baseOf() {
    local dir="$1" cur first="" best="" bestn="" ref mb n
    cur="$(git -C "${dir}" branch --show-current)"
    isLongLived "${cur}" && first="origin/${cur}"
    for ref in ${first} origin/HEAD origin/main origin/master origin/trunk origin/develop origin/dev \
               origin/next origin/alpha origin/beta origin/stable origin/release; do
        git -C "${dir}" rev-parse -q --verify "${ref}^{commit}" >/dev/null || continue
        mb="$(git -C "${dir}" merge-base HEAD "${ref}" 2>/dev/null)" || continue
        n="$(git -C "${dir}" rev-list --count "${mb}..HEAD")"
        if [[ -z "${bestn}" || "${n}" -lt "${bestn}" ]]; then best="${ref}"; bestn="${n}"; fi
    done
    [[ "${best}" == "origin/HEAD" ]] && best="$(git -C "${dir}" rev-parse --abbrev-ref origin/HEAD)"
    printf '%s' "${best#origin/}"
}

# Stories (e, num projeto único, o BACKLOG-SUMMARY) do development fora do git ou alteradas.
# Relatórios ficam de fora: nascem na branch da story e vão no MR dela.
filesOf() {
    local dir="$1" st path
    while IFS= read -r st; do
        path="${st:3}"
        [[ "${path}" == *.md && ! "${path}" =~ ${REPORT_RE} ]] || continue
        if [[ "$(basename "${path}")" == "BACKLOG-SUMMARY-${DEV}.md" ]] \
            || sed -n '1,15p' "${dir}/${path}" 2>/dev/null | grep -qE "^development:[[:space:]]*\"?${DEV}\"?[[:space:]]*$"; then
            printf '%s\n' "${path}"
        fi
    done < <(git -C "${dir}" status --porcelain --untracked-files=all -- "${STORY_DIR}/")
}

versionOne() {
    local dir="$1" name="$2" base start tmp f
    local -a files
    mapfile -t files < <(filesOf "${dir}")
    [[ ${#files[@]} -gt 0 ]] || return 1

    git -C "${dir}" fetch -q origin 2>/dev/null || warn "${name}: fetch falhou; seguindo com o que há localmente"
    if git -C "${dir}" rev-parse -q --verify "refs/remotes/origin/${BR}" >/dev/null; then
        start="origin/${BR}"
    else
        base="$(baseOf "${dir}")"
        [[ -n "${base}" ]] || { warn "${name}: sem branch de integração em origin; ${#files[@]} arquivo(s) continuam só no checkout"; return 0; }
        start="origin/${base}"
    fi

    tmp="$(mktemp -d)"
    git -C "${dir}" worktree add -q --detach "${tmp}/wt" "${start}" 2>/dev/null \
        || { warn "${name}: não consegui criar o worktree temporário"; rmdir "${tmp}"; return 0; }
    for f in "${files[@]}"; do mkdir -p "${tmp}/wt/$(dirname "${f}")" && cp "${dir}/${f}" "${tmp}/wt/${f}"; done
    git -C "${tmp}/wt" add -- "${files[@]}"
    if git -C "${tmp}/wt" diff --cached --quiet; then
        say "${name}: ${#files[@]} arquivo(s) já iguais em ${BR}"
    elif git -C "${tmp}/wt" commit -q -m "docs(stories): backup de ${DEV}" -m "$(printf -- '- %s\n' "${files[@]}")" \
         && git -C "${tmp}/wt" push -q origin "HEAD:refs/heads/${BR}" 2>/dev/null; then
        say "${name}: ${#files[@]} arquivo(s) guardados em ${BR} (backup, sem MR; a story entra na integração pelo MR dela)"
    else
        warn "${name}: commit/push de ${BR} falhou; ${#files[@]} arquivo(s) continuam só no checkout"
    fi
    git -C "${dir}" worktree remove --force "${tmp}/wt" 2>/dev/null; rmdir "${tmp}" 2>/dev/null
    return 0
}

found=0
subs=()
for d in */; do [[ -e "${d}.git" ]] && subs+=("${d%/}"); done
if [[ ${#subs[@]} -eq 0 ]]; then
    git rev-parse --show-toplevel >/dev/null 2>&1 || { warn "não é repositório git"; exit 0; }
    versionOne "." "$(basename "$(pwd -P)")" && found=1
else
    for s in "${subs[@]}"; do versionOne "${s}" "${s}" && found=1; done
fi
# Silêncio seria lido como "versionado": um development errado ou um frontmatter fora do padrão
# dá zero arquivos, e isso precisa aparecer.
[[ "${found}" -eq 1 ]] || warn "nenhuma story com 'development: ${DEV}' fora do git — nada foi guardado. Confira o slug."
exit 0
