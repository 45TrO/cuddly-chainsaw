#!/usr/bin/env bash
# Dragon Hoard (龙藏) - Histórico de Clipboard + Ações Rápidas de IA

ROFI_THEME="$HOME/.config/dragon-breath/config.rasi"
DRAGONCTL="$HOME/.config/dragon-breath/dragonctl"
source "$HOME/.config/dragon-breath/dragon_env.sh" 2>/dev/null
MODEL="${DRAGON_MODEL:-}"   # vazio: o dragonctl usa o modelo do Tier (dragond)

# Lista o histórico no Rofi (Enter = Cola normal | Alt+1 = Passa pela IA)
SELECTION=$(cliphist list | rofi -dmenu -p "🐉 Hoard" \
    -mesg "Enter: Copiar | Alt+1: Refinar/Traduzir/Formatar com IA" \
    -kb-custom-1 "Alt+1" \
    -theme "$ROFI_THEME")
EXIT_CODE=$?

[[ -z "$SELECTION" ]] && exit 0

if [[ $EXIT_CODE -eq 0 ]]; then
    # Decodifica direto no wl-copy: preserva imagens/binários (variáveis do bash perdem bytes NUL)
    printf '%s' "$SELECTION" | cliphist decode | wl-copy
    exit 0
elif [[ $EXIT_CODE -eq 10 ]]; then
    CONTENT=$(printf '%s' "$SELECTION" | cliphist decode)
    ACTION=$(printf "✨ Formatar / Limpar (JSON, SQL, Código)\n🌐 Traduzir para Português\n🛠️ Refatorar e otimizar código\n📝 Resumir em 3 tópicos" | \
        rofi -dmenu -p "🐉 Transformar:" -theme "$ROFI_THEME")
    [[ -z "$ACTION" ]] && exit 0

    notify-send -u low -t 2000 "🐉 Dragon Hoard" "Transformando clipboard com ${MODEL:-o modelo do Tier}..."

    RESULT=$(printf '%s' "$CONTENT" | "$DRAGONCTL" gen --mode hoard ${MODEL:+--model "$MODEL"} -- "Ação: $ACTION" 2>/dev/null)
    if [[ -n "$RESULT" ]]; then
        printf '%s' "$RESULT" | wl-copy
        notify-send -u low -t 3000 "🐉 Dragon Hoard" "Pronto! Novo conteúdo já está no seu Ctrl+V."
    else
        notify-send -u normal -t 4000 "🐉 Dragon Hoard" "Falha ao contatar o Ollama."
    fi
fi
