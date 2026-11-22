#!/usr/bin/env bash
# ============================================================================
# 🐉 DRAGON OS (龙) - MASTER INSTALLER & BOOTSTRAP (Camada D)
# Transforma Arch Linux / CachyOS no Dragon OS Completo
# ============================================================================

set -e

# Paleta Ink & Jade no Terminal
JADE='\033[38;2;0;168;107m'
GOLD='\033[38;2;212;175;55m'
CINNABAR='\033[38;2;227;66;52m'
RESET='\033[0m'
BOLD='\033[1m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRAGON_DIR="$HOME/.config/dragon-breath"
SCALES_DIR="$HOME/.local/share/dragon-scales"
WHISPER_DIR="$HOME/.local/share/dragon-whisper"
BACKUP_DIR="$HOME/.config/dragon-backup-$(date +%Y%m%d_%H%M%S)"

if [[ $EUID -eq 0 ]]; then
    echo -e "${CINNABAR}Não execute como root: os arquivos vão para o \$HOME do usuário. Rode como usuário comum (sudo é chamado quando preciso).${RESET}"
    exit 1
fi

clear
echo -e "${JADE}${BOLD}"
cat << "EOF"
   ___                              ____  _____
  / _ \_______ ____ ____  ___      / __ \/ ___/
 / // / __/ _ `/ _ `/ _ \/ _ \    / /_/ /\__ \ 
/____/_/  \_,_/\_, /\___/_//_/    \____/____/  
              /___/       [ 龙 - Ink & Jade Edition ]
EOF
echo -e "${RESET}"

# ----------------------------------------------------------------------------
# ETAPA 1: Detecção de Hardware e Classificação de Tier
# ----------------------------------------------------------------------------
echo -e "${GOLD}==> [1/7] Analisando Hardware e Memória Gráfica (VRAM)...${RESET}"

# lspci (pciutils) é necessário para detectar a GPU antes de qualquer outra coisa
command -v lspci >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm pciutils

GPU_VENDOR="CPU"
VRAM_MB=0
WHISPER_CMAKE_FLAGS=""
OLLAMA_PKG="ollama"
EXTRA_PKGS=()   # dependências de build do whisper.cpp conforme o backend

if command -v nvidia-smi >/dev/null 2>&1 || lspci | grep -qi "NVIDIA"; then
    GPU_VENDOR="NVIDIA"
    OLLAMA_PKG="ollama-cuda"
    WHISPER_CMAKE_FLAGS="-DGGML_CUDA=1"
    EXTRA_PKGS=(cuda)
    if command -v nvidia-smi >/dev/null 2>&1; then
        VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1 | tr -d ' ')
    else
        VRAM_MB=8192
    fi
# Só considera AMD se for a GPU (linha VGA/3D/Display), não a CPU AMD listada pelo lspci
elif lspci | grep -Ei "VGA|3D|Display" | grep -Eqi "AMD|ATI|Radeon"; then
    GPU_VENDOR="AMD"
    OLLAMA_PKG="ollama-rocm"
    WHISPER_CMAKE_FLAGS="-DGGML_VULKAN=1"
    EXTRA_PKGS=(vulkan-headers shaderc vulkan-icd-loader vulkan-radeon)
    for card in /sys/class/drm/card*/device/mem_info_vram_total; do
        if [[ -f "$card" ]]; then
            VRAM_BYTES=$(cat "$card")
            VRAM_MB=$((VRAM_BYTES / 1024 / 1024))
            [[ $VRAM_MB -gt 512 ]] && break
        fi
    done
fi

# Fallback para RAM compartilhada se APU/CPU
if [[ $VRAM_MB -lt 1024 ]]; then
    MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    VRAM_MB=$((MEM_TOTAL_KB / 1024))
    GPU_VENDOR="UMA/CPU"
    OLLAMA_PKG="ollama"
    WHISPER_CMAKE_FLAGS=""
    EXTRA_PKGS=()
fi

if [[ "$GPU_VENDOR" == "UMA/CPU" || $VRAM_MB -lt 6000 ]]; then
    DRAGON_TIER="Wyrm"
    DRAGON_ICON="🐍"
    DRAGON_MODEL="qwen2.5-coder:1.5b"
    VISION_MODEL="moondream"
    WHISPER_MODEL="base-q5_1"
elif [[ $VRAM_MB -lt 14000 ]]; then
    DRAGON_TIER="Drake"
    DRAGON_ICON="🦎"
    DRAGON_MODEL="qwen2.5-coder:7b"
    VISION_MODEL="moondream"
    WHISPER_MODEL="small-q5_1"
