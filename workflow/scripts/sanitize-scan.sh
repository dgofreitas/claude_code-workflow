#!/usr/bin/env bash
#
# sanitize-scan.sh — triagem read-only para /sdlc:sanitize-comments
#
# Resolve escopo, aplica exclusões, classifica nível e ranqueia por densidade
# de comentário. NUNCA escreve em arquivo do projeto.
#
# Exit codes (o chamador distingue "limpo" de "quebrado" pelo código, nunca
# pela saída vazia — stdout vazio vindo de erro do git era lido como
# "árvore limpa" e liberava o --apply sem rede de segurança):
#   0  ok
#   1  erro de uso
#   2  árvore suja
#   3  raiz não resolvida / não é repo git
#   4  escopo vazio (nenhum arquivo casou)

set -euo pipefail

readonly FIXED_EXCLUDES=(
    ".git/"
    "node_modules/"
    "vendor/"
    "dist/"
    "build/"
    "coverage/"
    ".nyc_output/"
)

readonly AUX_CAP=15

SCOPE=""
LIMIT=15
LEVEL_OVERRIDE=""
ROOT_OVERRIDE=""
USER_EXCLUDES=()

die() {
    local code="$1"; shift
    printf 'ERRO: %s\n' "$*" >&2
    exit "${code}"
}

