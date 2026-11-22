#!/usr/bin/env bash
# Sanctuary Mode (Modo Santuário) - Zero distrações e foco total no Hyprland

RUNTIME="${XDG_RUNTIME_DIR:-$HOME/.cache/dragon-runtime}"
# shellcheck disable=SC2174  # só a pasta final precisa ser 0700
mkdir -p -m 700 "$RUNTIME"
STATE_FLAG="$RUNTIME/dragon_sanctuary.lock"

if [[ -f "$STATE_FLAG" ]]; then
    rm -f "$STATE_FLAG"
    hyprctl --batch "\
        keyword general:gaps_in 5;\
        keyword general:gaps_out 10;\
        keyword decoration:rounding 10;\
        keyword decoration:dim_inactive false" >/dev/null
    killall -SIGUSR2 waybar 2>/dev/null || waybar &
    dunstctl set-paused false
    notify-send -u low -t 2000 "🐉 Modo Santuário Desativado" "Interface completa restaurada."
else
    touch "$STATE_FLAG"
    notify-send -u low -t 1500 "🧘 Modo Santuário Ativo" "Notificações silenciadas e foco máximo. (Super + Z para sair)"
    sleep 1.6
    dunstctl set-paused true
    killall -SIGUSR1 waybar 2>/dev/null
    hyprctl --batch "\
        keyword general:gaps_in 0;\
        keyword general:gaps_out 0;\
        keyword decoration:rounding 0;\
        keyword decoration:dim_inactive true;\
        keyword decoration:dim_strength 0.25" >/dev/null
fi
