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

die() {
    local code="$1"; shift
    printf 'ERRO: %s\n' "$*" >&2
    exit "${code}"
}

usage() {
    cat >&2 <<'EOF'
uso: backlog-status.sh [--project DIR] [--ref REF] [--development SLUG] [--epic EPIC-X]
                       [--aging-days N] [--all] [--json]

  --project DIR    sub-projeto (default: .claude/.active-project, senão .)
  --ref REF        referência da verdade (default: origin/main; sem fetch — é só leitura)
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
        -h|--help)     usage ;;
        *)             die 1 "argumento desconhecido: $1" ;;
    esac
done

[[ "${AGING_DAYS}" =~ ^[0-9]+$ ]] || die 1 "--aging-days exige um número"

if [[ -z "${PROJECT}" ]]; then
    PROJECT="$(cat .claude/.active-project 2>/dev/null || true)"
    PROJECT="${PROJECT:-.}"
fi

ROOT="$(git -C "${PROJECT}" rev-parse --show-toplevel 2>/dev/null)" \
    || die 3 "não é repo git: ${PROJECT}"

if [[ -z "${REF}" ]]; then
    REF="origin/main"
    git -C "${ROOT}" rev-parse --verify -q "${REF}^{commit}" >/dev/null || REF="main"
fi
git -C "${ROOT}" rev-parse --verify -q "${REF}^{commit}" >/dev/null \
    || die 5 "ref não existe: ${REF}"

readonly STORY_DIR="artifacts/stories"
readonly META_RE='^(type|title|created|development|epic):|^\*\*(Priority|Estimate)\*\*:'

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
        ( cd "${ROOT}" && glab mr list --all --per-page 1000 -F json 2>/dev/null ) \
            | node -e '
                let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
                  for (const m of JSON.parse(s)) {
                    const st = { merged: "MERGED", opened: "OPEN" }[m.state] || "CLOSED";
                    console.log(["PR", st, m.iid, m.source_branch, m.web_url].join("\t"));
                  }
                  console.log("FORGE\tglab");
                });' 2>/dev/null && return
    fi
    printf 'FORGE\tgit-only\n'
}

