#!/usr/bin/env bash
#
# version-stories.sh — versiona as stories de um development assim que o GATE-PM as aprova.
#
# O PM escreve as stories no checkout, fora do git. Sem isto elas só entram numa branch
# quando o tech-lead começa cada uma — às vezes semanas depois —, e até lá um `git clean`
# as apaga, outra máquina não as vê e um worktree começa sem elas.
#
# Em cada projeto (num guarda-chuva, cada sub-projeto) com stories do development fora do
# git: commit na branch de integração local, push para docs/stories-<dev> e MR para ela.
# O commit fica no checkout de propósito: versionar numa branch à parte e deixar o original
# solto trava o `git pull` depois do merge, mesmo com o conteúdo idêntico. Assim o pull é
# um fast-forward.
#
# Com o checkout em outra branch, ou com commits locais que não são deste script, o commit
# vai para um worktree temporário e os originais ficam: o aviso diz quais apagar após o merge.
#
# Nunca é gate: qualquer problema vira aviso e exit 0. Roda da raiz da sessão.
#
# uso: version-stories.sh --development <slug>

set -uo pipefail

readonly STORY_DIR="artifacts/stories"
readonly TRAILER="Versioned-by: version-stories.sh"
readonly REPORT_RE='-(checkpoint|technical-analysis|code-analysis|ux-spec|test-report|qa-report|code-review|cost-report|impl-report[A-Za-z0-9_-]*)(-r[0-9]+)?\.md$'

DEV=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --development)   [[ $# -ge 2 ]] || { echo "uso: version-stories.sh --development <slug>" >&2; exit 1; }; DEV="$2"; shift 2 ;;
        --development=*) DEV="${1#*=}"; shift ;;
        *) echo "uso: version-stories.sh --development <slug>" >&2; exit 1 ;;
    esac
done
[[ -n "${DEV}" ]] || { echo "uso: version-stories.sh --development <slug>" >&2; exit 1; }
BR="docs/stories-${DEV}"

# Só uma branch longa é base: uma feature branch nunca é destino do MR destas stories.
isLongLived() { [[ "$1" =~ ^(main|master|trunk|develop|dev|next|alpha|beta|stable|release)$ ]]; }

say()  { printf 'version-stories: %s\n' "$*"; }
warn() { printf 'version-stories: aviso: %s\n' "$*"; }

# A branch de onde as stories saem: das longas de sempre, a de merge-base mais próximo de
# HEAD (a mesma regra do catalog). A branch atual vence o empate: main e alpha no mesmo
# commit não dizem para onde vai o MR, o checkout diz.
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
            || sed -n '1,15p' "${dir}/${path}" 2>/dev/null | grep -qx "development: ${DEV}"; then
            printf '%s\n' "${path}"
        fi
    done < <(git -C "${dir}" status --porcelain --untracked-files=all -- "${STORY_DIR}/")
}

openMr() {
    local dir="$1" base="$2" n="$3" url title body
    url="$(git -C "${dir}" remote get-url origin 2>/dev/null || true)"
    title="docs(stories): ${DEV}"
    body="Stories do development \`${DEV}\` aprovadas no GATE-PM (${n} arquivo(s)). Versionadas antes de qualquer uma começar, para não viverem só no checkout. Só documentos, nenhum código."
    if [[ "${url}" == *github* ]] && command -v gh >/dev/null 2>&1; then
        ( cd "${dir}" && gh pr list --head "${BR}" --state open --json url --jq '.[0].url' 2>/dev/null | grep . ) \
            || ( cd "${dir}" && gh pr create --head "${BR}" --base "${base}" --title "${title}" --body "${body}" 2>/dev/null | tail -1 )
    elif [[ "${url}" == *gitlab* ]] && command -v glab >/dev/null 2>&1; then
        ( cd "${dir}" && glab mr list --source-branch "${BR}" 2>/dev/null | grep -oE 'https://[^ ]+merge_requests/[0-9]+|![0-9]+' | head -1 | grep . ) \
            || ( cd "${dir}" && glab mr create --source-branch "${BR}" --target-branch "${base}" --title "${title}" --description "${body}" --yes 2>/dev/null \
                   | grep -oE 'https://[^ ]+merge_requests/[0-9]+' | head -1 )
    fi
}

