#!/bin/bash

# ==============================================================================
# Claude Code Workflow - Builder de Instalador Auto-Contido
# ==============================================================================
# Este script cria um instalador único (claude-workflow-installer.sh) que
# contém todos os arquivos necessários do deliverable claude/ embutidos em
# formato TGZ.
#
# Uso: bash build-claude-installer.sh [--output <arquivo>]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_DEFAULT="${SCRIPT_DIR}/claude-workflow-installer.sh"

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Variáveis
OUTPUT_FILE="${OUTPUT_DEFAULT}"

# Lista de itens obrigatórios para o bundle (dentro de claude/)
readonly CLAUDE_REQUIRED_ITEMS=(
    "agents"
    "commands"
    "context"
    "hooks"
    "model-profiles"
    "skills"
    "CLAUDE.md"
    "RTK.md"
    "settings.json"
    ".rtk"
)

# ==============================================================================
# FUNÇÕES DE LOG
# ==============================================================================

logInfo() {
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    echo -e "${CYAN}[${timestamp}] [INFO]${NC} $*"
}

logWarn() {
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    echo -e "${YELLOW}[${timestamp}] [WARN]${NC} $*" >&2
}

logError() {
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    echo -e "${RED}[${timestamp}] [ERROR]${NC} $*" >&2
}

logSuccess() {
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    echo -e "${GREEN}[${timestamp}] [OK]${NC} $*"
}

logStep() {
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    echo -e "${BLUE}[${timestamp}] [STEP]${NC} $*"
}

# ==============================================================================
# FUNÇÕES DE BUILD
# ==============================================================================

printBanner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║        🔧 Claude Code Workflow - Builder v${SCRIPT_VERSION}                 ║"
    echo "║        Gerador de Instalador Auto-Contido                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

printHelp() {
    echo "Uso: bash build-claude-installer.sh [OPÇÃO]"
    echo ""
    echo "Opções:"
    echo "  -o, --output <arquivo>   Arquivo de saída (padrão: claude-workflow-installer.sh)"
    echo "  -h, --help               Mostrar esta ajuda"
    echo "  --version                Mostrar versão"
    echo ""
    echo "O script gera um instalador auto-contido com todos os arquivos embutidos."
}

parseArguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    logError "Opção --output requer um caminho de arquivo"
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                printHelp
                exit 0
                ;;
            --version)
                echo "Claude Code Workflow Builder v${SCRIPT_VERSION}"
                exit 0
                ;;
            *)
                logError "Opção desconhecida: $1"
                exit 1
                ;;
        esac
    done
}

validateSourceFiles() {
    logStep "Validando arquivos fonte..."

    local claudeDir="${SCRIPT_DIR}/claude"

    if [[ ! -d "${claudeDir}" ]]; then
        logError "Diretório claude/ não encontrado em: ${SCRIPT_DIR}"
        return 1
    fi

    local missing=0

    for item in "${CLAUDE_REQUIRED_ITEMS[@]}"; do
        if [[ ! -e "${claudeDir}/${item}" ]]; then
            logError "Item obrigatório não encontrado: claude/${item}"
            ((missing++))
        else
            logSuccess "Encontrado: claude/${item}"
        fi
    done

    if [[ ${missing} -gt 0 ]]; then
        logError "Faltam ${missing} item(s) obrigatório(s)"
        return 1
    fi

    return 0
}

createTarball() {
    local tarballPath="$1"

    logStep "Criando tarball..."

    # Copiar install-claude.sh para dentro de claude/ para o bundle
    # (o stub espera source de ${TEMP_EXTRACT_DIR}/claude/install-claude.sh)
    cp "${SCRIPT_DIR}/install-claude.sh" "${SCRIPT_DIR}/claude/install-claude.sh"

    # Criar tarball com gzip do diretório claude/ inteiro
    tar -czf "${tarballPath}" -C "${SCRIPT_DIR}" "claude"

    # Limpar: remover install-claude.sh de claude/ (só estava lá para o bundle)
    rm -f "${SCRIPT_DIR}/claude/install-claude.sh"

    local size
    size=$(stat -c%s "${tarballPath}" 2>/dev/null || stat -f%z "${tarballPath}" 2>/dev/null)
    local sizeKb=$((size / 1024))

    logSuccess "Tarball criado: ${tarballPath} (${sizeKb} KB)"
}