usage() {
    cat >&2 <<'EOF'
uso: sanitize-scan.sh [ESCOPO] [--exclude PADRÃO]... [--limit N]
                      [--level safe|default|strict] [--root DIR]

ESCOPO:
  (vazio) | all      repo inteiro
  caminho/arquivo    um arquivo
  caminho/           recursivo sob o diretório
  caminho/*.ext      NÃO-recursivo: só .ext direto naquele diretório
  *.ext | .ext | ext  essa extensão em todo o repo
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --exclude)
            [[ $# -ge 2 ]] || die 1 "--exclude exige um padrão"
            IFS=',' read -ra parts <<< "$2"
            for p in "${parts[@]}"; do
                [[ -n "${p}" ]] && USER_EXCLUDES+=("${p}")
            done
            shift 2
            ;;
        --exclude=*)
            IFS=',' read -ra parts <<< "${1#*=}"
            for p in "${parts[@]}"; do
                [[ -n "${p}" ]] && USER_EXCLUDES+=("${p}")
            done
            shift
            ;;
        --limit)
            [[ $# -ge 2 ]] || die 1 "--limit exige um número"
            LIMIT="$2"; shift 2
            ;;
        --limit=*)
            LIMIT="${1#*=}"; shift
            ;;
        --level)
            [[ $# -ge 2 ]] || die 1 "--level exige safe|default|strict"
            LEVEL_OVERRIDE="$2"; shift 2
            ;;
        --level=*)
            LEVEL_OVERRIDE="${1#*=}"; shift
            ;;
        --root)
            [[ $# -ge 2 ]] || die 1 "--root exige um diretório"
            ROOT_OVERRIDE="$2"; shift 2
            ;;
        --root=*)
            ROOT_OVERRIDE="${1#*=}"; shift
            ;;
        -h|--help)
            usage
            ;;
        --*)
            die 1 "flag desconhecida: $1"
            ;;
        *)
            [[ -n "${SCOPE}" ]] && die 1 "escopo já definido como '${SCOPE}'; recebi também '$1'"
            SCOPE="$1"; shift
            ;;
    esac
done

[[ "${LIMIT}" =~ ^[0-9]+$ ]] || die 1 "--limit deve ser inteiro, recebi '${LIMIT}'"
if [[ -n "${LEVEL_OVERRIDE}" && ! "${LEVEL_OVERRIDE}" =~ ^(safe|default|strict)$ ]]; then
    die 1 "--level deve ser safe|default|strict, recebi '${LEVEL_OVERRIDE}'"
fi

# ---------------------------------------------------------------- raiz

resolveRoot() {
    if [[ -n "${ROOT_OVERRIDE}" ]]; then
        printf '%s' "${ROOT_OVERRIDE}"
        return
    fi
    # Instalação umbrella: o diretório da sessão tem .claude/ mas não .git/, e
    # o repo de verdade é o sub-projeto nomeado em .active-project.
    local active=""
    [[ -f ".claude/.active-project" ]] && active="$(tr -d '[:space:]' < .claude/.active-project)"
    printf '%s' "${active:-.}"
}

ROOT="$(resolveRoot)"
[[ -d "${ROOT}" ]] || die 3 "raiz não existe: ${ROOT}"

TOPLEVEL="$(git -C "${ROOT}" rev-parse --show-toplevel 2>/dev/null)" \
    || die 3 "não é um repositório git: ${ROOT} (numa instalação umbrella, rode com --root <sub-projeto> ou defina .claude/.active-project)"

# ---------------------------------------------------------------- portão de árvore limpa

DIRTY="$(git -C "${TOPLEVEL}" status --porcelain)"
if [[ -n "${DIRTY}" ]]; then
    printf 'ÁRVORE SUJA em %s\n\n%s\n\n' "${TOPLEVEL}" "${DIRTY}" >&2
    printf 'Commit ou stash antes: `git diff` é a revisão desta operação e `git checkout` é o desfazer.\n' >&2
    exit 2
fi

# ---------------------------------------------------------------- escopo

# Devolve o pathspec git e uma descrição legível. Usa a mágica :(glob) para
# que `*` nunca cruze `/` — é isso que torna `dir/*.ext` não-recursivo de
# forma determinística, em vez de depender do wildmatch padrão.
SCOPE_KIND=""
SCOPE_SPEC=""

classifyScope() {
    local s="$1"

    if [[ -z "${s}" || "${s}" == "all" ]]; then
        SCOPE_KIND="repo inteiro"
        SCOPE_SPEC=""
        return
    fi

    # Caminho absoluto → relativiza contra o toplevel; fora dele é erro, não
    # um escopo vazio silencioso.
    if [[ "${s}" == /* ]]; then
        local abs_top; abs_top="$(cd "${TOPLEVEL}" && pwd -P)"
        case "${s}" in
            "${abs_top}"/*) s="${s#"${abs_top}"/}" ;;
            "${abs_top}")   s="" ;;
            *) die 1 "escopo '${s}' está fora do repo ${abs_top}" ;;
        esac
        if [[ -z "${s}" ]]; then
            SCOPE_KIND="repo inteiro"
            SCOPE_SPEC=""
            return
        fi
    fi

    # dir/*.ext  → não-recursivo naquele diretório
    if [[ "${s}" == */\*.* ]]; then
        SCOPE_KIND="não-recursivo em ${s%/*}/"
        SCOPE_SPEC=":(glob)${s}"
        return
    fi

    # *.ext | .ext | ext → extensão no repo inteiro
    if [[ "${s}" == \*.* ]]; then
        SCOPE_KIND="extensão ${s#\*} no repo inteiro"
        SCOPE_SPEC=":(glob)**/${s}"
        return
    fi
    if [[ "${s}" == .* && "${s}" != */* && -e "${TOPLEVEL}/${s}" ]]; then
        : # arquivo dotfile existente cai no ramo de arquivo abaixo
    elif [[ "${s}" == .?* && "${s}" != */* ]]; then
        SCOPE_KIND="extensão ${s} no repo inteiro"
        SCOPE_SPEC=":(glob)**/*${s}"
        return
    elif [[ "${s}" != */* && "${s}" != *.* && ! -e "${TOPLEVEL}/${s}" ]]; then
        SCOPE_KIND="extensão .${s} no repo inteiro"
        SCOPE_SPEC=":(glob)**/*.${s}"
        return
    fi

    if [[ -d "${TOPLEVEL}/${s}" ]]; then
        SCOPE_KIND="recursivo sob ${s%/}/"
        SCOPE_SPEC="${s%/}/"
        return
    fi

    if [[ "${s}" == */ ]]; then
        SCOPE_KIND="recursivo sob ${s}"
        SCOPE_SPEC="${s}"
        return
    fi

    SCOPE_KIND="arquivo único"
    SCOPE_SPEC="${s}"
}

classifyScope "${SCOPE}"

buildPathspec() {
    local -n out="$1"
    out=()
    [[ -n "${SCOPE_SPEC}" ]] && out+=("${SCOPE_SPEC}")
    local p
    for p in "${FIXED_EXCLUDES[@]}"; do
        out+=(":(exclude)${p}**")
    done
    for p in "${USER_EXCLUDES[@]}"; do
        # Sem barra e sem curinga: pode ser extensão (.sql) ou nome solto.
        if [[ "${p}" == .?* && "${p}" != */* && "${p}" != *\** ]]; then
            out+=(":(exclude,glob)**/*${p}")
        elif [[ "${p}" == */ ]]; then
            out+=(":(exclude)${p}**")
        elif [[ "${p}" == *\** ]]; then
            out+=(":(exclude,glob)${p}")
        else
            out+=(":(exclude)${p}")
            out+=(":(exclude)${p}/**")
        fi
    done
}

listFiles() {
    local -a spec
    buildPathspec spec
    if [[ ${#spec[@]} -eq 0 ]]; then
        git -C "${TOPLEVEL}" ls-files
    else
        git -C "${TOPLEVEL}" ls-files -- "${spec[@]}"
    fi
}

listFilesNoExcludes() {
    if [[ -z "${SCOPE_SPEC}" ]]; then
        git -C "${TOPLEVEL}" ls-files
    else
        git -C "${TOPLEVEL}" ls-files -- "${SCOPE_SPEC}"
    fi
}

# ---------------------------------------------------------------- nível

levelFor() {
    if [[ -n "${LEVEL_OVERRIDE}" ]]; then
        printf '%s' "${LEVEL_OVERRIDE}"
        return
    fi
    case "$1" in
        *.js|*.jsx|*.ts|*.tsx|*.py|*.sh|*.bash|*.c|*.h|*.go|*.rb|*.java)
            printf 'default' ;;
        *.conf|*.env|*.env.*|*.ini|*.toml|*.json5|*.properties|*.template|*.yml|*.yaml|Dockerfile|*/Dockerfile)
            printf 'safe' ;;
        *)
            printf '' ;;
    esac
}

# ---------------------------------------------------------------- métricas

METRICS=""
TOTAL_CMT=0
TOTAL_CODE=0
CONSIDERED=0
SKIPPED_TYPE=0

while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    lvl="$(levelFor "${f}")"
    if [[ -z "${lvl}" ]]; then
        SKIPPED_TYPE=$((SKIPPED_TYPE + 1))
        continue
    fi
    path="${TOPLEVEL}/${f}"
    [[ -f "${path}" ]] || continue

    tot=$(grep -c '' "${path}" 2>/dev/null || echo 0)
    blank=$(grep -c '^[[:space:]]*$' "${path}" 2>/dev/null || true)
    cmt=$(grep -cE '^[[:space:]]*(#|//|\*|/\*)' "${path}" 2>/dev/null || true)
    blank=${blank:-0}; cmt=${cmt:-0}
    code=$((tot - blank - cmt))
    [[ ${code} -le 0 ]] && continue

    CONSIDERED=$((CONSIDERED + 1))
    TOTAL_CMT=$((TOTAL_CMT + cmt))
    TOTAL_CODE=$((TOTAL_CODE + code))
    METRICS+="$(awk -v c="${cmt}" -v k="${code}" -v l="${lvl}" -v f="${f}" \
        'BEGIN{printf "%.1f\t%d\t%d\t%s\t%s", 100*c/(c+k), c, k, l, f}')"$'\n'
done < <(listFiles)

[[ ${CONSIDERED} -eq 0 ]] && die 4 "escopo vazio: nenhum arquivo elegível casou com '${SCOPE:-all}' (${SCOPE_KIND})"

RANKED="$(printf '%s' "${METRICS}" | sort -rn | head -n "${LIMIT}")"
DROPPED=$((CONSIDERED - $(printf '%s\n' "${RANKED}" | grep -c . || true)))

# ---------------------------------------------------------------- exclusões

EXCLUDED_REPORT=""
if [[ ${#USER_EXCLUDES[@]} -gt 0 || ${#FIXED_EXCLUDES[@]} -gt 0 ]]; then
    before=$(listFilesNoExcludes | wc -l)
    after=$(listFiles | wc -l)
    EXCLUDED_TOTAL=$((before - after))

    # Contagem por padrão: escopo bruto menos o escopo com este padrão isolado.
    for p in "${USER_EXCLUDES[@]}"; do
        if [[ "${p}" == .?* && "${p}" != */* && "${p}" != *\** ]]; then
            spec=":(exclude,glob)**/*${p}"
        elif [[ "${p}" == */ ]]; then
            spec=":(exclude)${p}**"
        elif [[ "${p}" == *\** ]]; then
            spec=":(exclude,glob)${p}"
        else
            spec=":(exclude)${p}"
        fi
        if [[ -z "${SCOPE_SPEC}" ]]; then
            n2=$(git -C "${TOPLEVEL}" ls-files -- "${spec}" | wc -l)
        else
            n2=$(git -C "${TOPLEVEL}" ls-files -- "${SCOPE_SPEC}" "${spec}" | wc -l)
        fi
        EXCLUDED_REPORT+="$((before - n2))"$'\t'"usuário"$'\t'"${p}"$'\n'
    done
else
    EXCLUDED_TOTAL=0
fi

# ---------------------------------------------------------------- varreduras auxiliares

scopedFiles() { listFiles; }

staleRefs() {
    local f tok
    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        [[ -f "${TOPLEVEL}/${f}" ]] || continue
        { grep -nE '^[[:space:]]*(#|//|\*)' "${TOPLEVEL}/${f}" 2>/dev/null \
        | grep -oE '[A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.[A-Za-z0-9]+' \
        | sort -u \
        | while IFS= read -r tok; do
            [[ -e "${TOPLEVEL}/${tok}" ]] || printf '%s\t%s\n' "${f}" "${tok}"
        done; } || true
    done < <(scopedFiles)
    return 0
}

duplicateBlocks() {
    local -a spec
    buildPathspec spec
    if [[ ${#spec[@]} -eq 0 ]]; then
        git -C "${TOPLEVEL}" grep -hE '^[[:space:]]*(#|//)' 2>/dev/null || true
    else
        git -C "${TOPLEVEL}" grep -hE '^[[:space:]]*(#|//)' -- "${spec[@]}" 2>/dev/null || true
    fi \
    | sed 's/^[[:space:]]*//' \
    | { grep -vE '^(#|//)[[:space:]]*[-=_*#/─━═┄·.[:space:]]*$' || true; } \
    | { grep -vEi 'shellcheck|eslint|noqa|type:|pylint|nosec|nolint' || true; } \
    | awk 'length($0)>40' \
    | sort | uniq -c | sort -rn | awk '$1>1'
    return 0
}

oversizedBlocks() {
    local f
    while IFS= read -r f; do
        [[ -n "${f}" ]] || continue
        [[ -f "${TOPLEVEL}/${f}" ]] || continue
        awk -v name="${f}" '
            /^[[:space:]]*(#|\/\/|\*)/ { n++; if (n==1) start=NR; next }
            { if (n>=5) printf "%s:%d\t%d\n", name, start, n; n=0 }
            END { if (n>=5) printf "%s:%d\t%d\n", name, start, n }
        ' "${TOPLEVEL}/${f}" || true
    done < <(scopedFiles)
    return 0
}

# Uma seção auxiliar vazia é resultado normal, não falha. Sob `set -e` +
# pipefail um `grep` sem match derruba o script inteiro no meio do relatório,
# então cada estágio aqui absorve o próprio status.
capped() {
    local body total
    body="$(cat)" || true
    if [[ -z "${body//[[:space:]]/}" ]]; then
        printf '(nenhum)\n'
        return 0
    fi
    total="$(printf '%s\n' "${body}" | grep -c . || true)"
    printf '%s\n' "${body}" | { grep . || true; } | head -n "${AUX_CAP}"
    if [[ ${total} -gt ${AUX_CAP} ]]; then
        printf '... (%d a mais, omitidos)\n' "$((total - AUX_CAP))"
    fi
    return 0
}

# ---------------------------------------------------------------- saída

RATIO=$(awk -v c="${TOTAL_CMT}" -v k="${TOTAL_CODE}" 'BEGIN{ if (c+k>0) printf "%.1f", 100*c/(c+k); else print "0.0" }')

printf 'ROOT\t%s\n' "${TOPLEVEL}"
printf 'SCOPE\t%s\t(%s)\n' "${SCOPE:-all}" "${SCOPE_KIND}"
printf 'LEVEL_OVERRIDE\t%s\n' "${LEVEL_OVERRIDE:-none}"
printf 'FILES_CONSIDERED\t%d\n' "${CONSIDERED}"
printf 'FILES_RANKED\t%d\n' "$(printf '%s\n' "${RANKED}" | grep -c . || true)"
printf 'LIMIT\t%d\n' "${LIMIT}"
printf 'LIMIT_DROPPED\t%d\n' "${DROPPED}"
printf 'EXCLUDED_TOTAL\t%d\n' "${EXCLUDED_TOTAL}"
printf 'SKIPPED_UNKNOWN_TYPE\t%d\n' "${SKIPPED_TYPE}"
printf 'AGGREGATE\tcmt=%d\tcode=%d\tratio=%s%%\n' "${TOTAL_CMT}" "${TOTAL_CODE}" "${RATIO}"

printf '\n# RANKED\tdensity\tcmt\tcode\tlevel\tpath\n'
printf '%s\n' "${RANKED}"

printf '\n# EXCLUDED_BY_PATTERN\tcount\torigin\tpattern\n'
for p in "${FIXED_EXCLUDES[@]}"; do
    printf '%s\tfixa\t%s\n' '-' "${p}"
done
[[ -n "${EXCLUDED_REPORT}" ]] && printf '%s' "${EXCLUDED_REPORT}"

printf '\n# STALE_REFS\tfile\treferenced-path\n'
staleRefs | capped

printf '\n# DUPLICATE_BLOCKS\tcount\ttext\n'
duplicateBlocks | capped

printf '\n# OVERSIZED_BLOCKS\tfile:line\tlines\n'
oversizedBlocks | capped
