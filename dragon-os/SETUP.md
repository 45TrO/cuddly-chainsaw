# Dragon OS (龙) v1.5

Instalação completa em um Arch Linux / CachyOS limpo (como usuário comum):

```bash
git clone <este repositório> && cd dragon-os
./dragon-install.sh
```

Variáveis opcionais do instalador:

| Variável | Efeito |
|---|---|
| `DRAGON_BOOT_SPLASH=0` | Não instala a abertura de boot (Plymouth) |
| `DRAGON_AUTOLOGIN=0` | Abertura sem login automático (pede senha no greetd) |
| `DRAGON_AUTOLOGIN=force` | Troca um display manager existente (SDDM, GDM…) pelo greetd |

ISO live bootável (em um host Arch): `./build-dragon-iso.sh` → `out-iso/`.

## Estrutura

```
dragon-os/
├── VERSION                       # 1.5
├── dragon-install.sh             # Instalador mestre (7 etapas)
├── build-dragon-iso.sh           # ISO live via archiso
├── core/                         # -> ~/.config/dragon-breath/
│   ├── dragonctl                 # CLI unificada de IA (breath, eye, gen, ask, search, index, watch, evict…)
│   ├── dragond.py                # Tier de hardware + liberação de VRAM
│   ├── dragon-shell.zsh          # Ctrl+G, wtf, ask, gcai, fastfetch
│   ├── dragon-hoard.sh           # Histórico do clipboard + transformação por IA (Super+C)
│   ├── sanctuary.sh              # Modo Santuário (Super+Z)
│   ├── whispering_wind.sh        # Ditado por voz offline (Super+V)
│   ├── dragon-intro.sh           # Fase final da abertura (após o login)
│   └── config.rasi               # Tema do Rofi
├── dotfiles/                     # Hyprland, hyprlock, hyprpaper, Waybar, Ghostty, Dunst,
│                                 # Starship, fastfetch, nwg-dock
├── systemd/                      # dragond, dragon-scales-watch, dragon-whisper (serviços de usuário)
├── boot/
│   ├── make-boot-assets.sh       # Vídeo -> quadros do Plymouth + clarão final + papel de parede
│   ├── install-boot-splash.sh    # Tema Plymouth, initramfs, 'quiet splash', greetd
│   └── plymouth/dragon-os/       # Tema Plymouth (script)
└── assets/boot-intro.mp4         # Vídeo de referência da abertura
```

## dragonctl

```bash
dragonctl status                 # painel de telemetria (alias: dstat)
dragonctl status --waybar        # JSON do módulo custom/dragond da Waybar
dragonctl evict [-q]             # libera a VRAM (Super+Shift+Backspace, alias: devict)
dragonctl model                  # lista modelos; 'dragonctl model qwen2.5-coder:7b -w' troca e pré-aquece
dragonctl model --reset          # volta ao modelo do Tier
dragonctl scales search "jwt"    # busca semântica (alias: dsearch)
dragonctl scales reindex         # varredura completa manual
dragonctl sanctuary              # Modo Santuário (Super+Z)
dragonctl breath                 # Launcher IA (Super+Shift+Space)
dragonctl eye                    # OCR / visão local (Super+Shift+S)
dragonctl gen -m shell -1 "listar portas abertas"
git diff --staged | dragonctl gen -m commit -1
dragonctl ask "diferença entre fd e find"
dragonctl index ~/Projetos/app   # indexa arquivos/pastas específicos
```

A troca de modelo fica em `~/.config/dragon-breath/model.override`; o `dragond` respeita esse
arquivo em vez de reescrever o modelo do Tier a cada 5 s.

Prompts de sistema (`breath`, `shell`, `wtf`, `commit`, `hoard`) podem ser sobrescritos, e novos modos
criados, em `~/.config/dragon-breath/prompts.json`:

```json
{ "shell": "Seu prompt…", "rapido": { "system": "Responda em uma frase." } }
```

## Abertura de boot

| Fase | Onde roda |
|---|---|
| 1. Mensagens de boot em verde jade | Plymouth (`SetMessageFunction`) |
| 2. Nanquim se espalha, luz dourada | Plymouth (quadros do vídeo) |
| 3. Voo do dragão até o "S" | Plymouth (segura o último quadro até o boot terminar) |
| 4. Clarão revela o desktop | `dragon-intro.sh` (mpv por cima do Hyprland) → hyprlock |

Para trocar a animação, substitua `assets/boot-intro.mp4` e ajuste os cortes:

```bash
INK_START=1.5 FLARE_START=7.25 FLARE_END=7.7 WALL_AT=7.0 \
  boot/make-boot-assets.sh assets/boot-intro.mp4 ~/.config/dragon-breath/assets
sudo boot/install-boot-splash.sh ~/.config/dragon-breath/assets "$USER"
```

Um papel de parede próprio pode substituir `~/.config/dragon-breath/assets/wallpaper.png` diretamente.

## Atalhos

| Atalho | Ação |
|---|---|
| Super + Space | Launcher de aplicativos |
| Super + Shift + Space | Dragon Breath |
| Super + Shift + S | Dragon Eye |
| Super + V | Whispering Wind |
| Super + C | Dragon Hoard |
| Super + Z | Modo Santuário |
| Super + Esc | Selo de Jade (hyprlock) |
| Super + Shift + Backspace | Liberar VRAM |
| Super + H/J/K/L | Foco (Vim) |
| Ctrl + G (Zsh) | Linguagem natural → comando |
