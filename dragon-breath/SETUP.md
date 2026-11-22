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
