import os
import json
import sqlite3
import urllib.request
import numpy as np

DB_PATH = os.path.expanduser("~/.local/share/dragon-scales/scales.db")
OLLAMA_EMBED_URL = "http://127.0.0.1:11434/api/embed"
EMBED_MODEL = "nomic-embed-text"

def search_scales(query, top_k=4):
    if not os.path.exists(DB_PATH):
        return []

    # 1. Vetoriza a pergunta
    payload = {"model": EMBED_MODEL, "input": [query], "keep_alive": "15m"}
    req = urllib.request.Request(
        OLLAMA_EMBED_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        q_vec = np.array(json.loads(resp.read().decode("utf-8"))["embeddings"][0], dtype=np.float32)
        q_vec = q_vec / (np.linalg.norm(q_vec) + 1e-10)

    # 2. Carrega vetores do SQLite e calcula similaridade de cosseno
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT path, content, embedding FROM chunks")
    rows = c.fetchall()
    conn.close()

    if not rows:
        return []

    matrix = np.frombuffer(b"".join(r[2] for r in rows), dtype=np.float32).reshape(len(rows), -1)
    scores = np.dot(matrix, q_vec)

    # 3. Seleciona os Top-K trechos mais relevantes
    top_indices = np.argsort(scores)[::-1][:top_k]
    results = []
    for idx in top_indices:
        if scores[idx] > 0.35:  # Filtro mínimo de relevância
            path, content, _ = rows[idx]
            results.append({
                "file": os.path.basename(path),
                "path": path,
                "score": float(scores[idx]),
                "content": content
            })
    return results
