#!/usr/bin/env bash
#
# backlog-status.sh — status de cada story, calculado do git e do forge. Só leitura.
#
# O status nunca é escrito à mão em lugar nenhum: sai daqui, a cada chamada.
#
#   DONE         PR/MR mergeado da branch da story, merge commit em <ref> com a branch,
#                ou checkpoint presente em <ref> (ele nasce na branch da story e só chega
#                a <ref> pelo merge). As checkboxes do checkpoint NÃO decidem: `[x] Merge
#                Request` quer dizer "PR criado", e checkpoints antigos ficam com `[ ]`
#                mesmo depois do merge.
#   OBSOLETE     outra story declara `supersedes: <id>` no frontmatter
#   IN-PROGRESS  PR/MR aberto, worktree ou branch local não mergeada, ou checkpoint fora de <ref>
#   PLANNED      só a technical-analysis
#   PENDING      só o arquivo da story
#   BLOCKED      PENDING/PLANNED com dependência aberta: uma story de `depends_on`, ou o épico
#                dela depende (`depends_on` no EPIC-x) de um épico com story não DONE. A ordem
#                vem do grafo, nunca do número. Começada mesmo assim, fica IN-PROGRESS com o
#                alerta BLOCKED-BY — e o GATE-MR espera.
#
# Nunca deriva DONE de `git log --grep STORY-XXX`: commits de grupo e commits que só
# adicionam o arquivo da story dão falso positivo e falso negativo.
#
# Exit codes:
#   0  ok
#   1  erro de uso
#   3  projeto não é repo git
#   5  <ref> não existe

set -euo pipefail

PROJECT=""
REF=""
DEV_FILTER=""
EPIC_FILTER=""
AGING_DAYS=14
FORMAT="table"
SHOW_ALL=0
FETCH=0
MINE=0
NO_DEPS=0

die() {
    local code="$1"; shift
    printf 'ERRO: %s\n' "$*" >&2
    exit "${code}"
}

usage() {
    cat >&2 <<'EOF'
uso: backlog-status.sh [--project DIR] [--ref REF] [--development SLUG] [--epic EPIC-X]
                       [--aging-days N] [--all] [--json] [--fetch] [--mine]

  --project DIR    sub-projeto (default: o desta sessão, em .claude/.state/<sessão>/active-project;
                   fora de sessão, num umbrella, é obrigatório)
  --ref REF        referência da verdade (default: origin/<branch de integração>, de base-branch.sh)
  --fetch          atualiza o origin antes: as branches feat/fix que outros devs já enviaram
                   (story reivindicada) só aparecem assim. Sem isto, nada é buscado
  --mine           só as stories cujo author é o seu e-mail do git (ou soltas neste checkout)
  --no-deps        não avalia dependências entre épicos/sub-projetos (uso interno, evita recursão)
  --all            inclui DONE e OBSOLETE na tabela (por default só entram nas contagens)
  --json           uma linha JSON por story, mais uma linha "summary"
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)     [[ $# -ge 2 ]] || usage; PROJECT="$2"; shift 2 ;;
        --project=*)   PROJECT="${1#*=}"; shift ;;
        --ref)         [[ $# -ge 2 ]] || usage; REF="$2"; shift 2 ;;
        --ref=*)       REF="${1#*=}"; shift ;;
        --development) [[ $# -ge 2 ]] || usage; DEV_FILTER="$2"; shift 2 ;;
        --development=*) DEV_FILTER="${1#*=}"; shift ;;
        --epic)        [[ $# -ge 2 ]] || usage; EPIC_FILTER="$2"; shift 2 ;;
        --epic=*)      EPIC_FILTER="${1#*=}"; shift ;;
        --aging-days)  [[ $# -ge 2 ]] || usage; AGING_DAYS="$2"; shift 2 ;;
        --aging-days=*) AGING_DAYS="${1#*=}"; shift ;;
        --all)         SHOW_ALL=1; shift ;;
        --json)        FORMAT="json"; shift ;;
        --fetch)       FETCH=1; shift ;;
        --mine)        MINE=1; shift ;;
        --no-deps)     NO_DEPS=1; shift ;;
        -h|--help)     usage ;;
        *)             die 1 "argumento desconhecido: $1" ;;
    esac
done

[[ "${AGING_DAYS}" =~ ^[0-9]+$ ]] || die 1 "--aging-days exige um número"

