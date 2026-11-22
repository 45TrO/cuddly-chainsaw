#!/usr/bin/env bash
# Dragon OS - Abertura pós-login (fase 4 do boot: o brilho final revela a área de trabalho)
# O Plymouth cobre as fases 1-3 (log em jade, nanquim, voo do dragão). Aqui toca o clarão
# final por cima do desktop e, se o login foi automático, sela a sessão com o hyprlock.

INTRO="$HOME/.config/dragon-breath/assets/intro.mp4"

AUTOLOGIN=0
grep -qs '^\[initial_session\]' /etc/greetd/config.toml && AUTOLOGIN=1

# Login automático => sessão aberta sem senha até o hyprlock subir. Durante o vídeo os
# atalhos ficam desligados (submap vazio 'dragon_lockdown') e o vídeo tem no máximo 3 s.
if [[ $AUTOLOGIN == 1 ]]; then
    hyprctl dispatch submap dragon_lockdown >/dev/null 2>&1
fi

if [[ "${DRAGON_INTRO:-1}" != 0 && -f "$INTRO" ]] && command -v mpv >/dev/null 2>&1; then
    timeout 3 mpv --fs --no-border --no-osc --no-osd-bar --no-input-default-bindings \
        --really-quiet --wayland-app-id=dragon-intro "$INTRO" || true
fi

# Sela a sessão sempre depois do vídeo, mesmo que o mpv falhe ou não exista
if [[ $AUTOLOGIN == 1 ]]; then
    hyprlock --immediate &
    LOCK_PID=$!
    sleep 0.5                                  # o bloqueio já está ativo: atalhos podem voltar
    hyprctl dispatch submap reset >/dev/null 2>&1
    wait "$LOCK_PID"
fi