generateStubScript() {
    cat << 'STUB_EOF'
#!/bin/bash

# ==============================================================================
# Claude Code Workflow - Instalador Auto-Contido
# ==============================================================================
# Este instalador contém todos os arquivos necessários embutidos.
# Extração automática ao executar.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# PAYLOAD EXTRACTION STUB
# ==============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

logInfo() { echo -e "${CYAN}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [INFO]${NC} $*"; }
logWarn() { echo -e "${YELLOW}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [WARN]${NC} $*" >&2; }
logError() { echo -e "${RED}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [ERROR]${NC} $*" >&2; }
logSuccess() { echo -e "${GREEN}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [OK]${NC} $*"; }
logStep() { echo -e "${BLUE}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [STEP]${NC} $*"; }

extractPayload() {
    local scriptPath="$1"
    local extractDir="$2"

    # Encontrar linha do marcador de payload
    local payloadLine
    payloadLine=$(grep -n "^__PAYLOAD_BEGIN__$" "${scriptPath}" 2>/dev/null | head -1 | cut -d: -f1)

    if [[ -z "${payloadLine}" ]]; then
        return 1
    fi

    logStep "Extraindo arquivos embutidos..."

    # Extrair payload (linhas após o marcador)
    tail -n +$((payloadLine + 1)) "${scriptPath}" | base64 -d | tar -xzf - -C "${extractDir}" 2>/dev/null

    logSuccess "Payload extraído"
    return 0
}

# ==============================================================================
# AUTO-EXTRAÇÃO
# ==============================================================================

# Obter caminho absoluto do script
SCRIPT_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"

# Verificar se há payload embutido
PAYLOAD_MARKER=$(grep -n "^__PAYLOAD_BEGIN__$" "${SCRIPT_SELF}" 2>/dev/null | head -1 | cut -d: -f1)

if [[ -n "${PAYLOAD_MARKER}" ]]; then
    logStep "Modo auto-contido detectado"

    # Criar diretório temporário para extração
    TEMP_EXTRACT_DIR=$(mktemp -d)

    # Cleanup ao sair
    cleanup() {
        rm -rf "${TEMP_EXTRACT_DIR}"
    }
    trap cleanup EXIT

    # Extrair payload
    if extractPayload "${SCRIPT_SELF}" "${TEMP_EXTRACT_DIR}"; then
        logInfo "Arquivos extraídos para: ${TEMP_EXTRACT_DIR}"

        # Executar install-claude.sh extraído
        SCRIPT_DIR="${TEMP_EXTRACT_DIR}/claude"
        export SCRIPT_DIR

        # Source do install-claude.sh extraído
        source "${TEMP_EXTRACT_DIR}/claude/install-claude.sh" "$@"
        exit $?
    else
        logError "Falha ao extrair payload"
        exit 1
    fi
fi

# Se não há payload, procurar install-claude.sh no diretório atual
logWarn "Nenhum payload encontrado - procurando install-claude.sh local..."
if [[ -f "install-claude.sh" ]]; then
    source "./install-claude.sh" "$@"
    exit $?
fi

logError "Nenhum payload e nenhum install-claude.sh encontrado"
exit 1
STUB_EOF
}

createPayloadInstaller() {
    local tarballPath="$1"
    local outputPath="$2"

    logStep "Gerando instalador auto-contido: ${outputPath}"

    # Gerar stub script + marcador + payload
    # (install-claude.sh já deve estar em claude/ se usarmos source dele)
    # NOTA: o stub source install-claude.sh do TEMP_EXTRACT_DIR/claude/
    # O install-claude.sh precisa estar no tarball, então precisamos copiá-lo
    # para claude/ antes de criar o tarball
    {
        generateStubScript
        echo ""
        echo "__PAYLOAD_BEGIN__"
        base64 "${tarballPath}"
    } > "${outputPath}"

    # Tornar executável
    chmod +x "${outputPath}"

    local size
    size=$(stat -c%s "${outputPath}" 2>/dev/null || stat -f%z "${outputPath}" 2>/dev/null)
    local sizeMb=$((size / 1024 / 1024))
    local sizeKb=$((size / 1024))

    logSuccess "Instalador gerado: ${outputPath} (${sizeMb} MB / ${sizeKb} KB)"
}

cleanup() {
    if [[ -n "${TARBALL_PATH:-}" && -f "${TARBALL_PATH}" ]]; then
        rm -f "${TARBALL_PATH}"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    trap cleanup EXIT

    printBanner

    if ! validateSourceFiles; then
        exit 1
    fi

    # Verificar se install-claude.sh existe (será incluído no bundle)
    if [[ ! -f "${SCRIPT_DIR}/install-claude.sh" ]]; then
        logError "install-claude.sh não encontrado em: ${SCRIPT_DIR}"
        logInfo "Este arquivo é necessário para o instalador auto-contido"
        exit 1
    fi

    # Criar tarball temporário
    local tarballPath
    tarballPath=$(mktemp --suffix=.tar.gz)
    TARBALL_PATH="${tarballPath}"

    createTarball "${tarballPath}"
    createPayloadInstaller "${tarballPath}" "${OUTPUT_FILE}"

    echo ""
    logSuccess "═══════════════════════════════════════════════════════════════"
    logSuccess "  Build concluído!"
    logSuccess "═══════════════════════════════════════════════════════════════"
    logInfo "Instalador: ${OUTPUT_FILE}"
    logInfo "Para distribuir, copie apenas o arquivo: ${OUTPUT_FILE}"
    logInfo "Execute com: bash ${OUTPUT_FILE}"
}

# ==============================================================================
# PONTO DE ENTRADA
# ==============================================================================
parseArguments "$@"
main
