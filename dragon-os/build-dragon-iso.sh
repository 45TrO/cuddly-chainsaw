#!/usr/bin/env bash
# ============================================================================
# 🐉 DRAGON OS - GERADOR DE IMAGEM ISO BOOTÁVEL (archiso)
# Requer um host Arch Linux / CachyOS (usa pacman e mkarchiso).
# ============================================================================
set -e

WORK_DIR="/tmp/dragon-archiso-work"
OUT_DIR="$PWD/out-iso"
PROFILE_DIR="/tmp/dragon-profile"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Instalando archiso..."
sudo pacman -S --needed --noconfirm archiso ffmpeg

echo "==> Preparando perfil base releng do Arch Linux..."
sudo rm -rf "$PROFILE_DIR" "$WORK_DIR"
cp -r /usr/share/archiso/configs/releng "$PROFILE_DIR"

# 1. Adiciona os pacotes do Dragon OS na lista da ISO
cat << 'EOF' >> "$PROFILE_DIR/packages.x86_64"
hyprland
waybar
rofi-wayland
dunst
ghostty
starship
zsh
wl-clipboard
wtype
grim
slurp
tesseract
tesseract-data-por
tesseract-data-eng
pipewire
pipewire-pulse
libnotify
eza
bat
ripgrep
fd
zoxide
bottom
jq
python
python-numpy
python-pymupdf
ttf-jetbrains-mono-nerd
noto-fonts-cjk
ollama
cliphist
hyprlock
hyprpaper
inotify-tools
nwg-dock-hyprland
fastfetch
mpv
EOF

# Assets da abertura gerados uma vez (papel de parede e clarão final; o Plymouth não roda na ISO live)
ASSETS_TMP="$(mktemp -d)"
trap 'rm -rf "$ASSETS_TMP"' EXIT
"$REPO_DIR/boot/make-boot-assets.sh" "$REPO_DIR/assets/boot-intro.mp4" "$ASSETS_TMP"

# 2. Injeta os arquivos do Dragon OS na ISO.
#    O usuário live do releng é o root (home /root, populado por airootfs/root),
#    então os arquivos vão para /root e também para /etc/skel (usuários criados depois).
inject_home() {
    local dest="$1"
    mkdir -p "$dest/.config/dragon-breath" "$dest/.config/hypr" "$dest/dragon-os"

    # Cópia do repositório sem a pasta de saída da ISO nem o .git (o instalador roda a partir dela)
    tar -C "$REPO_DIR" --exclude=./out-iso --exclude=./.git -cf - . | tar -C "$dest/dragon-os" -xf -

    [[ -d "$REPO_DIR/core" ]] && cp -r "$REPO_DIR/core/"* "$dest/.config/dragon-breath/"
    cp "$REPO_DIR/VERSION" "$dest/.config/dragon-breath/VERSION"
    mkdir -p "$dest/.config/dragon-breath/assets"
    cp "$ASSETS_TMP/intro.mp4" "$ASSETS_TMP/wallpaper.png" "$dest/.config/dragon-breath/assets/"
    if [[ -d "$REPO_DIR/dotfiles" ]]; then
        cp "$REPO_DIR/dotfiles/hyprland.conf" "$REPO_DIR/dotfiles/hyprlock.conf" \
           "$REPO_DIR/dotfiles/hyprpaper.conf" "$dest/.config/hypr/"
        cp -r "$REPO_DIR/dotfiles/waybar" "$REPO_DIR/dotfiles/ghostty" "$REPO_DIR/dotfiles/dunst" \
              "$REPO_DIR/dotfiles/fastfetch" "$REPO_DIR/dotfiles/nwg-dock-hyprland" "$dest/.config/"
        cp "$REPO_DIR/dotfiles/starship.toml" "$dest/.config/starship.toml"
    fi

    cat << 'EOF' >> "$dest/.zshrc"

# --- Dragon OS (龙) Shell Integration ---
eval "$(starship init zsh)"
[[ -f "$HOME/.config/dragon-breath/dragon-shell.zsh" ]] && source "$HOME/.config/dragon-breath/dragon-shell.zsh"
EOF
}

inject_home "$PROFILE_DIR/airootfs/etc/skel"
inject_home "$PROFILE_DIR/airootfs/root"

# 3. Customiza o nome da ISO e do Bootloader
sed -i 's/iso_name="archlinux"/iso_name="dragon-os"/' "$PROFILE_DIR/profiledef.sh"
sed -i 's/iso_label="ARCH_/iso_label="DRAGON_/' "$PROFILE_DIR/profiledef.sh"
sed -i 's/iso_publisher="Arch Linux/iso_publisher="Dragon OS Project/' "$PROFILE_DIR/profiledef.sh"

echo "==> Construindo a ISO do Dragon OS (isso pode levar alguns minutos)..."
sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

echo "🐉 ISO gerada com sucesso em: $OUT_DIR"
