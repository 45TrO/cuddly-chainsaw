#!/usr/bin/env bash
# Dragon OS - Abertura pós-login (fase 4 do boot: o brilho final revela a área de trabalho)
# O Plymouth cobre as fases 1-3 (log em jade, nanquim, voo do dragão). Aqui toca o clarão
# final por cima do desktop e, se o login foi automático, sela a sessão com o hyprlock.

INTRO="$HOME/.config/dragon-breath/assets/intro.mp4"

if [[ "${DRAGON_INTRO:-1}" != 0 && -f "$INTRO" ]] && command -v mpv >/dev/null 2>&1; then
    timeout 8 mpv --fs --no-border --no-osc --no-osd-bar --no-input-default-bindings \
        --really-quiet --wayland-app-id=dragon-intro "$INTRO" || true
fi

# Login automático (greetd initial_session) => a sessão precisa ser selada.
# Roda sempre depois do vídeo, mesmo que o mpv falhe ou não exista.
if grep -qs '^\[initial_session\]' /etc/greetd/config.toml; then
    exec hyprlock
fi
