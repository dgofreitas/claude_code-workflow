#!/bin/bash

# ==============================================================================
# Claude Code Workflow — Instalador Local
# ==============================================================================
# Compatível com: Debian, Ubuntu, Linux Mint, macOS
# Uso: bash install-claude.sh [--dest <path>] [--verbose] [--help]
#
# Modo: LOCAL apenas. Instala em <project>/.claude/.
# Se --dest não for informado, instala no cwd/.claude.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="Claude Code Workflow Installer"

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

readonly DEFAULT_LOCAL_DIR=".claude"

readonly CLAUDE_REQUIRED_ITEMS=(
    "agents"
    "commands"
    "context"
    "hooks"
    "skills"
    "model-profiles"
    "CLAUDE.md"
    "RTK.md"
    "settings.json"
    ".rtk"
)

readonly RTK_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"
readonly RTK_GLOBAL_BIN_DIR="${HOME}/.local/bin"

COUNT_AGENTS=0
COUNT_COMMANDS=0
COUNT_SKILLS=0
COUNT_HOOKS=0
COUNT_CONTEXT=0

INSTALL_DEST=""
VERBOSE=false
NO_TAVILY=false
MODEL_PROVIDER=""
RTK_VERSION=""

# ==============================================================================
# LOG
# ==============================================================================

logInfo()    { echo -e "${CYAN}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [INFO]${NC} $*"; }
logWarn()    { echo -e "${YELLOW}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [WARN]${NC} $*" >&2; }
logError()   { echo -e "${RED}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [ERROR]${NC} $*" >&2; }
logSuccess() { echo -e "${GREEN}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [OK]${NC} $*"; }
logStep()    { echo -e "${BLUE}[$(date '+%Y-%m-%dT%H:%M:%S%z')] [STEP]${NC} $*"; }

# ==============================================================================
# UI
# ==============================================================================

calculateMetrics() {
    local baseDir="${SCRIPT_DIR}"
    COUNT_AGENTS=$(find "${baseDir}/agents"   -name "*.md"     2>/dev/null | wc -l)
    COUNT_COMMANDS=$(find "${baseDir}/commands" -name "*.md"   2>/dev/null | wc -l)
    COUNT_SKILLS=$(find "${baseDir}/skills"  -name "SKILL.md" 2>/dev/null | wc -l)
    COUNT_HOOKS=$(find "${baseDir}/hooks"    -type f          2>/dev/null | wc -l)
    COUNT_CONTEXT=$(find "${baseDir}/context" -name "*.md"    2>/dev/null | wc -l)
}

printBanner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║        🤖 Claude Code Workflow - Instalador v${SCRIPT_VERSION}                ║"
    echo "║                                                                ║"
    echo "║  🤖 Agentes: ${COUNT_AGENTS} | ⌨️  Comandos: ${COUNT_COMMANDS} | 🛠️  Skills: ${COUNT_SKILLS}               ║"
    echo "║  🔗 Hooks: ${COUNT_HOOKS} | 📂 Contexto: ${COUNT_CONTEXT} | ⬇️  RTK: baixado na instalação        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

printHelp() {
    echo "Uso: bash install-claude.sh [OPÇÃO]"
    echo ""
    echo "Modo único: instalação LOCAL no projeto (.claude/)."
    echo ""
    echo "Opções:"
    echo "  -d, --dest <path>     Diretório do projeto destino (padrão: pwd)"
    echo "                        Resultado: <path>/.claude/"
    echo "  -v, --verbose         Modo verboso"
    echo "  -h, --help            Mostrar esta ajuda"
    echo "  --version             Mostrar versão"
    echo "  --no-tavily           Não configurar Tavily MCP (padrão: pergunta)"
    echo "  --provider <p>        Provedor de modelo: 'claude' ou 'ollama' (padrão: pergunta)"
    echo "  --rtk-version <v>     Fixa a versão do RTK baixada (ex.: v0.43.0). Padrão: sempre a mais recente"
    echo ""
    echo "Sem --dest: instala em <cwd>/.claude/ (interativo confirma o caminho)."
    echo "Sem --provider: pergunta interativamente qual provedor usar neste projeto."
    echo "RTK é sempre baixado direto de github.com/rtk-ai/rtk na instalação — nunca vendorizado neste repo."
    echo "RTK é instalado globalmente em ~/.local/bin (compartilhado entre projetos, já costuma estar no PATH),"
    echo "com um link simbólico em <projeto>/.claude/bin/rtk. --rtk-version afeta essa instalação global."
    echo ""
    echo "Variáveis de ambiente:"
    echo "  API_KEY_TAVILY        Chave da API Tavily (evita prompt interativo)"
}

