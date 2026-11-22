#!/usr/bin/env bash
# ============================================================================
# 🐉 DRAGON OS - Gera os assets da abertura a partir de um vídeo
#   uso: make-boot-assets.sh <video.mp4> <pasta_saida>
# Saída:
#   <saida>/plymouth/frame-NNN.png  -> fases 2-3 (nanquim + voo do dragão) no Plymouth
#   <saida>/intro.mp4               -> fase 4 (clarão final) tocada pelo Hyprland após o login
#   <saida>/wallpaper.png           -> papel de parede
# Os cortes (em segundos) podem ser ajustados por variável de ambiente para outro vídeo.
# ============================================================================
set -euo pipefail

VIDEO="${1:?uso: $0 <video.mp4> <pasta_saida>}"
OUT="${2:?uso: $0 <video.mp4> <pasta_saida>}"

INK_START="${INK_START:-1.5}"       # início do nanquim (pula o log falso do vídeo)
FLARE_START="${FLARE_START:-7.25}"  # dragão enrolado, logo antes do clarão
FLARE_END="${FLARE_END:-7.7}"       # pico do clarão (depois disso o vídeo já mostra outro desktop)
WALL_AT="${WALL_AT:-7.0}"           # quadro usado como papel de parede
FPS="${FPS:-12}"
WIDTH="${WIDTH:-854}"               # quadros menores = initramfs menor e boot mais rápido

command -v ffmpeg >/dev/null || { echo "ffmpeg não encontrado" >&2; exit 1; }

rm -rf "$OUT/plymouth"
mkdir -p "$OUT/plymouth"

# PNG com paleta de 256 cores por quadro: ~1/2 do tamanho (os quadros vão para o initramfs)
echo "==> Quadros do Plymouth (${INK_START}s → ${FLARE_START}s, ${FPS} fps, ${WIDTH}px)..."
ffmpeg -v error -y -ss "$INK_START" -to "$FLARE_START" -i "$VIDEO" -an \
    -vf "fps=${FPS},scale=${WIDTH}:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=single[p];[b][p]paletteuse=new=1:dither=sierra2_4a" \
    -compression_level 9 -start_number 0 \
    "$OUT/plymouth/frame-%03d.png"

echo "==> Clarão final para o Hyprland (${FLARE_START}s → ${FLARE_END}s)..."
ffmpeg -v error -y -ss "$FLARE_START" -to "$FLARE_END" -i "$VIDEO" \
    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart \
    "$OUT/intro.mp4"

echo "==> Papel de parede (quadro em ${WALL_AT}s)..."
ffmpeg -v error -y -ss "$WALL_AT" -i "$VIDEO" -frames:v 1 -vf "scale=1920:-2:flags=lanczos" \
    "$OUT/wallpaper.png"

COUNT=$(find "$OUT/plymouth" -name 'frame-*.png' | wc -l)
echo "==> ${COUNT} quadros, $(du -sh "$OUT/plymouth" | cut -f1) em quadros do Plymouth."