else
    DRAGON_TIER="Imperial Dragon"
    DRAGON_ICON="🐉"
    DRAGON_MODEL="qwen2.5-coder:14b"
    VISION_MODEL="llava"
    WHISPER_MODEL="small-q5_1"
fi

echo -e "    Hardware detectado : ${BOLD}${GPU_VENDOR} (${VRAM_MB} MB)${RESET}"
echo -e "    Edição selecionada : ${JADE}${BOLD}${DRAGON_ICON} ${DRAGON_TIER} Edition${RESET}"
echo -e "    Modelo Principal   : ${GOLD}${DRAGON_MODEL}${RESET} | Visão: ${GOLD}${VISION_MODEL}${RESET}"

# ----------------------------------------------------------------------------
# ETAPA 2: Instalação de Pacotes do Sistema (Wayland + Rust Coreutils + IA)
# ----------------------------------------------------------------------------
echo -e "\n${GOLD}==> [2/7] Instalando pacotes base, compositor Wayland e ferramentas Rust...${RESET}"

sudo pacman -Syu --needed --noconfirm \
    base-devel git cmake curl jq python python-pip python-numpy python-pymupdf \
    hyprland waybar rofi-wayland dunst ghostty starship zsh \
    wl-clipboard wtype grim slurp tesseract tesseract-data-por tesseract-data-eng \
    pipewire pipewire-pulse libnotify xdg-utils pciutils \
    eza bat ripgrep fd zoxide bottom \
    ttf-jetbrains-mono-nerd noto-fonts-cjk \
    "$OLLAMA_PKG" "${EXTRA_PKGS[@]}"

# ----------------------------------------------------------------------------
# ETAPA 3: Compilação do Whispering Wind (whisper.cpp)
# ----------------------------------------------------------------------------
echo -e "\n${GOLD}==> [3/7] Forjando módulo Whispering Wind (whisper.cpp)...${RESET}"

mkdir -p "$WHISPER_DIR"
if [[ ! -d "$WHISPER_DIR/.git" ]]; then
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi

[[ "$GPU_VENDOR" == "NVIDIA" ]] && export PATH="/opt/cuda/bin:$PATH"

pushd "$WHISPER_DIR" >/dev/null
cmake -B build -DCMAKE_BUILD_TYPE=Release $WHISPER_CMAKE_FLAGS
cmake --build build -j"$(nproc)" --config Release
sh ./models/download-ggml-model.sh "$WHISPER_MODEL"
# Cria link simbólico padronizado para o modelo ativo
ln -sf "$WHISPER_DIR/models/ggml-${WHISPER_MODEL}.bin" "$WHISPER_DIR/models/active-model.bin"
popd >/dev/null

# ----------------------------------------------------------------------------
# ETAPA 4: Instalação dos Módulos Core e Dotfiles (Com Backup Seguro)
# ----------------------------------------------------------------------------
echo -e "\n${GOLD}==> [4/7] Instalando módulos do Dragon OS e aplicando estética Ink & Jade...${RESET}"

mkdir -p "$DRAGON_DIR" "$SCALES_DIR" "$BACKUP_DIR"

# Exporta variáveis iniciais do Tier (o dragond mantém este arquivo atualizado depois)
cat << EOF > "$DRAGON_DIR/dragon_env.sh"
export DRAGON_TIER="$DRAGON_TIER"
export DRAGON_MODEL="$DRAGON_MODEL"
export DRAGON_VISION_MODEL="$VISION_MODEL"
EOF

# Copia scripts do diretório core/ se existirem no repositório
if [[ -d "$REPO_DIR/core" ]]; then
    cp -r "$REPO_DIR/core/"* "$DRAGON_DIR/"
    chmod +x "$DRAGON_DIR/"*.py "$DRAGON_DIR/"*.sh 2>/dev/null || true
fi

# Função de backup e link/cópia de dotfiles
deploy_config() {
    local src="$1"
    local dest="$2"
    if [[ -e "$dest" ]]; then
        # Backup preservando o caminho relativo ao $HOME (evita colisão de nomes como 'config')
        local rel="${dest#$HOME/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        mv "$dest" "$BACKUP_DIR/$rel"
    fi
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
}

if [[ -d "$REPO_DIR/dotfiles" ]]; then
    deploy_config "$REPO_DIR/dotfiles/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
    deploy_config "$REPO_DIR/dotfiles/waybar" "$HOME/.config/waybar"
    deploy_config "$REPO_DIR/dotfiles/ghostty/config" "$HOME/.config/ghostty/config"
    deploy_config "$REPO_DIR/dotfiles/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
    deploy_config "$REPO_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
fi

# Configura Zsh + Starship + Dragon Shell
if ! grep -q "dragon-shell.zsh" "$HOME/.zshrc" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.zshrc"