# ==============================================================================
# PRÉ-REQUISITOS
# ==============================================================================

checkPrerequisites() {
    logStep "Verificando pré-requisitos..."

    local -a missing=()
    local -a warnings=()

    # Claude Code CLI (opcional — avisa mas não bloqueia)
    if ! command -v claude > /dev/null 2>&1; then
        warnings+=("claude")
        logWarn "Claude Code CLI não encontrado"
        logInfo "  Instale em: https://docs.anthropic.com/en/docs/agents/claude-code"
    else
        local version
        version=$(claude --version 2>/dev/null || echo "instalado")
        logSuccess "Claude Code CLI: ${version}"
    fi

    # Node.js ≥18 (obrigatório para hooks Caveman)
    if ! command -v node > /dev/null 2>&1; then
        missing+=("node")
        logWarn "Node.js não encontrado (≥18 necessário para hooks Caveman)"
        logInfo "  Instale em: https://nodejs.org"
    else
        local nodeMajor
        nodeMajor=$(node -p "process.versions.node.split('.')[0]")
        if [[ "${nodeMajor}" -lt 18 ]]; then
            missing+=("node≥18")
            logWarn "Node.js ${nodeMajor} muito antigo. Necessário ≥18 para hooks Caveman."
        else
            logSuccess "Node.js: $(node --version)"
        fi
    fi

    # RTK no PATH (opcional — o instalador baixa a versão atual em ~/.local/bin de qualquer forma)
    if ! command -v rtk > /dev/null 2>&1; then
        logInfo "RTK não encontrado no PATH — será baixado direto do GitHub (rtk-ai/rtk) em ${RTK_GLOBAL_BIN_DIR}"
    else
        logSuccess "RTK (global): $(rtk --version 2>/dev/null || echo "instalado")"
    fi

    # Git (recomendado)
    if ! command -v git > /dev/null 2>&1; then
        logWarn "Git não encontrado (recomendado para workflows em equipe)"
    else
        logSuccess "Git: $(git --version | cut -d' ' -f3)"
    fi

    # jq (obrigatório apenas se o provedor Ollama for escolhido)
    if ! command -v jq > /dev/null 2>&1; then
        warnings+=("jq")
        logWarn "jq não encontrado (necessário apenas se você escolher o provedor Ollama)"
    else
        logSuccess "jq: $(jq --version 2>/dev/null || echo "instalado")"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        logError "Dependências obrigatórias faltando: ${missing[*]}"
        return 1
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        logWarn "Dependências opcionais não encontradas: ${warnings[*]}"
        logInfo "  A instalação continuará, mas algumas funcionalidades podem estar limitadas"
    fi

    return 0
}

# ==============================================================================
# INSTALAÇÃO
# ==============================================================================

copyWorkflowFiles() {
    local targetDir="$1"
    logStep "Copiando arquivos para: ${targetDir}"

    mkdir -p "${targetDir}"

    for item in "${CLAUDE_REQUIRED_ITEMS[@]}"; do
        if [[ -e "${SCRIPT_DIR}/${item}" ]]; then
            cp -r "${SCRIPT_DIR}/${item}" "${targetDir}/"
            logInfo "  Copiado: ${item}"
        else
            logWarn "  Item ignorado (não encontrado na fonte): ${item}"
        fi
    done

    logSuccess "Arquivos copiados com sucesso"
}

