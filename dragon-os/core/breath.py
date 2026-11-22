#!/usr/bin/env python3
import sys
import json
import subprocess
import urllib.request
import os

from scales_search import search_scales

OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
STATE_FILE = "/tmp/dragon_state.json"

def get_model():
    """DRAGON_MODEL do ambiente; senão o modelo do Tier definido pelo dragond."""
    if os.environ.get("DRAGON_MODEL"):
        return os.environ["DRAGON_MODEL"]
    try:
        with open(STATE_FILE) as f:
            return json.load(f)["default_model"]
    except Exception:
        return "qwen2.5-coder:3b"

ROFI_THEME = os.path.expanduser("~/.config/dragon-breath/config.rasi")

SYSTEM_PROMPT = (
    "Você é o Dragon Breath, a IA integrada ao Dragon OS (Linux/Wayland). "
    "Seja extremamente direto, conciso e técnico. "
    "Se o usuário pedir um comando Linux, retorne APENAS o comando na primeira linha, "
    "seguido de uma explicação de no máximo 1 linha."
)

def rofi_prompt(prompt_text="🐉 Sopro:", message="", options=None):
    cmd = ["rofi", "-dmenu", "-p", prompt_text, "-theme", ROFI_THEME]
    if message:
        cmd.extend(["-mesg", message])

    input_str = "\n".join(options) if options else ""
    proc = subprocess.run(cmd, input=input_str, text=True, capture_output=True)
    return proc.stdout.strip()

def get_clipboard():
    try:
        res = subprocess.run(["wl-paste", "-n"], capture_output=True, text=True, timeout=0.5)
        return res.stdout.strip()[:1000] # Limita tamanho por agilidade
    except Exception:
        return ""

def query_ollama(user_query, include_clip=False):
    full_prompt = user_query
    if include_clip:
        clip = get_clipboard()
        if clip:
            full_prompt = f"Contexto da área de transferência:\n{clip}\n\nPergunta: {user_query}"

    payload = {
        "model": get_model(),
        "prompt": full_prompt,
        "system": SYSTEM_PROMPT,
        "stream": False,
        "keep_alive": "30m", # Mantém na VRAM/RAM por 30 min para resposta zero-latency
        "options": {
            "temperature": 0.1,
            "num_predict": 250
        }
    }

    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode("utf-8"))
            return result.get("response", "Sem resposta do modelo.").strip()
    except Exception as e:
        return f"Erro ao conectar ao dragond (Ollama): {e}"

def main():
    # 1. Captura a pergunta inicial
    query = rofi_prompt("🐉 Dragon Breath", "Digite sua consulta ('@' inclui o texto copiado, '#' busca nos seus arquivos)")
    if not query:
        sys.exit(0)

    sources = []
    if query.startswith("#"):
        clean_query = query[1:].strip()
        try:
            sources = search_scales(clean_query, top_k=4)
        except Exception as e:
            # Ollama fora do ar / timeout: segue sem contexto em vez de derrubar o script
            sources = []
            query = f"(Aviso: falha ao consultar o índice Scales: {e}) {clean_query}"
        else:
            if sources:
                context_blocks = "\n\n---\n".join(
                    f"[{s['file']}] (Relevância: {s['score']:.2f}):\n{s['content']}"
                    for s in sources
                )
                query = (
                    f"Use os seguintes trechos dos arquivos locais do usuário para responder.\n"
                    f"Cite o nome do arquivo entre colchetes.\n\n"
                    f"{context_blocks}\n\nPergunta: {clean_query}"
                )
            else:
                query = f"(Aviso: Nenhum arquivo relevante encontrado no índice Scales) {clean_query}"

    include_clip = False
    if query.startswith("@"):
        include_clip = True
        query = query[1:].strip()

    # 2. Consulta o modelo local
    answer = query_ollama(query, include_clip)
    first_line = answer.split("\n")[0].strip("` ")

    # 3. Exibe a resposta e oferece ações rápidas
    actions = [
        f"📋 Copiar resposta completa",
        f"⚡ Copiar 1ª linha ({first_line[:40]}...)",
        f"🖥️ Executar no terminal: {first_line[:40]}...",
        f"🔄 Nova pergunta"
    ]

    if sources:
        actions.insert(0, f"📂 Abrir fonte principal: {sources[0]['file']}")

    choice = rofi_prompt("🐉 Ação", answer, actions)

    if choice.startswith("📂"):
        subprocess.Popen(["xdg-open", sources[0]["path"]])
    elif choice.startswith("📋"):
        subprocess.run(["wl-copy"], input=answer, text=True)
    elif choice.startswith("⚡"):
        subprocess.run(["wl-copy"], input=first_line, text=True)
    elif choice.startswith("🖥️"):
        # Abre o terminal padrão (ex: ghostty ou kitty) executando o comando e mantendo aberto
        subprocess.Popen(["kitty", "sh", "-c", f"{first_line}; exec zsh"])
    elif choice.startswith("🔄"):
        main()

if __name__ == "__main__":
    main()