# Nunca um arquivo compartilhado entre sessões: outra sessão trocando de sub-projeto
# faria esta ler o backlog do repo errado.
if [[ -z "${PROJECT}" && -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    PROJECT="$(cat ".claude/.state/${CLAUDE_CODE_SESSION_ID}/active-project" 2>/dev/null || true)"
fi
if [[ -z "${PROJECT}" ]]; then
    subs=""
    for d in */; do [[ -e "${d}.git" ]] && subs="${subs} ${d%/}"; done
    [[ -z "${subs}" ]] || die 1 "umbrella sem sub-projeto definido: use --project <um de:${subs}>"
    PROJECT="."
fi

ROOT="$(git -C "${PROJECT}" rev-parse --show-toplevel 2>/dev/null)" \
    || die 3 "não é repo git: ${PROJECT}"

[[ "${FETCH}" -eq 1 ]] && { git -C "${ROOT}" fetch -q origin 2>/dev/null || true; }

# A verdade é a branch de integração do repo, não um nome fixo: num repo que integra em alpha,
# origin/main deixa de fora tudo o que foi mergeado e ainda não promovido.
if [[ -z "${REF}" ]]; then
    base="$(bash "$(dirname "${BASH_SOURCE[0]}")/base-branch.sh" "${ROOT}" 2>/dev/null || true)"
    REF="origin/${base:-main}"
    git -C "${ROOT}" rev-parse --verify -q "${REF}^{commit}" >/dev/null || REF="origin/main"
    git -C "${ROOT}" rev-parse --verify -q "${REF}^{commit}" >/dev/null || REF="main"
fi
git -C "${ROOT}" rev-parse --verify -q "${REF}^{commit}" >/dev/null \
    || die 5 "ref não existe: ${REF}"

readonly STORY_DIR="artifacts/stories"
# Nome do checkout principal, não de ROOT: com --project apontando para um worktree,
# ROOT é `.worktrees/api-STORY-x` e o summary diz `api`.
SUBPROJECT="$(basename "$(git -C "${ROOT}" worktree list --porcelain | sed -n '1s/^worktree //p')")"
readonly META_RE='^(type|title|created|development|epic|author):|^\*\*(Priority|Estimate)\*\*:'
ME="$(git -C "${ROOT}" config user.email 2>/dev/null || true)"

REF_DESC="$(git -C "${ROOT}" log -1 --format='%h %cs' "${REF}")"

# Pega o forge pelo remote. Sem CLI autenticada, cai para git-only e diz isso na saída.
forgeRecords() {
    local url
    url="$(git -C "${ROOT}" remote get-url origin 2>/dev/null || true)"
    if [[ "${url}" == *github* ]] && command -v gh >/dev/null 2>&1; then
        ( cd "${ROOT}" && gh pr list --state all --limit 1000 \
            --json number,state,headRefName,url \
            --jq '.[] | ["PR", .state, (.number|tostring), .headRefName, .url] | @tsv' \
            2>/dev/null ) && { printf 'FORGE\tgh\n'; return; }
    elif [[ "${url}" == *gitlab* ]] && command -v glab >/dev/null 2>&1; then
        # O GitLab devolve no máximo 100 por página: sem paginar, os MRs antigos somem e as
        # stories deles deixam de ser DONE.
        local page=1 got
        {
            while :; do
                got="$( cd "${ROOT}" && glab mr list --all --per-page 100 --page "${page}" -F json 2>/dev/null )" || break
                printf '%s\n' "${got}"
                [[ "$(printf '%s' "${got}" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).length))' 2>/dev/null)" == "100" ]] || break
                page=$((page + 1))
            done
        } | node -e '
                let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
                  for (const line of s.split("\n").filter(Boolean)) for (const m of JSON.parse(line)) {
                    const st = { merged: "MERGED", opened: "OPEN" }[m.state] || "CLOSED";
                    console.log(["PR", st, m.iid, m.source_branch, m.web_url].join("\t"));
                  }
                  console.log("FORGE\tglab");
                });' 2>/dev/null && return
    fi
    printf 'FORGE\tgit-only\n'
}

# Os `depends_on` de um frontmatter (lista inline ou em linhas `- x`), um id por linha.
fmDeps() {
    awk 'NR == 1 { if ($0 != "---") exit; next }
         $0 == "---" { exit }
         /^[A-Za-z_]+:/ { on = ($0 ~ /^depends_on:/) }
         on' "$1" 2>/dev/null \
        | grep -oE '([A-Za-z0-9._-]+/)?(STORY|EPIC)-[A-Za-z0-9._-]*[A-Za-z0-9]' || true
}