installRtk() {
    local targetDir="$1"
    local projectBinDir="${targetDir}/bin"
    local globalBinDir="${RTK_GLOBAL_BIN_DIR}"

    logStep "Baixando RTK (rtk-ai/rtk) direto da fonte..."

    if ! command -v curl > /dev/null 2>&1; then
        logWarn "curl não encontrado — não é possível baixar o RTK automaticamente"
        logInfo "  Instale manualmente: RTK_INSTALL_DIR=\"${globalBinDir}\" curl -fsSL ${RTK_INSTALL_SCRIPT_URL} | sh"
        return 0
    fi

    mkdir -p "${globalBinDir}"

    # Instala SEMPRE em ~/.local/bin (padrão do instalador upstream, já costuma estar no
    # PATH do usuário) em vez de <projeto>/.claude/bin — instalar dentro do projeto quebrava
    # a resolução de `rtk` como comando de shell (nada adiciona .claude/bin ao PATH da sessão
    # que a ferramenta Bash do Claude Code realmente usa). Um link simbólico no projeto
    # preserva o caminho fixo que rtk-guard.js espera e a checagem de integridade abaixo.
    local installOutput
    if [[ -n "${RTK_VERSION}" ]]; then
        logInfo "  Versão fixada: ${RTK_VERSION} (instalação global em ${globalBinDir}, compartilhada entre projetos)"
        installOutput=$(RTK_INSTALL_DIR="${globalBinDir}" RTK_VERSION="${RTK_VERSION}" curl -fsSL "${RTK_INSTALL_SCRIPT_URL}" 2>&1 | RTK_INSTALL_DIR="${globalBinDir}" RTK_VERSION="${RTK_VERSION}" sh 2>&1) || true
    else
        installOutput=$(curl -fsSL "${RTK_INSTALL_SCRIPT_URL}" 2>&1 | RTK_INSTALL_DIR="${globalBinDir}" sh 2>&1) || true
    fi

    if [[ -x "${globalBinDir}/rtk" ]]; then
        logSuccess "RTK instalado (global): $("${globalBinDir}/rtk" --version 2>/dev/null || echo "${globalBinDir}/rtk")"

        mkdir -p "${projectBinDir}"
        ln -sf "${globalBinDir}/rtk" "${projectBinDir}/rtk"
        logInfo "  Link do projeto: ${projectBinDir}/rtk -> ${globalBinDir}/rtk"

        case ":${PATH}:" in
            *":${globalBinDir}:"*)
                logSuccess "  ${globalBinDir} já está no PATH — 'rtk' funciona direto no shell"
                ;;
            *)
                logWarn "  ${globalBinDir} não está no PATH desta sessão de shell"
                logInfo "    Adicione ao seu shell profile (~/.bashrc ou ~/.zshrc): export PATH=\"${globalBinDir}:\$PATH\""
                ;;
        esac
    else
        logWarn "Falha ao baixar o RTK automaticamente — a instalação continua sem ele"
        [[ "${VERBOSE}" == "true" ]] && logInfo "  Saída do instalador: ${installOutput}"
        logInfo "  Para tentar manualmente depois: RTK_INSTALL_DIR=\"${globalBinDir}\" curl -fsSL ${RTK_INSTALL_SCRIPT_URL} | sh"
    fi
}

removeExistingInstallation() {
    local targetDir="$1"
    logStep "Removendo instalação existente em: ${targetDir}"

    for item in "${CLAUDE_REQUIRED_ITEMS[@]}"; do
        rm -rf "${targetDir}/${item}"
    done
    rm -rf "${targetDir}/node_modules"

    logSuccess "Instalação anterior removida"
}

confirmOverwrite() {
    local targetDir="$1"
    [[ ! -d "${targetDir}/agents" ]] && return 0

    logWarn "Instalação existente encontrada em: ${targetDir}"
    read -p "Sobrescrever? [y/N]: " -r overwrite
    [[ "${overwrite}" =~ ^[Yy]$ ]] || { logInfo "Instalação cancelada"; return 1; }
    return 0
}

