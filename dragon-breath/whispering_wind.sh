#!/usr/bin/env bash
# Dragon OS - Módulo Whispering Wind (风语)

PID_FILE="/tmp/whispering_wind.pid"
AUDIO_FILE="/tmp/whispering_wind.wav"
SERVER_URL="http://127.0.0.1:8178/inference"
CLI_BIN="$HOME/.local/share/dragon-whisper/build/bin/whisper-cli"
MODEL_PATH="$HOME/.local/share/dragon-whisper/models/ggml-small-q5_1.bin"

# Se já estiver gravando, para a gravação e transcreve
if [ -f "$PID_FILE" ]; then
    REC_PID=$(cat "$PID_FILE")
    rm -f "$PID_FILE"

    # Interrompe o pw-record com SIGINT para fechar o cabeçalho WAV corretamente
    kill -SIGINT "$REC_PID" 2>/dev/null
    wait "$REC_PID" 2>/dev/null

    notify-send -t 1200 -u low -h string:x-canonical-private-synchronous:whisper \
        "🐉 Whispering Wind" "Transcrevendo..."

    # Tenta usar o servidor ultra-rápido; se estiver offline, usa o binário CLI como fallback
    if curl -s --head "http://127.0.0.1:8178" >/dev/null; then
        RAW_TEXT=$(curl -s -X POST "$SERVER_URL" \
            -F "file=@${AUDIO_FILE}" \
            -F "temperature=0.0" \
            -F "response_format=json" | jq -r '.text')
    else
        RAW_TEXT=$("$CLI_BIN" -m "$MODEL_PATH" -f "$AUDIO_FILE" -l pt -nt -np 2>/dev/null)
    fi

    # Limpa espaços extras, quebras de linha e alucinações de silêncio do Whisper
    CLEAN_TEXT=$(echo "$RAW_TEXT" | tr '\n' ' ' | sed -E 's/\[.*\]//g; s/\(.*\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//')

    if [ -n "$CLEAN_TEXT" ]; then
        # Copia para o clipboard como segurança e digita na janela ativa via Wayland
        wl-copy "$CLEAN_TEXT"
        sleep 0.08 # Pequena pausa para garantir que a janela mantenha o foco
        wtype "$CLEAN_TEXT"
        notify-send -t 2000 -u low -h string:x-canonical-private-synchronous:whisper \
            "🐉 Sussurro Enviado" "$CLEAN_TEXT"
    else
        notify-send -t 1500 -u low -h string:x-canonical-private-synchronous:whisper \
            "🐉 Whispering Wind" "Nenhuma fala detectada."
    fi

    rm -f "$AUDIO_FILE"
    exit 0
fi

# Caso não esteja gravando: inicia captura em 16kHz Mono 16-bit (formato nativo do Whisper)
rm -f "$AUDIO_FILE"
pw-record --rate 16000 --channels 1 --format s16 "$AUDIO_FILE" &
echo $! > "$PID_FILE"

notify-send -t 30000 -u normal -h string:x-canonical-private-synchronous:whisper \
    "🎙️ Whispering Wind" "Ouvindo... (Pressione Super + V para concluir)"