collect() {
    printf 'TODAY\t%s\n' "$(date +%Y-%m-%d)"

    git -C "${ROOT}" ls-tree --name-only "${REF}" "${STORY_DIR}/" \
        | sed 's/^/F\tref\t/'

    git -C "${ROOT}" grep -n -E "${META_RE}" "${REF}" -- "${STORY_DIR}/" 2>/dev/null \
        | sed "s|^${REF}:|M\t|" || true
    git -C "${ROOT}" grep -n -A8 -E '^supersedes:' "${REF}" -- "${STORY_DIR}/" 2>/dev/null \
        | sed "s|^${REF}:|SUP\t|" || true

    # Cada worktree: arquivos rastreados na branch dele e os não versionados. O checkout
    # principal pode estar sujo e atrasado — é justamente onde moram os não versionados.
    local wt branch
    while IFS=$'\t' read -r wt branch; do
        printf 'WT\t%s\t%s\n' "${wt}" "${branch}"
        [[ -d "${wt}/${STORY_DIR}" ]] || continue
        git -C "${wt}" ls-files -- "${STORY_DIR}/" | sed "s|^|F\twt:${wt}\t|"
        git -C "${wt}" ls-files --others --exclude-standard -- "${STORY_DIR}/" \
            | sed "s|^|F\tuntracked:${wt}\t|"
        ( cd "${wt}" && grep -n -H -E "${META_RE}" "${STORY_DIR}"/*.md 2>/dev/null ) \
            | sed 's/^/M\t/' || true
        ( cd "${wt}" && grep -n -H -A8 -E '^supersedes:' "${STORY_DIR}"/*.md 2>/dev/null ) \
            | sed 's/^/SUP\t/' || true
    done < <(git -C "${ROOT}" worktree list --porcelain | awk '
        /^worktree / { wt = substr($0, 10); br = "" }
        /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
        /^$/         { if (wt != "") print wt "\t" br; wt = "" }
        END          { if (wt != "") print wt "\t" br }')

    git -C "${ROOT}" log --merges --format=%s "${REF}" \
        | grep -oE '(feat|fix)/[A-Za-z0-9._-]+' | sed 's/^/MC\t/' || true

    git -C "${ROOT}" for-each-ref --format='%(refname:short)' --no-merged="${REF}" \
        refs/heads/feat refs/heads/fix | sed 's/^/LB\t/' || true

    # Ids citados em qualquer BACKLOG-SUMMARY, de <ref> e dos worktrees.
    {
        git -C "${ROOT}" grep -h -o -E 'STORY(-[0-9]+)+' "${REF}" -- "${STORY_DIR}/BACKLOG-SUMMARY*" 2>/dev/null || true
        while read -r wt; do
            cat "${wt}/${STORY_DIR}"/BACKLOG-SUMMARY*.md 2>/dev/null || true
        done < <(git -C "${ROOT}" worktree list --porcelain | sed -n 's/^worktree //p')
    } | grep -o -E 'STORY(-[0-9]+)+' | sed 's/^/SUM\t/' || true

    forgeRecords
}

collect | awk -F'\t' -v devf="${DEV_FILTER}" -v epicf="${EPIC_FILTER}" \
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
    sub(/-(checkpoint|technical-analysis|code-analysis|ux-spec|test-report|qa-report|code-review|impl-report[A-Za-z0-9_-]*)$/, "", b)
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
$1 == "WT" { if ($3 ~ /^(feat|fix)\//) wtBranch[$3] = $2; next }
$1 == "MC" { mergedBranch[$2] = "merge commit"; next }
$1 == "LB" { localBranch[$2] = 1; next }
$1 == "SUM" { inSummary[$2] = 1; next }
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

    for (id in ids) {
        title = meta[id, "title", "s"];       if (title == "") title = meta[id, "title", "c"]
        dev   = meta[id, "development", "s"]; if (dev == "")   dev   = meta[id, "development", "c"]
        epic  = meta[id, "epic", "s"];        if (epic == "")  epic  = meta[id, "epic", "c"]
        if (devf != "" && dev != devf) continue
        if (epicf != "" && epic != epicf) continue

        pr = meta[id, "priority", "s"]; gsub(/^[* ]+/, "", pr)
        if (pr ~ /^[Mm]ust/) { pr = "Must"; prRank = 1 }
        else if (pr ~ /^[Ss]hould/) { pr = "Should"; prRank = 2 }
        else if (pr ~ /^[Cc]ould/) { pr = "Could"; prRank = 3 }
        else if (pr ~ /^[Ww]on/) { pr = "Wont"; prRank = 4 }
        else { pr = "-"; prRank = 5 }
        est = meta[id, "estimate", "s"]; sub(/[ (].*/, "", est); if (est == "") est = "-"
        created = meta[id, "created", "s"]

        if (id in done)                  st = "DONE"
        else if (id in obsoleteBy)       { st = "OBSOLETE"; addWhere(id, "supersedes em " obsoleteBy[id]) }
        else if (id in active)           st = "IN-PROGRESS"
        else if (has[id, "checkpoint", "branch"] || has[id, "checkpoint", "untracked"]) st = "IN-PROGRESS"
        else if (has[id, "analysis", "ref"] || has[id, "analysis", "branch"] || has[id, "analysis", "untracked"]) st = "PLANNED"
        else                             st = "PENDING"

        if (has[id, "story", "untracked"] && !has[id, "story", "ref"] && !has[id, "story", "branch"]) addAlert(id, "UNTRACKED")
        if (has[id, "story", "branch"] && !has[id, "story", "ref"]) addAlert(id, "NOT-ON-REF")
        if (st != "DONE" && st != "OBSOLETE" && !(shortId(id) in inSummary)) addAlert(id, "NOT-IN-SUMMARY")
        if (st == "DONE" && (id in wtOf)) addAlert(id, "STALE-WORKTREE")
        age = (created != "") ? today - days(created) : -1
        if (pr == "Must" && (st == "PENDING" || st == "PLANNED") && age > aging) addAlert(id, "MUST-HAVE-AGING")

        count[st]++
        if (pr == "Must" && (st == "PENDING" || st == "PLANNED")) { mustN[st]++; must[++nmust] = shortId(id) }

        stRank = (st == "IN-PROGRESS") ? 1 : (st == "PENDING") ? 2 : (st == "PLANNED") ? 3 : (st == "OBSOLETE") ? 4 : 5
        if (!showall && (st == "DONE" || st == "OBSOLETE")) continue
        w = (id in where) ? where[id] : "-"
        a = (alert[id] == "") ? "-" : alert[id]
        if (fmt == "json")
            row = "{\"id\":" jstr(id) ",\"title\":" jstr(title) ",\"priority\":" jstr(pr) ",\"estimate\":" jstr(est) \
                  ",\"status\":" jstr(st) ",\"where\":" jstr(w) ",\"alerts\":" jstr(a) ",\"development\":" jstr(dev) \
                  ",\"created\":" jstr(created) "}"
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
           count["IN-PROGRESS"] + 0 " IN-PROGRESS, " count["DONE"] + 0 " DONE, " count["OBSOLETE"] + 0 " OBSOLETE"
    if (forge == "") forge = "git-only"
    if (fmt == "json") {
        printf "{\"summary\":%s,\"must_have_open\":%s,\"root\":%s,\"ref\":%s,\"forge\":%s}\n", \
            jstr(line), jstr(mustList), jstr(root), jstr(ref " " refdesc), jstr(forge)
    } else {
        print "backlog-status: " root " @ " ref " (" refdesc ") · forge: " forge (forge == "git-only" ? " (sem PR aberto; DONE só por merge commit/checkpoint)" : "")
        print line
        if (mustList != "") print "Must Have não iniciadas: " mustList
        if (nrows > 0) print "\n| id | título | prio | est | status | onde | alerta |\n|---|---|---|---|---|---|---|"
    }
    fflush()
    cmd = "sort -t \"\t\" -k1,1n -k2,2n -k3,3 | cut -f4-"
    for (i = 1; i <= nrows; i++) print rows[i] | cmd
    close(cmd)
}'
