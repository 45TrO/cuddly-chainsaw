#!/usr/bin/env python3
import os
import json
import sqlite3
import urllib.error
import urllib.request
import fitz  # PyMuPDF
import numpy as np

DB_PATH = os.path.expanduser("~/.local/share/dragon-scales/scales.db")
OLLAMA_EMBED_URL = "http://127.0.0.1:11434/api/embed"
EMBED_MODEL = "nomic-embed-text"

# Diretórios e extensões que as "Escamas" vão monitorar
WATCH_DIRS = [
    os.path.expanduser("~/Documentos"),
    os.path.expanduser("~/Projetos"),
]
CODE_EXTS = {".py", ".rs", ".c", ".cpp", ".js", ".ts", ".sh", ".md", ".txt", ".toml", ".json"}
IGNORE_DIRS = {".git", "node_modules", "target", "__pycache__", ".venv", "build"}

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")  # sem isso o ON DELETE CASCADE é ignorado
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY,
            mtime REAL
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT,
            chunk_index INTEGER,
            content TEXT,
            embedding BLOB,
            FOREIGN KEY(path) REFERENCES files(path) ON DELETE CASCADE
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path)")
    conn.commit()
    return conn

def get_embeddings(texts):
    payload = {"model": EMBED_MODEL, "input": texts, "keep_alive": "5m"}
    req = urllib.request.Request(
        OLLAMA_EMBED_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return [np.array(vec, dtype=np.float32) for vec in data["embeddings"]]

def extract_text(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    if ext == ".pdf":
        with fitz.open(filepath) as doc:
            return "\n".join(page.get_text("text") for page in doc)
    elif ext in CODE_EXTS:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    return ""

def chunk_text(text, size=800, overlap=150):
    chunks = []
    start = 0
    while start < len(text):
        chunk = text[start:start + size].strip()
        if len(chunk) > 40:  # Ignora fragmentos muito pequenos
            chunks.append(chunk)
        start += size - overlap
    return chunks

def index_file(conn, filepath, mtime):
    """Indexa um arquivo de forma atômica: ou entra tudo, ou nada muda."""
    text = extract_text(filepath)
    chunks = chunk_text(text)

    # Gera todos os embeddings ANTES de tocar no banco
    rows = []
    for i in range(0, len(chunks), 32):
        batch = chunks[i:i+32]
        # Adiciona o nome do arquivo ao texto para melhorar a precisão semântica
        contextual_batch = [f"Arquivo: {os.path.basename(filepath)}\n{ch}" for ch in batch]
        embeddings = get_embeddings(contextual_batch)
        for idx, (ch, emb) in enumerate(zip(batch, embeddings)):
            norm_emb = emb / (np.linalg.norm(emb) + 1e-10)
            rows.append((filepath, i + idx, ch, norm_emb.tobytes()))

    c = conn.cursor()
    try:
        # UPSERT (e não INSERT OR REPLACE): REPLACE apagaria a linha-pai e,
        # com foreign_keys=ON, derrubaria os chunks em cascata.
        c.execute(
            "INSERT INTO files (path, mtime) VALUES (?, ?) "
            "ON CONFLICT(path) DO UPDATE SET mtime = excluded.mtime",
            (filepath, mtime),
        )
        c.execute("DELETE FROM chunks WHERE path = ?", (filepath,))
        c.executemany(
            "INSERT INTO chunks (path, chunk_index, content, embedding) VALUES (?, ?, ?, ?)",
            rows,
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise

def index_all():
    conn = init_db()
    c = conn.cursor()
    seen = set()
    scanned_dirs = []
    failed = 0

    try:
        for base_dir in WATCH_DIRS:
            if not os.path.exists(base_dir):
                continue  # pode estar desmontado: não apaga o que já foi indexado dele
            scanned_dirs.append(base_dir)
            for root, dirs, files in os.walk(base_dir):
                dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
                for file in files:
                    ext = os.path.splitext(file)[1].lower()
                    if ext not in CODE_EXTS and ext != ".pdf":
                        continue

                    filepath = os.path.join(root, file)
                    seen.add(filepath)
                    try:
                        mtime = os.path.getmtime(filepath)
                    except OSError:
                        continue

                    c.execute("SELECT mtime FROM files WHERE path = ?", (filepath,))
                    row = c.fetchone()
                    if row and row[0] >= mtime:
                        continue  # Arquivo já está atualizado no banco

                    print(f"[Scales] Indexando: {filepath}")
                    try:
                        index_file(conn, filepath, mtime)
                    except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
                        # Ollama indisponível: não adianta insistir arquivo por arquivo
                        print(f"[Scales] Ollama indisponível, abortando: {e}")
                        return
                    except Exception as e:
                        failed += 1
                        print(f"[Scales] Falha em {filepath}: {e}")

        # Remove do índice arquivos que não existem mais (apenas nas pastas varridas)
        c.execute("SELECT path FROM files")
        stale = [
            (p,) for (p,) in c.fetchall()
            if p not in seen
            and any(p.startswith(d.rstrip(os.sep) + os.sep) for d in scanned_dirs)
        ]
        if stale:
            c.executemany("DELETE FROM chunks WHERE path = ?", stale)
            c.executemany("DELETE FROM files WHERE path = ?", stale)
            conn.commit()
            print(f"[Scales] Removidos do índice: {len(stale)} arquivo(s) que não existem mais.")
    finally:
        conn.close()

    print(f"[Scales] Indexação concluída ({failed} falha(s)).")

if __name__ == "__main__":
    index_all()
