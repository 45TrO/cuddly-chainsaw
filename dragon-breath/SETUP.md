# Dragon Breath - dependências

```bash
ollama pull nomic-embed-text   # modelo de embeddings (RAG)
pip install pymupdf numpy      # leitura de PDF + vetores
```

## Indexador automático (systemd --user)

```bash
mkdir -p ~/.config/systemd/user
cp systemd/dragon-scales.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dragon-scales.timer
```

## Whispering Wind (風語) - ditado por voz offline

Fluxo: `pw-record` (WAV 16kHz mono) -> `whisper-server` (whisper.cpp, residente na RAM/VRAM, HTTP em 127.0.0.1:8178) -> `wtype` (injeta o texto na janela em foco).

```bash
# Dependências (Arch / CachyOS)
sudo pacman -S pipewire wtype wl-clipboard libnotify curl jq cmake base-devel

# Compilar o whisper.cpp
mkdir -p ~/.local/share/dragon-whisper && cd ~/.local/share/dragon-whisper
git clone https://github.com/ggerganov/whisper.cpp.git .
cmake -B build -DCMAKE_BUILD_TYPE=Release     # NVIDIA: -DGGML_CUDA=1 | AMD/Intel: -DGGML_VULKAN=1
cmake --build build -j$(nproc) --config Release

# Modelo quantizado
sh ./models/download-ggml-model.sh small-q5_1

# Serviço
cp ~/<repo>/dragon-breath/systemd/dragon-whisper.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dragon-whisper.service
```

## dragond + Dragon Shell

```bash
cp systemd/dragond.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dragond.service

chmod +x ~/.config/dragon-breath/dragond.py
echo 'source ~/.config/dragon-breath/dragon-shell.zsh' >> ~/.zshrc
# ferramentas: sudo pacman -S eza bat ripgrep fd bottom zoxide jq
```

## Starship

```bash
sudo pacman -S starship
cp starship.toml ~/.config/starship.toml
# no ~/.zshrc, DEPOIS do source do dragon-shell.zsh:
eval "$(starship init zsh)"
```