# Dependências que atravessam esta árvore: épicos (na raiz, com o PO) e stories de outro
# sub-projeto. Para cada épico do qual algum outro depende, as stories dele saem do summary do
# development dele — onde quer que tenham sido escritas, por quem for — e o status de cada uma
# vem do sub-projeto dela (uma chamada com --no-deps por sub-projeto, não por story).
epicDeps() {
    # Sem set -e aqui: um épico citado e ainda sem arquivo, ou um grep sem resultado, é uma
    # dependência aberta — nunca motivo para parar a coleta e perder o resto.
    local -; set +e
    local f e d dev sum line sub id want=() subs=()
    local -A need=() isSub=()
    for d in */; do if [[ -e "${d}.git" ]]; then isSub["${d%/}"]=1; fi; done
    for f in artifacts/epics/EPIC-*.md; do
        [[ -e "${f}" ]] || continue
        e="$(basename "${f}" .md)"
        printf 'EPFILE\t%s\n' "${e}"
        while IFS= read -r d; do printf 'EPDEP\t%s\t%s\n' "${e}" "${d}"; want+=("${d}"); done < <(fmDeps "${f}" | grep '^EPIC-')
    done
    # Stories que dependem de um épico inteiro, ou de uma story de outro sub-projeto.
    while IFS= read -r d; do
        case "${d}" in
            EPIC-*) want+=("${d}") ;;
            */STORY-*) need["${d%%/*}"]=1 ;;
        esac
    done < <({ git -C "${ROOT}" grep -h -A8 -E '^depends_on:' "${REF}" -- "${STORY_DIR}/" 2>/dev/null || true
               ( cd "${ROOT}" && grep -h -A8 -E '^depends_on:' "${STORY_DIR}"/*.md 2>/dev/null ) || true; } \
             | grep -oE '([A-Za-z0-9._-]+/)?(STORY|EPIC)-[A-Za-z0-9._-]*[A-Za-z0-9]' | sort -u)
    for d in $(printf '%s\n' "${want[@]}" | sort -u); do
        f="artifacts/epics/${d}.md"
        dev="$(sed -n '1,20p' "${f}" 2>/dev/null | sed -n 's/^development:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' | head -1)"
        [[ -n "${dev}" ]] || dev="${d#EPIC-}"
        sum=""
        for f in "artifacts/epics/BACKLOG-SUMMARY-${dev}.md" "${ROOT}/${STORY_DIR}/BACKLOG-SUMMARY-${dev}.md"; do
            if [[ -f "${f}" ]]; then sum="${f}"; break; fi
        done
        [[ -n "${sum}" ]] || { printf 'EPKNOWN\t%s\t0\n' "${d}"; continue; }
        printf 'EPKNOWN\t%s\t1\n' "${d}"
        while IFS= read -r line; do
            id="$(grep -oE 'STORY-[A-Za-z0-9._-]*[A-Za-z0-9]' <<<"${line}" | head -1)"
            [[ -n "${id}" ]] || continue
            sub="."
            while IFS= read -r c; do
                c="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/`//g' <<<"${c}")"
                if [[ -n "${c}" && -n "${isSub[${c}]:-}" ]]; then sub="${c}"; break; fi
            done < <(tr '|' '\n' <<<"${line}")
            printf 'EPST\t%s\t%s\t%s\n' "${d}" "${sub}" "${id}"
            if [[ "${sub}" != "." && "${sub}" != "${SUBPROJECT}" ]]; then need["${sub}"]=1; fi
        done < <(grep -E '^\|.*STORY-' "${sum}")
    done
    for sub in "${!need[@]}"; do
        [[ -z "${sub}" || "${sub}" == "${SUBPROJECT}" || -z "${isSub[${sub}]:-}" ]] && continue
        bash "${BASH_SOURCE[0]}" --project "${sub}" --all --json --no-deps 2>/dev/null \
            | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{for(const l of s.split("\n")){if(!l)continue;let o;try{o=JSON.parse(l)}catch(e){continue}if(o.id)console.log(["XST",process.argv[1],o.id,o.status].join("\t"))}})' "${sub}" \
            || true
    done
}

devOf() { local b; b="$(basename "$1" .md)"; [[ "${b}" == BACKLOG-SUMMARY-* ]] && printf '%s' "${b#BACKLOG-SUMMARY-}"; }
sumIds() { { grep -o -E 'STORY(-[0-9]+)+' || true; } | sed "s/^/SUM\t$1\t/"; }

collect() {
    printf 'TODAY\t%s\n' "$(date +%Y-%m-%d)"

    git -C "${ROOT}" ls-tree --name-only "${REF}" "${STORY_DIR}/" \
        | sed 's/^/F\tref\t/'

    git -C "${ROOT}" grep -n -E "${META_RE}" "${REF}" -- "${STORY_DIR}/" 2>/dev/null \
        | sed "s|^${REF}:|M\t|" || true
    git -C "${ROOT}" grep -n -A8 -E '^supersedes:' "${REF}" -- "${STORY_DIR}/" 2>/dev/null \
        | sed "s|^${REF}:|SUP\t|" || true
    git -C "${ROOT}" grep -n -A8 -E '^depends_on:' "${REF}" -- "${STORY_DIR}/" 2>/dev/null \
        | sed "s|^${REF}:|DEP\t|" || true

    # Cada worktree: arquivos rastreados na branch dele e os não versionados. O checkout
    # principal pode estar sujo e atrasado — é justamente onde moram os não versionados.
    # Stories aprovadas ficam soltas no checkout até começarem, com cópia em docs/stories-<dev>
    # (version-stories.sh). Solta e idêntica ao backup não é UNTRACKED: está guardada.
    local backups
    backups="$(git -C "${ROOT}" for-each-ref --format='%(refname)' 'refs/remotes/origin/docs/stories-*' \
        | while read -r ref; do git -C "${ROOT}" ls-tree -r "${ref}" -- "${STORY_DIR}/"; done | awk '{print $3}')"

    local wt branch f
    while IFS=$'\t' read -r wt branch; do
        printf 'WT\t%s\t%s\n' "${wt}" "${branch}"
        [[ -d "${wt}/${STORY_DIR}" ]] || continue
        git -C "${wt}" ls-files -- "${STORY_DIR}/" | sed "s|^|F\twt:${wt}\t|"
        while IFS= read -r f; do
            printf 'F\tuntracked:%s\t%s\n' "${wt}" "${f}"
            [[ -n "${backups}" ]] && grep -qxF "$(git -C "${wt}" hash-object "${f}")" <<<"${backups}" \
                && printf 'BK\t%s\n' "${f}"
        done < <(git -C "${wt}" ls-files --others --exclude-standard -- "${STORY_DIR}/")
        ( cd "${wt}" && grep -n -H -E "${META_RE}" "${STORY_DIR}"/*.md 2>/dev/null ) \
            | sed 's/^/M\t/' || true
        ( cd "${wt}" && grep -n -H -A8 -E '^supersedes:' "${STORY_DIR}"/*.md 2>/dev/null ) \
            | sed 's/^/SUP\t/' || true
        ( cd "${wt}" && grep -n -H -A8 -E '^depends_on:' "${STORY_DIR}"/*.md 2>/dev/null ) \
            | sed 's/^/DEP\t/' || true
    done < <(git -C "${ROOT}" worktree list --porcelain | awk '
        /^worktree / { wt = substr($0, 10); br = "" }
        /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
        /^$/         { if (wt != "") print wt "\t" br; wt = "" }
        END          { if (wt != "") print wt "\t" br }')

    git -C "${ROOT}" log --merges --format=%s "${REF}" \
        | grep -oE '(feat|fix)/[A-Za-z0-9._-]+' | sed 's/^/MC\t/' || true

    git -C "${ROOT}" for-each-ref --format='%(refname:short)' --no-merged="${REF}" \
        refs/heads/feat refs/heads/fix | sed 's/^/LB\t/' || true
    # A branch que outro dev já enviou: a story está reivindicada, mesmo sem MR (tech-lead faz o
    # push ao criá-la). Só aparece com --fetch, ou se um fetch recente já a trouxe. Sem
    # --no-merged: recém-criada, ela ainda aponta para um commit da base e contaria como mergeada.
    # A mergeada de fato continua DONE — o DONE vem antes do IN-PROGRESS.
    git -C "${ROOT}" for-each-ref --format='%(refname:short)' \
        refs/remotes/origin/feat refs/remotes/origin/fix | sed 's|^origin/||; s/^/RB\t/' || true

    # Ids citados nos BACKLOG-SUMMARY, com o development de cada um (o nome do arquivo). A story
    # só conta como listada no summary do PRÓPRIO development: números se repetem, e a 084 de
    # outro dev, no summary dele, calaria o alerta da nossa. Summary sem development (legado)
    # vale para qualquer story.
    local p
    while IFS= read -r p; do
        git -C "${ROOT}" show "${REF}:${p}" 2>/dev/null | sumIds "$(devOf "${p}")"
    done < <(git -C "${ROOT}" ls-tree --name-only "${REF}" "${STORY_DIR}/" | grep '/BACKLOG-SUMMARY[^/]*\.md$')
    while read -r wt; do
        for p in "${wt}/${STORY_DIR}"/BACKLOG-SUMMARY*.md; do
            [[ -e "${p}" ]] && sumIds "$(devOf "${p}")" < "${p}"
        done
    done < <(git -C "${ROOT}" worktree list --porcelain | sed -n 's/^worktree //p')
    # Num guarda-chuva o summary é um por development, na raiz, e lista stories de vários
    # sub-projetos. Só conta a linha cuja célula de sub-projeto é este.
    if [[ "$(pwd -P)" != "${ROOT}" ]]; then
        for p in artifacts/epics/BACKLOG-SUMMARY*.md; do
            [[ -e "${p}" ]] || continue
            awk -F'|' -v want="${SUBPROJECT}" '{
                for (i = 2; i < NF; i++) { c = $i; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == want) { print; next } }
            }' "${p}" | sumIds "$(devOf "${p}")"
        done
    fi

    [[ "${NO_DEPS}" -eq 1 ]] || epicDeps
    forgeRecords
}

collect | awk -F'\t' -v devf="${DEV_FILTER}" -v epicf="${EPIC_FILTER}" -v me="${ME}" -v mine="${MINE}" -v self="${SUBPROJECT}" \
    -v aging="${AGING_DAYS}" -v showall="${SHOW_ALL}" -v fmt="${FORMAT}" \
    -v root="${ROOT}" -v ref="${REF}" -v refdesc="${REF_DESC}" '

# Dias desde a época civil, sem mktime (que só o gawk tem).
function days(d,   y, m, dd, era, yoe, doy, doe) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return -1
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m <= 2) y--
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe
}

function basename(p) { sub(/.*\//, "", p); sub(/\.md$/, "", p); return p }

# Mesma regra strip-and-dedupe do Master. Devolve "" para o que não é story.
function baseOf(name,   b) {
    b = name
    sub(/-r[0-9]+$/, "", b)
    sub(/-(checkpoint|technical-analysis|code-analysis|ux-spec|test-report|qa-report|code-review|cost-report|impl-report[A-Za-z0-9_-]*)$/, "", b)
    if (b !~ /^STORY-/) return ""
    return b
}

function kindOf(name, b) {
    if (name == b) return "story"
    if (name ~ /-checkpoint$/) return "checkpoint"
    if (name ~ /-technical-analysis$/) return "analysis"
    return "report"
}

function clean(v) {
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    gsub(/^"|"$/, "", v)
    gsub(/\[\[|\]\]/, "", v)
    return v
}

# Branch, ou id curto citado num supersedes, para o id da story. O mais longo vence,
# com fronteira em "-": feat/STORY-006-3-x nunca cai em STORY-006-35.
function resolve(name,   c, k, hit, n) {
    sub(/^(feat|fix)\//, "", name)
    c = name
    while (1) {
        if (c in ids) return c
        if (c !~ /-/) break
        sub(/-[^-]*$/, "", c)
        if (c !~ /^STORY-/) break
    }
    n = 0
    for (k in ids) if (index(k, name "-") == 1) { hit = k; n++ }
    return n == 1 ? hit : ""
}

function shortId(id) { match(id, /^STORY(-[0-9]+)+/); return substr(id, 1, RLENGTH) }

function joinw(a, b) { return b == "" ? a : (a == "" ? b : a ", " b) }

# Status de uma dependência. Neste repo vem do cálculo desta mesma chamada; noutro sub-projeto,
# da chamada --no-deps feita para ele. Não encontrada = não DONE (DONE estaria na base).
function depStatus(sp, tok,   t, k, kk, hit, n) {
    if (sp == "" || sp == "." || sp == self) {
        t = resolve(tok); if (t != "") return stat[t]
        # Sem arquivo aqui, a story pode viver só na branch de quem a começou (enviada ou local).
        for (k in remoteBranch) { t = k; sub(/^(feat|fix)\//, "", t); if (t == tok || index(t, tok "-") == 1) return "IN-PROGRESS" }
        for (k in localBranch)  { t = k; sub(/^(feat|fix)\//, "", t); if (t == tok || index(t, tok "-") == 1) return "IN-PROGRESS" }
        return ""
    }
    if ((sp, tok) in xst) return xst[sp, tok]
    n = 0
    for (k in xst) { split(k, kk, SUBSEP); if (kk[1] == sp && (index(kk[2], tok "-") == 1 || shortId(kk[2]) == tok)) { hit = xst[k]; n++ } }
    return n == 1 ? hit : ""
}

# Um épico está concluído quando toda story do summary dele está DONE (ou OBSOLETE).
function epicBlock(D,   k, s, open, tot) {
    if (D in epCycle) return D " (ciclo entre épicos)"
    if (!epKnown[D] || epStN[D] == 0) return D " (sem stories ainda)"
    open = 0; tot = epStN[D]
    for (k = 1; k <= tot; k++) { s = depStatus(epStSub[D, k], epStId[D, k]); if (s != "DONE" && s != "OBSOLETE") open++ }
    return open ? D " (" open " de " tot " abertas)" : ""
}

function blockers(id,   k, tok, sp, s, why, e, j) {
    why = ""
    for (k = 1; k <= depN[id]; k++) {
        tok = dep[id, k]; sp = ""
        if (index(tok, "/")) { sp = substr(tok, 1, index(tok, "/") - 1); tok = substr(tok, index(tok, "/") + 1) }
        if (tok ~ /^EPIC-/) { why = joinw(why, epicBlock(tok)); continue }
        s = depStatus(sp, tok)
        if (s != "DONE" && s != "OBSOLETE") why = joinw(why, (sp != "" ? sp "/" : "") tok " (" (s == "" ? "não encontrada" : s) ")")
    }
    e = meta[id, "epic", "s"]; if (e == "") e = meta[id, "epic", "c"]
    for (j = 1; j <= epDepN[e]; j++) why = joinw(why, epicBlock(epDep[e, j]))
    return why
}

function jstr(s) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, " ", s)
    return "\"" s "\""
}

function addWhere(id, w) { where[id] = (id in where) ? where[id] ", " w : w }
function addAlert(id, a) { if (index("," alert[id] ",", "," a ",") == 0) alert[id] = (alert[id] == "") ? a : alert[id] "," a }

$1 == "TODAY" { today = days($2); todayStr = $2; next }
$1 == "FORGE" { forge = $2; next }
$1 == "F" {
    loc = $2; path = $3
    if (path !~ /\.md$/) next
    name = basename(path); b = baseOf(name)
    if (b == "") next
    k = kindOf(name, b)
    if (k == "story" || k == "checkpoint") ids[b] = 1
    if (loc == "ref") { inRef[path] = 1; has[b, k, "ref"] = 1; next }
    if (path in inRef) next
    if (loc ~ /^untracked:/) { has[b, k, "untracked"] = 1; untrackedAt[b, k] = substr(loc, 11) }
    else has[b, k, "branch"] = 1
    if (k == "checkpoint") addWhere(b, "checkpoint em " basename(substr(loc, index(loc, ":") + 1)))
    next
}
$1 == "M" {
    # path:linha:conteúdo
    rest = $2; for (i = 3; i <= NF; i++) rest = rest "\t" $i
    if (!match(rest, /:[0-9]+:/)) next
    path = substr(rest, 1, RSTART - 1); ln = substr(rest, RSTART + 1, RLENGTH - 2) + 0
    line = substr(rest, RSTART + RLENGTH)
    name = basename(path); b = baseOf(name)
    if (b == "") next
    k = kindOf(name, b)
    if (k != "story" && k != "checkpoint") next
    if (line ~ /^\*\*Priority\*\*:/) { key = "priority"; v = line; sub(/^[^:]*:/, "", v) }
    else if (line ~ /^\*\*Estimate\*\*:/) { key = "estimate"; v = line; sub(/^[^:]*:/, "", v) }
    else { if (ln > 40) next; key = line; sub(/:.*/, "", key); v = line; sub(/^[^:]*:/, "", v) }
    # Story ganha do checkpoint; o primeiro valor visto (de <ref>) ganha dos worktrees.
    slot = (k == "story") ? "s" : "c"
    if (!((b, key, slot) in meta)) meta[b, key, slot] = clean(v)
    next
}
$1 == "SUP" {
    rest = $2; for (i = 3; i <= NF; i++) rest = rest "\t" $i
    if (rest == "--") { supOpen = ""; next }
    # Linha casada vem como path:N:, linha de contexto (-A) como path-N-.
    if (!match(rest, /\.md[:-][0-9]+[:-]/)) next
    path = substr(rest, 1, RSTART + 2); line = substr(rest, RSTART + RLENGTH)
    name = basename(path); b = baseOf(name)
    if (b == "" || name != b) next
    if (line ~ /^supersedes:/) { supOpen = path; sub(/^supersedes:/, "", line) }
    else if (supOpen != path || line !~ /^[ \t]*-/) { supOpen = ""; next }
    while (match(line, /STORY-[A-Za-z0-9._-]*[A-Za-z0-9]/)) {
        supPending[substr(line, RSTART, RLENGTH)] = b
        line = substr(line, RSTART + RLENGTH)
    }
    next
}
$1 == "DEP" {
    rest = $2; for (i = 3; i <= NF; i++) rest = rest "\t" $i
    if (rest == "--") { depOpen = ""; next }
    if (!match(rest, /\.md[:-][0-9]+[:-]/)) next
    path = substr(rest, 1, RSTART + 2); line = substr(rest, RSTART + RLENGTH)
    name = basename(path); b = baseOf(name)
    if (b == "" || name != b) next
    if (line ~ /^depends_on:/) { depOpen = path; sub(/^depends_on:/, "", line) }
    else if (depOpen != path || line !~ /^[ \t]*-/) { depOpen = ""; next }
    while (match(line, /([A-Za-z0-9._-]+\/)?(STORY|EPIC)-[A-Za-z0-9._-]*[A-Za-z0-9]/)) {
        tok = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        if (!((b, tok) in depSeen)) { depSeen[b, tok] = 1; dep[b, ++depN[b]] = tok }
    }
    next
}
$1 == "EPFILE"  { epFile[$2] = 1; next }
$1 == "EPDEP"   { epDep[$2, ++epDepN[$2]] = $3; next }
$1 == "EPKNOWN" { epKnown[$2] = $3 + 0; next }
$1 == "EPST"    { k = ++epStN[$2]; epStSub[$2, k] = $3; epStId[$2, k] = $4; next }
$1 == "XST"     { xst[$2, $3] = $4; next }
$1 == "WT" { if ($3 ~ /^(feat|fix)\//) wtBranch[$3] = $2; next }
$1 == "MC" { mergedBranch[$2] = "merge commit"; next }
$1 == "LB" { localBranch[$2] = 1; next }
$1 == "RB" { remoteBranch[$2] = 1; next }
$1 == "SUM" { inDev[$2, $3] = 1; inAny[$3] = 1; if ($2 == "") inLegacy[$3] = 1; next }
$1 == "BK" { backed[basename($2)] = 1; next }
$1 == "PR" {
    if ($2 == "MERGED") prMerged[$4] = "PR #" $3
    else if ($2 == "OPEN") prOpen[$4] = "PR #" $3 " aberto"
    next
}

END {
    # Anexo com nome de story (`-baseline`, `-spike`, `-test-report-T2`) não é story: sem
    # checkpoint, só conta o arquivo cujo `type:` diz story — ou, sem frontmatter, que tem Priority.
    # Sai antes de resolver branches, para nenhuma branch cair num anexo.
    for (id in ids) {
        ty = meta[id, "type", "s"]
        if (!has[id, "checkpoint", "ref"] && !has[id, "checkpoint", "branch"] && !has[id, "checkpoint", "untracked"] \
            && ty !~ /^(story|bugfix|hotfix)$/ && !(ty == "" && meta[id, "priority", "s"] != "")) ghost[id] = 1
    }
    for (id in ghost) delete ids[id]

    # Checkpoint com id curto (`STORY-005-47-checkpoint`) de story com slug: se só uma story
    # começa por ele, o checkpoint é dela. Sem isso, a story em andamento sairia PENDING.
    for (id in ids) if (!has[id, "story", "ref"] && !has[id, "story", "branch"] && !has[id, "story", "untracked"]) shortOnly[id] = 1
    for (id in shortOnly) {
        n = 0
        for (k in ids) if (!(k in shortOnly) && index(k, id "-") == 1) { hit = k; n++ }
        if (n != 1) continue
        split("ref branch untracked", locs, " ")
        for (i = 1; i <= 3; i++) for (j = 1; j <= 2; j++) {
            kk = (j == 1) ? "checkpoint" : "analysis"
            if (has[id, kk, locs[i]]) has[hit, kk, locs[i]] = 1
        }
        if (id in where) addWhere(hit, where[id])
        delete ids[id]
    }

    for (s in supPending) { t = resolve(s); if (t != "" && t != supPending[s]) obsoleteBy[t] = supPending[s] }

    for (br in prMerged)     { id = resolve(br); if (id != "") { done[id] = 1; addWhere(id, prMerged[br]) } }
    for (br in mergedBranch) { id = resolve(br); if (id != "" && !(id in done)) { done[id] = 1; addWhere(id, "merge commit") } }
    for (id in ids) if (!(id in done) && has[id, "checkpoint", "ref"]) { done[id] = 1; addWhere(id, "checkpoint em " ref) }

    for (br in prOpen)      { id = resolve(br); if (id != "") { active[id] = 1; addWhere(id, prOpen[br]) } }
    for (br in wtBranch)    { id = resolve(br); if (id != "") { active[id] = 1; wtOf[id] = wtBranch[br]; addWhere(id, "worktree " basename(wtBranch[br])) } }
    for (br in localBranch) { id = resolve(br); if (id != "" && !(id in wtOf)) { active[id] = 1; addWhere(id, "branch " br) } }
    for (br in remoteBranch) { id = resolve(br); if (id != "" && !(id in active)) { active[id] = 1; addWhere(id, "branch remota " br) } }

    for (id in ids) {
        if (id in done)                  stat[id] = "DONE"
        else if (id in obsoleteBy)       { stat[id] = "OBSOLETE"; addWhere(id, "supersedes em " obsoleteBy[id]) }
        else if (id in active)           stat[id] = "IN-PROGRESS"
        else if (has[id, "checkpoint", "branch"] || has[id, "checkpoint", "untracked"]) stat[id] = "IN-PROGRESS"
        else if (has[id, "analysis", "ref"] || has[id, "analysis", "branch"] || has[id, "analysis", "untracked"]) stat[id] = "PLANNED"
        else                             stat[id] = "PENDING"
    }

    # Ciclo entre épicos (A depende de B que depende de A): ninguém começaria nunca. Fecho
    # transitivo do grafo, que é pequeno.
    for (a in epDepN) for (j = 1; j <= epDepN[a]; j++) reach[a, epDep[a, j]] = 1
    for (it = 0; it < 50; it++) {
        grew = 0
        for (k in reach) { split(k, ab, SUBSEP); for (j = 1; j <= epDepN[ab[2]]; j++) if (!((ab[1], epDep[ab[2], j]) in reach)) { reach[ab[1], epDep[ab[2], j]] = 1; grew = 1 } }
        if (!grew) break
    }
    for (a in epDepN) if ((a, a) in reach) { epCycle[a] = 1; cycles = joinw(cycles, a) }

    # Dependência aberta: quem não começou fica BLOCKED; quem já começou (empilhada) segue
    # IN-PROGRESS com alerta, e o GATE-MR espera. Avaliado sobre o status base, antes dos filtros.
    for (id in ids) {
        if (stat[id] == "DONE" || stat[id] == "OBSOLETE") continue
        why = blockers(id)
        if (why == "") continue
        blockedBy[id] = why
        if (stat[id] == "PENDING" || stat[id] == "PLANNED") stat[id] = "BLOCKED"
    }

    for (id in ids) {
        title = meta[id, "title", "s"];       if (title == "") title = meta[id, "title", "c"]
        dev   = meta[id, "development", "s"]; if (dev == "")   dev   = meta[id, "development", "c"]
        epic  = meta[id, "epic", "s"];        if (epic == "")  epic  = meta[id, "epic", "c"]
        if (devf != "" && dev != devf) continue
        if (epicf != "" && epic != epicf) continue
        # Seu: author é o seu e-mail; sem author (story anterior ao campo), só se está solta
        # neste checkout — só quem a escreveu aqui a tem fora do git.
        author = meta[id, "author", "s"]
        if (mine && !(author == me || (author == "" && has[id, "story", "untracked"]))) continue

        pr = meta[id, "priority", "s"]; gsub(/^[* ]+/, "", pr)
        if (pr ~ /^[Mm]ust/) { pr = "Must"; prRank = 1 }
        else if (pr ~ /^[Ss]hould/) { pr = "Should"; prRank = 2 }
        else if (pr ~ /^[Cc]ould/) { pr = "Could"; prRank = 3 }
        else if (pr ~ /^[Ww]on/) { pr = "Wont"; prRank = 4 }
        else { pr = "-"; prRank = 5 }
        est = meta[id, "estimate", "s"]; sub(/[ (].*/, "", est); if (est == "") est = "-"
        created = meta[id, "created", "s"]

        st = stat[id]
        if (id in blockedBy) {
            addWhere(id, "espera " blockedBy[id])
            if (st == "IN-PROGRESS") addAlert(id, "BLOCKED-BY")
        }

        if (has[id, "story", "untracked"] && !has[id, "story", "ref"] && !has[id, "story", "branch"]) {
            if (id in backed) addWhere(id, "backup em docs/stories"); else addAlert(id, "UNTRACKED")
        }
        if (has[id, "story", "branch"] && !has[id, "story", "ref"]) addAlert(id, "NOT-ON-REF")
        sid = shortId(id)
        listed = (dev != "") ? (((dev, sid) in inDev) || (sid in inLegacy)) : (sid in inAny)
        if (st != "DONE" && st != "OBSOLETE" && !listed) addAlert(id, "NOT-IN-SUMMARY")
        if (st == "DONE" && (id in wtOf)) addAlert(id, "STALE-WORKTREE")
        age = (created != "") ? today - days(created) : -1
        if (pr == "Must" && (st == "PENDING" || st == "PLANNED") && age > aging) addAlert(id, "MUST-HAVE-AGING")

        count[st]++
        if (pr == "Must" && (st == "PENDING" || st == "PLANNED")) { mustN[st]++; must[++nmust] = shortId(id) }

        stRank = (st == "IN-PROGRESS") ? 1 : (st == "PENDING") ? 2 : (st == "PLANNED") ? 3 : (st == "BLOCKED") ? 4 : (st == "OBSOLETE") ? 5 : 6
        if (!showall && (st == "DONE" || st == "OBSOLETE")) continue
        w = (id in where) ? where[id] : "-"
        a = (alert[id] == "") ? "-" : alert[id]
        if (fmt == "json")
            row = "{\"id\":" jstr(id) ",\"title\":" jstr(title) ",\"priority\":" jstr(pr) ",\"estimate\":" jstr(est) \
                  ",\"status\":" jstr(st) ",\"where\":" jstr(w) ",\"alerts\":" jstr(a) ",\"development\":" jstr(dev) \
                  ",\"created\":" jstr(created) ",\"author\":" jstr(author) ",\"blocked_by\":" jstr(blockedBy[id]) "}"
        else {
            if (length(title) > 60) title = substr(title, 1, 57) "..."
            gsub(/\|/, "/", title)
            row = "| " id " | " title " | " pr " | " est " | " st " | " w " | " a " |"
        }
        rows[++nrows] = stRank "\t" prRank "\t" id "\t" row
    }

    for (i = 2; i <= nmust; i++) for (j = i; j > 1 && must[j - 1] > must[j]; j--) { t = must[j]; must[j] = must[j - 1]; must[j - 1] = t }
    for (i = 1; i <= nmust; i++) mustList = mustList (i > 1 ? ", " : "") must[i]
    line = "Backlog: " count["PENDING"] + 0 " PENDING (" mustN["PENDING"] + 0 " Must Have), " \
           count["PLANNED"] + 0 " PLANNED (" mustN["PLANNED"] + 0 " Must Have), " \
           count["IN-PROGRESS"] + 0 " IN-PROGRESS, " count["BLOCKED"] + 0 " BLOCKED, " count["DONE"] + 0 " DONE, " count["OBSOLETE"] + 0 " OBSOLETE"
    if (forge == "") forge = "git-only"
    if (fmt == "json") {
        printf "{\"summary\":%s,\"must_have_open\":%s,\"root\":%s,\"ref\":%s,\"forge\":%s}\n", \
            jstr(line), jstr(mustList), jstr(root), jstr(ref " " refdesc), jstr(forge)
    } else {
        print "backlog-status: " root " @ " ref " (" refdesc ") · forge: " forge (forge == "git-only" ? " (sem PR aberto; DONE só por merge commit/checkpoint)" : "")
        print line
        if (mustList != "") print "Must Have não iniciadas: " mustList
        if (cycles != "") print "Ciclo de dependências entre épicos (nenhum deles pode começar): " cycles
        if (nrows > 0) print "\n| id | título | prio | est | status | onde | alerta |\n|---|---|---|---|---|---|---|"
    }
    fflush()
    cmd = "sort -t \"\t\" -k1,1n -k2,2n -k3,3 | cut -f4-"
    for (i = 1; i <= nrows; i++) print rows[i] | cmd
    close(cmd)
}'
