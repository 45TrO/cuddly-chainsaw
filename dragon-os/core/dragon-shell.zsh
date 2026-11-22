# ============================================================================
# 🐉 DRAGON SHELL (龙壳) - Inteligência Nativa e Coreutils em Rust
# ============================================================================

# 1. Carrega o Tier e o Modelo definidos pelo dragond
[[ -f "$HOME/.config/dragon-breath/dragon_env.sh" ]] && source "$HOME/.config/dragon-breath/dragon_env.sh"
export DRAGON_MODEL="${DRAGON_MODEL:-qwen2.5-coder:3b}"
export OLLAMA_HOST="http://127.0.0.1:11434"

# 2. Substituição Transparente por Ferramentas em Rust (O Corpo Ágil)
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -lh --icons=auto --git --group-directories-first'
    alias la='eza -lah --icons=auto --git --group-directories-first'
    alias lt='eza --tree --level=2 --icons=auto'
fi

command -v bat >/dev/null 2>&1 && alias cat='bat --style=plain --paging=never'
command -v rg >/dev/null 2>&1  && alias grep='rg'
command -v fd >/dev/null 2>&1  && alias find='fd'
command -v btm >/dev/null 2>&1 && alias top='btm'
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --cmd cd)"

# 3. Widget ZLE: Tradutor de Linguagem Natural In-Place (Atalho: Ctrl + G)
# Digite o que quer fazer na linha de comando e pressione Ctrl+G.
_dragon_translate_line() {
    [[ -z "$BUFFER" ]] && return

    local user_intent="$BUFFER"
    BUFFER="🐉 [Sopro do Dragão forjando comando...] $user_intent"
    zle redisplay

    local sys_prompt="Você é o gerador de comandos Zsh/Linux do Dragon OS (Arch Linux). Retorne EXCLUSIVAMENTE o comando executável em uma única linha, sem blocos markdown, sem crases e sem explicações. Prefira ferramentas modernas (fd, rg, eza, ffmpeg, git, pacman) quando apropriado."

    local payload=$(jq -n \
        --arg model "$DRAGON_MODEL" \
        --arg prompt "$user_intent" \
        --arg system "$sys_prompt" \
        '{model: $model, prompt: $prompt, system: $system, stream: false, keep_alive: "30m", options: {temperature: 0.05, num_predict: 120}}')

    local response=$(curl -s --max-time 15 "$OLLAMA_HOST/api/generate" -d "$payload" | jq -r '.response // empty')

    # Limpa eventuais crases ou quebras de linha
    local clean_cmd=$(echo "$response" | sed -E 's/^```[a-zA-Z]*//; s/```$//; s/`//g' | tr '\n' ' ' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')

    if [[ -n "$clean_cmd" ]]; then
        BUFFER="$clean_cmd"
        CURSOR=${#BUFFER}
    else
        BUFFER="$user_intent"
        zle -M "⚠️ Dragon Shell: Falha ao contatar o Ollama ($DRAGON_MODEL)."
    fi
    zle redisplay
}

zle -N _dragon_translate_line
bindkey '^G' _dragon_translate_line

# 4. Captura de Contexto e Diagnóstico de Erros ('wtf')
# Registra o último comando executado e seu código de saída
autoload -Uz add-zsh-hook

_dragon_preexec() {
    # Não sobrescreve o contexto quando o próprio wtf/ask é executado
    case "${1%% *}" in
        wtf|ask) return ;;
    esac
    export _DRAGON_LAST_CMD="$1"
    _DRAGON_CAPTURE_EXIT=1
}

_dragon_precmd() {
    local rc="$?"
    # Só atualiza o código de saída se um comando "de verdade" rodou
    if [[ -n "$_DRAGON_CAPTURE_EXIT" ]]; then
        export _DRAGON_LAST_EXIT="$rc"
        unset _DRAGON_CAPTURE_EXIT
    fi
}

add-zsh-hook preexec _dragon_preexec
add-zsh-hook precmd _dragon_precmd
# Garante que nosso precmd rode ANTES dos demais (starship etc.), senão $? já foi sobrescrito
precmd_functions=(_dragon_precmd ${precmd_functions:#_dragon_precmd})

wtf() {
    if [[ -z "$_DRAGON_LAST_CMD" ]]; then
        echo "\033[38;2;212;175;55m🐉 Nenhum comando anterior registrado nesta sessão.\033[0m"
        return 0
    fi

    echo "\033[38;2;0;168;107m🐉 Analisando falha do comando:\033[0m \033[1m$_DRAGON_LAST_CMD\033[0m (Exit Code: $_DRAGON_LAST_EXIT)..."

    # Captura as últimas 15 linhas de erro reexecutando ou avaliando o comando se seguro,
    # ou envia o comando e o código de erro para diagnóstico.
    local query="Comando executado no Arch Linux: \`$_DRAGON_LAST_CMD\` (Código de saída: $_DRAGON_LAST_EXIT). Explique em 1 frase curta por que falhou e mostre o comando corrigido exato."

    local payload=$(jq -n \
        --arg model "$DRAGON_MODEL" \
        --arg prompt "$query" \
        --arg system "Seja cirúrgico e direto. Responda em português no formato:\nCausa: <explicação curta>\nCorreção: <comando corrigido>" \
        '{model: $model, prompt: $prompt, system: $system, stream: false, keep_alive: "30m", options: {temperature: 0.1, num_predict: 180}}')

    local answer=$(curl -s "$OLLAMA_HOST/api/generate" -d "$payload" | jq -r '.response // "Erro ao conectar ao Ollama."')

    echo "\n\033[38;2;212;175;55m$answer\033[0m\n"
}

# 5. Atalho rápido 'ask' para perguntas diretas no terminal com streaming
ask() {
    if [[ -z "$*" ]]; then
        echo "Uso: ask <sua pergunta técnica>"
        return 1
    fi
    local payload=$(jq -n \
        --arg model "$DRAGON_MODEL" \
        --arg prompt "$*" \
        '{model: $model, prompt: $prompt, stream: true, keep_alive: "30m", options: {temperature: 0.2}}')

    echo -ne "\033[38;2;0;168;107m🐉 [$DRAGON_MODEL]: \033[0m"
    curl -sN "$OLLAMA_HOST/api/generate" -d "$payload" | while read -r line; do
        printf "%s" "$(echo "$line" | jq -r '.response // empty')"
    done
    echo ""
}