versionOne() {
    local dir="$1" name="$2" base cur foreign tmp msg mr
    local -a files
    mapfile -t files < <(filesOf "${dir}")
    [[ ${#files[@]} -gt 0 ]] || return 0

    git -C "${dir}" fetch -q origin 2>/dev/null || warn "${name}: fetch falhou; seguindo com o que há localmente"
    base="$(baseOf "${dir}")"
    [[ -n "${base}" ]] || { warn "${name}: sem branch de integração em origin; ${#files[@]} arquivo(s) continuam fora do git"; return 0; }
    cur="$(git -C "${dir}" branch --show-current)"
    msg="$(printf 'docs(stories): %s\n\nStories aprovadas no GATE-PM, versionadas antes de qualquer uma começar.\n\n%s\n\n%s\n' \
        "${DEV}" "$(printf -- '- %s\n' "${files[@]}")" "${TRAILER}")"

    # Commits locais à frente da base que não são deste script iriam juntos no MR.
    foreign="$(git -C "${dir}" log --format='%(trailers:key=Versioned-by,valueonly,separator=%x2C)' "origin/${base}..HEAD" 2>/dev/null | grep -cv 'version-stories.sh')"

    if [[ "${cur}" == "${base}" ]] && isLongLived "${base}" && [[ "${foreign}" -eq 0 ]]; then
        git -C "${dir}" add -- "${files[@]}" || { warn "${name}: git add falhou"; return 0; }
        git -C "${dir}" commit -q -m "${msg}" -- "${files[@]}" || { warn "${name}: git commit falhou; os arquivos ficaram no stage"; return 0; }
        git -C "${dir}" push -q origin "HEAD:refs/heads/${BR}" 2>/dev/null \
            || { warn "${name}: push de ${BR} falhou; o commit ficou só em ${base} local"; return 0; }
        mr="$(openMr "${dir}" "${base}" "${#files[@]}")"
        say "${name}: ${#files[@]} arquivo(s) em ${base} local, push ${BR} → ${mr:-abra o MR de ${BR} para ${base}}"
        return 0
    fi

    tmp="$(mktemp -d)"
    if git -C "${dir}" rev-parse -q --verify "refs/heads/${BR}" >/dev/null; then
        git -C "${dir}" worktree add -q "${tmp}/wt" "${BR}" 2>/dev/null
    elif git -C "${dir}" rev-parse -q --verify "refs/remotes/origin/${BR}" >/dev/null; then
        git -C "${dir}" worktree add -q -b "${BR}" "${tmp}/wt" "origin/${BR}" 2>/dev/null
    else
        git -C "${dir}" worktree add -q -b "${BR}" "${tmp}/wt" "origin/${base}" 2>/dev/null
    fi || { warn "${name}: não consegui criar o worktree de ${BR}"; rmdir "${tmp}"; return 0; }
    for f in "${files[@]}"; do mkdir -p "${tmp}/wt/$(dirname "${f}")" && cp "${dir}/${f}" "${tmp}/wt/${f}"; done
    git -C "${tmp}/wt" add -- "${files[@]}" \
        && git -C "${tmp}/wt" commit -q -m "${msg}" -- "${files[@]}" \
        && git -C "${tmp}/wt" push -q -u origin "${BR}" 2>/dev/null \
        || warn "${name}: commit/push em ${BR} falhou"
    git -C "${dir}" worktree remove --force "${tmp}/wt" 2>/dev/null; rmdir "${tmp}" 2>/dev/null
    mr="$(openMr "${dir}" "${base}" "${#files[@]}")"
    say "${name}: ${#files[@]} arquivo(s) em ${BR} → ${mr:-abra o MR de ${BR} para ${base}}"
    local why="está em '${cur:-HEAD solto}'"
    [[ "${foreign}" -gt 0 ]] && why="tem ${foreign} commit(s) local(is) fora de origin/${base}"
    warn "${name}: o checkout ${why}, então os originais ficaram nele. Depois do merge, apague-os antes do pull (o git recusa sobrescrever arquivo solto, mesmo idêntico): $(printf '%s ' "${files[@]}")"
}

subs=()
for d in */; do [[ -e "${d}.git" ]] && subs+=("${d%/}"); done
if [[ ${#subs[@]} -eq 0 ]]; then
    git rev-parse --show-toplevel >/dev/null 2>&1 || { warn "não é repositório git"; exit 0; }
    versionOne "." "$(basename "$(pwd -P)")"
else
    for s in "${subs[@]}"; do versionOne "${s}" "${s}"; done
fi
exit 0
