#!/usr/bin/env bash
# ============================================================================
# 🐉 DRAGON OS - Instala a abertura de boot (Plymouth) e o login automático (greetd)
#   uso: sudo install-boot-splash.sh <pasta_assets> <usuario>
# Mexe em /etc/mkinitcpio.conf e na linha de comando do kernel (GRUB ou
# systemd-boot). Cada arquivo alterado ganha um backup *.dragon-bak.
# DRAGON_AUTOLOGIN=0 pula o greetd; DRAGON_AUTOLOGIN=force substitui outro display manager.
# ============================================================================
set -euo pipefail

ASSETS="${1:?uso: $0 <pasta_assets> <usuario>}"
TARGET_USER="${2:?uso: $0 <pasta_assets> <usuario>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="/usr/share/plymouth/themes/dragon-os"

[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }

backup() { [[ -f "$1" && ! -f "$1.dragon-bak" ]] && cp -a "$1" "$1.dragon-bak" || true; }

# --- 1. Tema Plymouth -------------------------------------------------------
COUNT=$(find "$ASSETS/plymouth" -name 'frame-*.png' 2>/dev/null | wc -l)
if [[ $COUNT -eq 0 ]]; then
    echo "Nenhum quadro em $ASSETS/plymouth (rode make-boot-assets.sh antes)." >&2
    exit 1
fi
rm -rf "$THEME_DIR"
mkdir -p "$THEME_DIR"
cp "$HERE/plymouth/dragon-os/dragon-os.plymouth" "$THEME_DIR/"
sed "s/@FRAME_COUNT@/$COUNT/" "$HERE/plymouth/dragon-os/dragon-os.script" > "$THEME_DIR/dragon-os.script"
cp "$ASSETS/plymouth/"frame-*.png "$THEME_DIR/"
echo "    Tema Plymouth instalado ($COUNT quadros)."

# --- 2. Hook do Plymouth no initramfs (mkinitcpio) ---------------------------
INITRAMFS_OK=0
if [[ -f /etc/mkinitcpio.conf ]] && command -v mkinitcpio >/dev/null; then
    if grep -Eq '^HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf; then
        INITRAMFS_OK=1
    elif grep -Eq '^HOOKS=\(.*\b(systemd|udev)\b' /etc/mkinitcpio.conf; then
        backup /etc/mkinitcpio.conf
        # 'plymouth' logo depois de systemd/udev: antes de encrypt/sd-encrypt (senha do LUKS no splash)
        sed -Ei '/^HOOKS=/ { /\bsystemd\b/ s/\bsystemd\b/systemd plymouth/; t; s/\budev\b/udev plymouth/ }' /etc/mkinitcpio.conf
        INITRAMFS_OK=1
        echo "    Hook 'plymouth' adicionado ao mkinitcpio."
    fi
fi
[[ $INITRAMFS_OK -eq 1 ]] || echo "    ⚠ mkinitcpio não reconhecido: adicione o hook 'plymouth' ao initramfs manualmente."

# --- 3. 'quiet splash' na linha de comando do kernel -------------------------
add_splash() { # adiciona 'quiet' e 'splash' a uma linha de opções, sem duplicar
    local line="$1"
    [[ " $line " == *" quiet "* ]] || line="$line quiet"
    [[ " $line " == *" splash "* ]] || line="$line splash"
    echo "$line" | sed -E 's/^ +//'
}

CMDLINE_OK=0
if [[ -f /etc/default/grub ]] && command -v grub-mkconfig >/dev/null; then
    backup /etc/default/grub
    current=$(sed -nE 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/p' /etc/default/grub)
    new=$(add_splash "$current")
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"|" /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null
    CMDLINE_OK=1
    echo "    GRUB atualizado (quiet splash)."
else
    for entry in /boot/loader/entries/*.conf /efi/loader/entries/*.conf /boot/efi/loader/entries/*.conf; do
        [[ -f "$entry" ]] || continue
        grep -q '^options' "$entry" || continue
        backup "$entry"
        current=$(sed -nE 's/^options[[:space:]]+(.*)/\1/p' "$entry" | head -n1)
        new=$(add_splash "$current")
        sed -i "s|^options[[:space:]].*|options $new|" "$entry"
        CMDLINE_OK=1
    done
    [[ $CMDLINE_OK -eq 1 ]] && echo "    systemd-boot atualizado (quiet splash)."
fi
[[ $CMDLINE_OK -eq 1 ]] || echo "    ⚠ Bootloader não reconhecido (Limine/rEFInd?): adicione 'quiet splash' aos parâmetros do kernel manualmente."

# --- 4. Ativa o tema e recria o initramfs -----------------------------------
plymouth-set-default-theme dragon-os
if [[ $INITRAMFS_OK -eq 1 ]]; then
    mkinitcpio -P
fi

# --- 5. Login automático com greetd (a sessão é selada pelo hyprlock depois da abertura) ---
case "${DRAGON_AUTOLOGIN:-1}" in
    0) echo "    Login automático desativado (DRAGON_AUTOLOGIN=0)."; exit 0 ;;
esac

current_dm=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)" .service)
if [[ -n "$current_dm" && "$current_dm" != "display-manager" && "$current_dm" != "greetd" && "${DRAGON_AUTOLOGIN:-1}" != "force" ]]; then
    echo "    ⚠ Display manager '$current_dm' já ativo: login automático NÃO configurado."
    echo "      Para trocar pelo greetd: DRAGON_AUTOLOGIN=force"
    exit 0
fi

mkdir -p /etc/greetd
backup /etc/greetd/config.toml
cat > /etc/greetd/config.toml << GREETD
# 🐉 Dragon OS - greetd
# initial_session: login automático só no primeiro login após o boot (a abertura flui direto);
# o dragon-intro.sh sela a sessão com o hyprlock logo em seguida.
[terminal]
vt = 1

[default_session]
command = "agreety --cmd Hyprland"
user = "greeter"

[initial_session]
command = "Hyprland"
user = "$TARGET_USER"
GREETD

if [[ -n "$current_dm" && "$current_dm" != "greetd" && "$current_dm" != "display-manager" ]]; then
    systemctl disable "$current_dm.service"
fi
systemctl enable greetd.service   # sem --now: entra em vigor no próximo boot
echo "    greetd configurado com login automático para '$TARGET_USER' (efetivo no próximo boot)."
