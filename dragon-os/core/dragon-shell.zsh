# ============================================================================
# 🐉 DRAGON SHELL (龙壳) - Inteligência Nativa e Coreutils em Rust
# ============================================================================

# 1. Carrega o Tier e o Modelo definidos pelo dragond
[[ -f "$HOME/.config/dragon-breath/dragon_env.sh" ]] && source "$HOME/.config/dragon-breath/dragon_env.sh"
# Sem dragon_env.sh, o dragonctl resolve o modelo pelo estado do dragond
export OLLAMA_HOST="http://127.0.0.1:11434"

# dragonctl: CLI unificada de IA (v1.5). Todo o acesso ao Ollama passa por ela.
DRAGONCTL="$HOME/.config/dragon-breath/dragonctl"
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

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

    local clean_cmd
    clean_cmd=$("$DRAGONCTL" gen --mode shell --one-line --max-tokens 120 --timeout 15 -t 0.05 -- "$user_intent" 2>/dev/null </dev/null)

    if [[ -n "$clean_cmd" ]]; then
        BUFFER="$clean_cmd"
        CURSOR=${#BUFFER}
    else
        BUFFER="$user_intent"
        zle -M "⚠️ Dragon Shell: Falha ao contatar o Ollama (${DRAGON_MODEL:-modelo do Tier})."
    fi
    zle redisplay
}

zle -N _dragon_translate_line
bindkey '^G' _dragon_translate_line

# 4. Captura de Contexto e Diagnóstico de Erros ('wtf')
# Registra o último comando executado e seu código de saída
autoload -Uz add-zsh-hook

_dragon_preexec() {
    # Não sobrescreve o contexto quando os próprios atalhos de IA são executados
    case "${1%% *}" in
        wtf|ask|gcai) return ;;
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

    local query="Comando executado no Arch Linux: \`$_DRAGON_LAST_CMD\` (Código de saída: $_DRAGON_LAST_EXIT). Explique em 1 frase curta por que falhou e mostre o comando corrigido exato."
    local answer
    answer=$("$DRAGONCTL" gen --mode wtf --max-tokens 180 -- "$query" </dev/null 2>&1) || answer="Erro ao conectar ao Ollama."

    echo "\n\033[38;2;212;175;55m$answer\033[0m\n"
}

# 5. Atalho rápido 'ask' para perguntas diretas no terminal com streaming
ask() {
    if [[ -z "$*" ]]; then
        echo "Uso: ask <sua pergunta técnica>"
        return 1
    fi
    "$DRAGONCTL" ask -- "$*"
}

# 6. Git Commit AI (gcai) - Gera Conventional Commit a partir do git diff --staged
gcai() {
    local diff_content=$(git diff --staged --stat -p | head -c 3500)
    if [[ -z "$diff_content" ]]; then
        echo "\033[38;2;227;66;52m⚠️ Nenhuma alteração no stage. Use 'git add' primeiro.\033[0m"
        return 1
    fi

    echo -ne "\033[38;2;0;168;107m🐉 Analisando diff e forjando mensagem de commit...\033[0m\r"

    local msg
    msg=$(print -r -- "$diff_content" | "$DRAGONCTL" gen --mode commit --one-line --max-tokens 60 2>/dev/null | tr -d '"')
    echo -ne "\033[2K" # Limpa a linha de loading

    if [[ -n "$msg" ]]; then
        # ${(qq)msg}: aspas simples seguras — '$', '!' ou '$(...)' vindos do modelo não são expandidos ao dar Enter
        print -z "git commit -m ${(qq)msg}"
    else
        echo "Falha ao gerar mensagem de commit."
    fi
}

# 7. Boas-vindas com fastfetch no primeiro shell interativo (DRAGON_NO_FETCH=1 desativa)
if [[ -o interactive && -z "$DRAGON_NO_FETCH" && "$SHLVL" -le 1 ]] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch
fi