# --- Dragon OS (龙) Shell Integration ---
eval "$(starship init zsh)"
[[ -f "$HOME/.config/dragon-breath/dragon-shell.zsh" ]] && source "$HOME/.config/dragon-breath/dragon-shell.zsh"
EOF
fi

# Torna o Zsh o shell de login (sem isso Ctrl+G / wtf não funcionam no terminal)
if [[ "$(basename "${SHELL:-}")" != "zsh" ]]; then
    chsh -s "$(command -v zsh)" || echo -e "${CINNABAR}    Não foi possível trocar o shell padrão; rode manualmente: chsh -s $(command -v zsh)${RESET}"
fi

# ----------------------------------------------------------------------------
# ETAPA 5: Criação e Ativação dos Serviços Systemd (User & System)
# ----------------------------------------------------------------------------
echo -e "\n${GOLD}==> [5/7] Configurando Daemons (Ollama, dragond, Scales e Whisper)...${RESET}"

sudo systemctl enable --now ollama.service
mkdir -p "$HOME/.config/systemd/user"

# 1. dragond.service
cat << 'EOF' > "$HOME/.config/systemd/user/dragond.service"
[Unit]
Description=Dragon OS Core Daemon (Hardware Tier & VRAM Manager)
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.config/dragon-breath/dragond.py
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

# 2. dragon-scales.service & timer
cat << 'EOF' > "$HOME/.config/systemd/user/dragon-scales.service"
[Unit]
Description=Dragon OS Scales - Indexador Vetorial Local (RAG)

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/bin/python3 %h/.config/dragon-breath/scales_indexer.py
EOF

cat << 'EOF' > "$HOME/.config/systemd/user/dragon-scales.timer"
[Unit]
Description=Executa o indexador Dragon Scales a cada 15 minutos

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
EOF

# 3. dragon-whisper.service
cat << 'EOF' > "$HOME/.config/systemd/user/dragon-whisper.service"
[Unit]
Description=Dragon OS Whispering Wind - Servidor Local whisper.cpp
After=default.target

[Service]
Type=simple
WorkingDirectory=%h/.local/share/dragon-whisper
ExecStart=%h/.local/share/dragon-whisper/build/bin/whisper-server -m models/active-model.bin -l pt -t 4 --host 127.0.0.1 --port 8178
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now dragond.service
systemctl --user enable --now dragon-scales.timer
systemctl --user enable --now dragon-whisper.service

# ----------------------------------------------------------------------------
# ETAPA 6: Download dos Modelos de IA Open-Source no Ollama
# ----------------------------------------------------------------------------
echo -e "\n${GOLD}==> [6/7] Baixando modelos de IA locais para a edição ${DRAGON_TIER}...${RESET}"

# Espera a API do Ollama responder (até 30s) antes de baixar os modelos
for _ in $(seq 1 30); do
    curl -sf http://127.0.0.1:11434/api/version >/dev/null && break
    sleep 1
done

ollama pull nomic-embed-text
ollama pull "$DRAGON_MODEL"
ollama pull "$VISION_MODEL"

# ----------------------------------------------------------------------------
# ETAPA 7: Indexação Inicial e Conclusão
# ----------------------------------------------------------------------------
echo -e "\n${GOLD}==> [7/7] Disparando indexação inicial do Dragon Scales em segundo plano...${RESET}"
# --no-block: o serviço é oneshot e, sem isso, o instalador esperaria a indexação terminar
systemctl --user start --no-block dragon-scales.service || true

echo -e "\n${JADE}${BOLD}============================================================================${RESET}"
echo -e "${JADE}${BOLD}🐉 DRAGON OS (${DRAGON_TIER} Edition) INSTALADO COM SUCESSO!${RESET}"
echo -e "${JADE}${BOLD}============================================================================${RESET}"
echo -e "  • ${GOLD}Super + Space${RESET}         : Launcher de Aplicativos (Rofi Ink & Jade)"
echo -e "  • ${GOLD}Super + Shift + Space${RESET} : Dragon Breath (IA Global, '@' clipboard, '#' RAG Scales)"
echo -e "  • ${GOLD}Super + V${RESET}             : Whispering Wind (Ditado por voz offline)"
echo -e "  • ${GOLD}Super + Shift + S${RESET}     : Dragon Eye (OCR e Visão Computacional na tela)"
echo -e "  • ${GOLD}Ctrl + G (no Zsh)${RESET}     : Traduz linguagem natural em comando Linux"
echo -e "  • ${GOLD}wtf (no Zsh)${RESET}          : Explica e corrige o último erro do terminal"
echo -e "\nBackup das suas configurações anteriores salvo em: ${BACKUP_DIR}"
