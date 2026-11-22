#!/usr/bin/env bash
# Dragon OS - Módulo Whispering Wind (风语)

# Áudio e PID só do usuário: em /tmp outros usuários poderiam ler o ditado ou forjar o PID
RUNTIME="${XDG_RUNTIME_DIR:-$HOME/.cache/dragon-runtime}"
# shellcheck disable=SC2174  # só a pasta final precisa ser 0700
mkdir -p -m 700 "$RUNTIME"
umask 077
PID_FILE="$RUNTIME/whispering_wind.pid"
AUDIO_FILE="$RUNTIME/whispering_wind.wav"
SERVER_URL="http://127.0.0.1:8178/inference"
CLI_BIN="$HOME/.local/share/dragon-whisper/build/bin/whisper-cli"
MODEL_PATH="$HOME/.local/share/dragon-whisper/models/active-model.bin"

# Se já estiver gravando, para a gravação e transcreve
if [ -f "$PID_FILE" ]; then
    REC_PID=$(cat "$PID_FILE")
    rm -f "$PID_FILE"

    # Só sinaliza se o PID for mesmo o pw-record (arquivo velho ou forjado não mata outro processo)
    if [[ "$REC_PID" =~ ^[0-9]+$ ]] && [[ "$(ps -o comm= -p "$REC_PID" 2>/dev/null)" == pw-record ]]; then
        # Interrompe o pw-record com SIGINT para fechar o cabeçalho WAV corretamente
        kill -SIGINT "$REC_PID" 2>/dev/null
        # 'wait' não funciona entre execuções diferentes do script: espera o processo sair
        for _ in $(seq 1 40); do kill -0 "$REC_PID" 2>/dev/null || break; sleep 0.05; done
    fi

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
    # Remove também caracteres de controle: o texto vira teclas digitadas na janela em foco
    CLEAN_TEXT=$(printf '%s' "$RAW_TEXT" | tr '\n' ' ' | tr -d '\000-\010\013-\037\177' \
        | sed -E 's/\[[^]]*\]//g; s/\([^)]*\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//')

    if [ -n "$CLEAN_TEXT" ]; then
        # Copia para o clipboard como segurança e digita na janela ativa via Wayland
        printf '%s' "$CLEAN_TEXT" | wl-copy
        sleep 0.08 # Pequena pausa para garantir que a janela mantenha o foco
        # '--': texto que comece com '-' (ex.: "-k Return") não vira opção do wtype
        wtype -- "$CLEAN_TEXT"
        # Escapa o markup do Dunst no corpo da notificação
        SAFE_BODY=$(printf '%s' "$CLEAN_TEXT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        notify-send -t 2000 -u low -h string:x-canonical-private-synchronous:whisper \
            "🐉 Sussurro Enviado" "$SAFE_BODY"
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