askLocalDestination() {
    local defaultDest="${INSTALL_DEST:-$(pwd)/${DEFAULT_LOCAL_DIR}}"

    logInfo "Diretório destino padrão: ${defaultDest}"
    read -p "Informe o diretório do projeto [ENTER para usar ${defaultDest}]: " -r userDest

    if [[ -n "${userDest}" ]]; then
        # Expandir ~ (read não expande tilde)
        if [[ "${userDest}" == "~/"* ]]; then
            userDest="${HOME}/${userDest#\~/}"
        elif [[ "${userDest}" == "~" ]]; then
            userDest="${HOME}"
        fi
        # Caminho relativo → absoluto
        if [[ "${userDest}" != /* ]]; then
            userDest="$(pwd)/${userDest}"
        fi
        # Usuário informa o projeto — adicionar subdiretório de instalação
        INSTALL_DEST="${userDest}/${DEFAULT_LOCAL_DIR}"
    else
        INSTALL_DEST="${defaultDest}"
    fi

    logInfo "Diretório destino: ${INSTALL_DEST}"
}

updateGitignore() {
    local projectRoot="$1"
    local gitignoreFile="${projectRoot}/.gitignore"

    logStep "Atualizando .gitignore"

    if [[ -f "${gitignoreFile}" ]]; then
        if grep -q ".claude/node_modules" "${gitignoreFile}" 2>/dev/null; then
            logInfo ".gitignore já contém entrada para .claude/node_modules"
            return 0
        fi
        echo "" >> "${gitignoreFile}"
        echo "# Claude Code workflow" >> "${gitignoreFile}"
        echo ".claude/node_modules/" >> "${gitignoreFile}"
    else
        echo "# Claude Code workflow" > "${gitignoreFile}"
        echo ".claude/node_modules/" >> "${gitignoreFile}"
    fi

    logSuccess ".gitignore atualizado"
}

configureTavilyMCP() {
    local targetDir="$1"
    local settingsJson="${targetDir}/settings.json"

    logStep "Configuração do Tavily MCP"

    # Se --no-tavily foi passado, manter desabilitado
    if [[ "${NO_TAVILY}" == "true" ]]; then
        logInfo "Tavily MCP: desabilitado via --no-tavily"
        return 0
    fi

    # Verificar se o settings.json tem a configuração Tavily
    if [[ ! -f "${settingsJson}" ]]; then
        logWarn "settings.json não encontrado em: ${settingsJson}"
        return 0
    fi

    # Verificar se já está configurado com chave real
    if grep -q '"url".*mcp.tavily.com' "${settingsJson}" 2>/dev/null; then
        if ! grep -q '${TAVILY_API_KEY}' "${settingsJson}" 2>/dev/null; then
            logInfo "Tavily MCP: já configurado com chave real"
            return 0
        fi
    fi

    # Verificar se já existe TAVILY_API_KEY no ambiente
    local tavilyKey="${API_KEY_TAVILY:-}"

    # Se não encontrou na variável de ambiente, perguntar ao usuário
    if [[ -z "${tavilyKey}" ]]; then
        logInfo "Tavily é um serviço de busca web que permite aos agentes:"
        logInfo "  - Buscar documentação atualizada"
        logInfo "  - Pesquisar bibliotecas e frameworks"
        logInfo "  - Obter dados em tempo real"
        logInfo ""
        logInfo "É gratuito para uso básico. Saiba mais em: https://tavily.com/"
        logInfo ""
        logInfo "Você pode configurar de 3 formas:"
        logInfo "  1. Pressione ENTER para pular (MCP permanece DESABILITADO)"
        logInfo "  2. Digite sua API key agora"
        logInfo "  3. Configure depois editando ${settingsJson} diretamente"
        echo ""
        read -s -p "API Key do Tavily (ou ENTER para pular): " tavilyKey
        echo ""  # newline após input secreto

        # Se usuário pressionou ENTER, sair mantendo desabilitado
        if [[ -z "${tavilyKey}" ]]; then
            logInfo "Tavily MCP: mantido desabilitado"
            return 0
        fi
    fi

    # Validar prefixo da API key
    if [[ ! "${tavilyKey}" =~ ^tvly- ]]; then
        logWarn "Chave informada não começa com 'tvly-'. Verifique se é válida."
        read -p "Continuar mesmo assim? [y/N]: " -r confirm
        [[ "${confirm}" =~ ^[Yy]$ ]] || { logInfo "Configuração skipada"; return 0; }
    fi

    # Substituir o placeholder pela key real
    # Usar sed com delimitador | para evitar escaping de /
    if sed -i \
        -e "s|\"enabled\": false|\"enabled\": true|" \
        -e "s|\\\${TAVILY_API_KEY}|${tavilyKey}|g" \
        "${settingsJson}"; then
        logSuccess "Tavily MCP configurado e habilitado"
        logInfo "  URL: https://mcp.tavily.com/mcp/"
        logWarn "  Nota: Não faça commit do arquivo settings.json com a chave"
    else
        logError "Falha ao configurar Tavily MCP. Edite manualmente: ${settingsJson}"
    fi
}

askModelProvider() {
    [[ -n "${MODEL_PROVIDER}" ]] && return 0

    echo ""
    logInfo "Qual provedor de modelo este projeto vai usar?"
    logInfo "  1) Claude (Anthropic) — padrão, requer login/assinatura Claude"
    logInfo "  2) Ollama Cloud — modelos abertos (glm-5.2, kimi-k2.7-code, deepseek-v4, etc.)"
    echo ""
    read -p "Escolha [1/2] (ENTER = 1): " -r providerChoice

    case "${providerChoice}" in
        2) MODEL_PROVIDER="ollama" ;;
        ""|1) MODEL_PROVIDER="claude" ;;
        *)
            logWarn "Opção inválida '${providerChoice}' — usando 'claude'"
            MODEL_PROVIDER="claude"
            ;;
    esac
}

applyModelProvider() {
    local targetDir="$1"
    local profileFile="${targetDir}/model-profiles/ollama.json"
    local settingsLocal="${targetDir}/settings.local.json"

    if [[ "${MODEL_PROVIDER}" == "claude" ]]; then
        logInfo "Provedor: Claude (Anthropic) — modelos padrão já aplicados pela cópia dos arquivos"
        # Limpa overrides de um flavor Ollama anterior, se existirem
        if [[ -f "${settingsLocal}" ]] && command -v jq > /dev/null 2>&1; then
            if jq -e '.env.ANTHROPIC_BASE_URL' "${settingsLocal}" > /dev/null 2>&1; then
                local tmpFile
                tmpFile="$(mktemp)"
                jq 'del(.env.ANTHROPIC_BASE_URL, .env.ANTHROPIC_AUTH_TOKEN, .env.ANTHROPIC_API_KEY, .env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY) | del(.model)
                    | if (.env // {}) == {} then del(.env) else . end' \
                    "${settingsLocal}" > "${tmpFile}" && mv "${tmpFile}" "${settingsLocal}"
                if [[ "$(jq -c '.' "${settingsLocal}")" == "{}" ]]; then
                    rm -f "${settingsLocal}"
                    logSuccess "settings.local.json: vazio após limpeza — removido"
                else
                    logSuccess "settings.local.json: overrides do provedor Ollama removidos"
                fi
            fi
        fi
        return 0
    fi

    # provider == ollama
    logStep "Aplicando flavor Ollama Cloud..."

    if ! command -v jq > /dev/null 2>&1; then
        logError "jq é obrigatório para aplicar o provedor Ollama (merge de settings.local.json)."
        logError "Instale jq e rode novamente: bash install-claude.sh --dest <path> --provider ollama"
        return 1
    fi

    if [[ ! -f "${profileFile}" ]]; then
        logError "Perfil não encontrado: ${profileFile}"
        return 1
    fi

    local agentName modelTag
    while IFS= read -r agentName; do
        modelTag=$(jq -r --arg k "${agentName}" '.agents[$k]' "${profileFile}")
        local agentFile="${targetDir}/agents/${agentName}.md"

        if [[ ! -f "${agentFile}" ]]; then
            logError "  Agente no perfil não existe no destino: ${agentName}.md (mapeamento desatualizado?)"
            return 1
        fi

        if ! grep -q '^model:' "${agentFile}"; then
            logError "  ${agentName}.md não tem linha 'model:' — abortando"
            return 1
        fi

        sed -i "s/^model:.*/model: ${modelTag}/" "${agentFile}"
        logInfo "  ${agentName} → ${modelTag}"
    done < <(jq -r '.agents | keys[]' "${profileFile}")

    local sessionModel envJson
    sessionModel=$(jq -r '.session.model' "${profileFile}")
    envJson=$(jq -c '.env' "${profileFile}")

    local tmpFile
    tmpFile="$(mktemp)"
    if [[ -f "${settingsLocal}" ]]; then
        jq --argjson envObj "${envJson}" --arg model "${sessionModel}" \
            '.env = ((.env // {}) + $envObj) | .model = $model' \
            "${settingsLocal}" > "${tmpFile}" && mv "${tmpFile}" "${settingsLocal}"
    else
        jq -n --argjson envObj "${envJson}" --arg model "${sessionModel}" \
            '{model: $model, env: $envObj}' > "${settingsLocal}"
    fi

    logSuccess "Sessão (Master/tech-lead): ${sessionModel}"
    logSuccess "settings.local.json atualizado com env do gateway Ollama"
    logWarn "Lembrete: exporte no shell/servidor Ollama o suporte a contexto maior (num_ctx) e mantenha o Ollama atualizado — ver conversa de setup para detalhes."
}

installLocal() {
    if [[ -z "${INSTALL_DEST}" ]]; then
        askLocalDestination
    fi

    local targetDir="${INSTALL_DEST}"
    local projectRoot
    projectRoot=$(dirname "${targetDir}")

    if [[ ! -f "${projectRoot}/package.json" && ! -d "${projectRoot}/.git" ]]; then
        logWarn "Diretório não parece ser um projeto (sem package.json ou .git)"
        read -p "Continuar mesmo assim? [y/N]: " -r continueAnyway
        [[ "${continueAnyway}" =~ ^[Yy]$ ]] || { logInfo "Instalação cancelada"; return 1; }
    fi

    logStep "Instalação LOCAL em: ${targetDir}"

    confirmOverwrite "${targetDir}" || return 1

    if [[ -d "${targetDir}/agents" ]]; then
        removeExistingInstallation "${targetDir}"
    fi

    copyWorkflowFiles "${targetDir}"
    installRtk "${targetDir}"
    updateGitignore "${projectRoot}"
    configureTavilyMCP "${targetDir}"

    askModelProvider
    applyModelProvider "${targetDir}"

    logSuccess "Instalação local concluída!"
    logInfo "Para compartilhar: git add .claude/ && git commit -m 'Add Claude Code workflow'"
}

# ==============================================================================
# VERIFICAÇÃO
# ==============================================================================

verifyInstallation() {
    local targetDir="$1"
    logStep "Verificando integridade em: ${targetDir}"

    local errors=0

    for item in "${CLAUDE_REQUIRED_ITEMS[@]}"; do
        if [[ -e "${targetDir}/${item}" ]]; then
            logSuccess "  Presente: ${item}"
        else
            logError "  Faltando: ${item}"
            ((errors++))
        fi
    done

    local agentCount
    agentCount=$(find "${targetDir}/agents" -name "*.md" 2>/dev/null | wc -l)
    if [[ ${agentCount} -ge 20 ]]; then
        logInfo "  Contagem de Agentes: ${agentCount} (OK)"
    else
        logError "  Contagem de Agentes: ${agentCount} (esperado: ≥20)"
        ((errors++))
    fi

    local skillCount
    skillCount=$(find "${targetDir}/skills" -name "SKILL.md" 2>/dev/null | wc -l)
    if [[ ${skillCount} -ge 5 ]]; then
        logInfo "  Contagem de Skills: ${skillCount} (OK)"
    else
        logError "  Contagem de Skills: ${skillCount} (esperado: ≥5)"
        ((errors++))
    fi

    local hookCount
    hookCount=$(find "${targetDir}/hooks" -type f 2>/dev/null | wc -l)
    if [[ ${hookCount} -ge 5 ]]; then
        logInfo "  Contagem de Hooks: ${hookCount} (OK)"
    else
        logError "  Contagem de Hooks: ${hookCount} (esperado: ≥5)"
        ((errors++))
    fi

    if [[ -f "${targetDir}/bin/rtk" && -x "${targetDir}/bin/rtk" ]]; then
        logSuccess "  Binário rtk: executável"
    else
        logWarn "  Binário rtk: não encontrado (download pode ter falhado — veja instruções manuais acima)"
    fi

    if [[ ${errors} -eq 0 ]]; then
        logSuccess "Instalação verificada com sucesso!"
        return 0
    fi
    logError "Instalação com ${errors} erro(s)"
    return 1
}

# ==============================================================================
# PARSING
# ==============================================================================

parseArguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dest)
                [[ -z "${2:-}" ]] && { logError "Opção --dest requer um caminho"; exit 1; }
                INSTALL_DEST="$2/${DEFAULT_LOCAL_DIR}"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                printHelp
                exit 0
                ;;
            --version)
                echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
                exit 0
                ;;
            --no-tavily)
                NO_TAVILY=true
                shift
                ;;
            --provider)
                [[ -z "${2:-}" ]] && { logError "Opção --provider requer 'claude' ou 'ollama'"; exit 1; }
                case "$2" in
                    claude|ollama) MODEL_PROVIDER="$2" ;;
                    *) logError "Provedor inválido: '$2' (use 'claude' ou 'ollama')"; exit 1 ;;
                esac
                shift 2
                ;;
            --rtk-version)
                [[ -z "${2:-}" ]] && { logError "Opção --rtk-version requer uma tag (ex.: v0.43.0)"; exit 1; }
                RTK_VERSION="$2"
                shift 2
                ;;
            # Compatibilidade: avisa e ignora flags removidas
            -g|--global|-H|--hybrid|-l|--local)
                logWarn "Flag '$1' foi removida — apenas instalação local é suportada"
                shift
                ;;
            *)
                logError "Opção desconhecida: $1"
                logInfo "Use --help para ver as opções disponíveis"
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    calculateMetrics
    printBanner

    if ! checkPrerequisites; then
        exit 1
    fi

    installLocal

    if [[ -n "${INSTALL_DEST}" ]]; then
        verifyInstallation "${INSTALL_DEST}"
    fi

    echo ""
    logSuccess "═══════════════════════════════════════════════════════════════"
    logSuccess "  Instalação concluída!"
    logSuccess "═══════════════════════════════════════════════════════════════"
    logInfo "Provedor configurado: ${MODEL_PROVIDER}"
    logInfo "Para começar: claude"
    logInfo ""
    logInfo "Próximos passos:"
    case ":${PATH}:" in
        *":${RTK_GLOBAL_BIN_DIR}:"*)
            logInfo "  1. 'rtk' já está no PATH (${RTK_GLOBAL_BIN_DIR})"
            ;;
        *)
            logWarn "  1. Adicione ${RTK_GLOBAL_BIN_DIR} ao PATH antes de abrir uma nova sessão de shell:"
            logInfo "     export PATH=\"${RTK_GLOBAL_BIN_DIR}:\$PATH\"   # adicione também no ~/.bashrc ou ~/.zshrc"
            ;;
    esac
    logInfo "  2. Reinicie o Claude Code para ativar hooks (RTK + Caveman)"
    logInfo "  3. Teste RTK: rtk gain"
    logInfo "  4. Teste Caveman: digite /caveman no chat"
}

parseArguments "$@"
main
