#!/usr/bin/env python3
"""
Dragon Eye (龙眼) - Visão Computacional e OCR Local para o Dragon OS
Integra grim + slurp + Tesseract OCR + Ollama Vision API
"""
import os
import sys
import json
import base64
import shutil
import subprocess
import urllib.request

OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
STATE_FILE = "/tmp/dragon_state.json"
ROFI_THEME = os.path.expanduser("~/.config/dragon-breath/config.rasi")
SHOT_PATH = "/tmp/dragon_eye_capture.png"

def get_vision_model():
    """Escolhe o modelo de visão ideal com base no Tier detectado pelo dragond."""
    if os.environ.get("DRAGON_VISION_MODEL"):
        return os.environ["DRAGON_VISION_MODEL"]
    try:
        with open(STATE_FILE) as f:
            tier = json.load(f).get("tier", "Wyrm")
        if tier == "Wyrm":
            return "moondream"
        return "llava" # Ou minicpm-v / llama3.2-vision
    except Exception:
        return "moondream"

def rofi_menu(prompt_text, message="", options=None):
    cmd = ["rofi", "-dmenu", "-p", prompt_text, "-theme", ROFI_THEME]
    if message:
        cmd.extend(["-mesg", message])
    input_str = "\n".join(options) if options else ""
    proc = subprocess.run(cmd, input=input_str, text=True, capture_output=True)
    return proc.stdout.strip()

def notify(title, body, urgency="low"):
    subprocess.Popen([
        "notify-send", "-u", urgency, "-t", "3500",
        "-h", "string:x-canonical-private-synchronous:dragon_eye",
        title, body
    ])

def capture_region():
    """Abre seletor slurp com borda Verde Jade (#00A86B) e fundo Nanquim."""
    slurp_cmd = [
        "slurp",
        "-b", "0D0F1266", # Sombra nanquim translúcida
        "-c", "00A86BFF", # Borda Verde Jade Imperial
        "-s", "00000000", # Seleção transparente
        "-w", "2"
    ]
    res = subprocess.run(slurp_cmd, capture_output=True, text=True)
    region = res.stdout.strip()
    if not region:
        sys.exit(0) # Usuário cancelou com ESC

    subprocess.run(["grim", "-g", region, SHOT_PATH], check=True)
    return SHOT_PATH

def run_fast_ocr(image_path):
    """Extrai texto instantaneamente via Tesseract (CPU, <100ms)."""
    if not shutil.which("tesseract"):
        return "Erro: 'tesseract' não instalado."
    res = subprocess.run(
        ["tesseract", image_path, "stdout", "-l", "por+eng", "--psm", "6"],
        capture_output=True, text=True
    )
    return res.stdout.strip()

def query_vision_ai(image_path, prompt_text):
    """Envia a imagem em Base64 para o modelo de visão local no Ollama."""
    model = get_vision_model()
    notify("👁️ Dragon Eye", f"Analisando imagem com {model}...")

    with open(image_path, "rb") as img_f:
        b64_img = base64.b64encode(img_f.read()).decode("utf-8")

    payload = {
        "model": model,
        "prompt": prompt_text,
        "images": [b64_img],
        "stream": False,
        "keep_alive": "10m",
        "options": {"temperature": 0.1, "num_predict": 400}
    }

    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("response", "Sem resposta do modelo de visão.").strip()
    except Exception as e:
        return f"Erro ao consultar modelo de visão ({model}): {e}\nCertifique-se de ter rodado: ollama pull {model}"

def main():
    # 1. Seleciona e captura a área da tela
    img_path = capture_region()

    # 2. Menu de intenções do Dragon Eye
    modes = [
        "⚡ OCR Instantâneo (Extrair texto/código puro)",
        "📊 Explicar gráfico, diagrama ou imagem (IA)",
        "📝 Converter tabela/equação para Markdown/LaTeX (IA)",
        "🌐 Traduzir texto da imagem para Português (IA)",
        "💻 Gerar código HTML/Tailwind desta interface (IA)",
        "🖼️ Apenas copiar imagem para o Clipboard"
    ]

    choice = rofi_menu("👁️ Dragon Eye", "Selecione a ação para a região capturada (ou digite um prompt livre):", modes)
    if not choice:
        sys.exit(0)

    # 3. Executa a ação escolhida
    if choice.startswith("🖼️"):
        with open(img_path, "rb") as f:
            subprocess.run(["wl-copy", "--type", "image/png"], input=f.read())
        notify("👁️ Dragon Eye", "Imagem copiada para a área de transferência!")
        sys.exit(0)

    elif choice.startswith("⚡"):
        result = run_fast_ocr(img_path)
        if not result:
            result = "Nenhum texto detectado pelo OCR."
    elif choice.startswith("📊"):
        result = query_vision_ai(img_path, "Analise esta imagem em detalhes, mas de forma direta e técnica em português. Se for um gráfico ou erro, explique os pontos principais.")
    elif choice.startswith("📝"):
        result = query_vision_ai(img_path, "Extraia qualquer tabela desta imagem para formato Markdown limpo, ou converta equações matemáticas para LaTeX. Retorne apenas o resultado formatado.")
    elif choice.startswith("🌐"):
        result = query_vision_ai(img_path, "Traduza todo o texto visível nesta imagem para o português mantendo a formatação original.")
    elif choice.startswith("💻"):
        result = query_vision_ai(img_path, "Escreva o código HTML + Tailwind CSS que reproduz fielmente este componente de interface.")
    else:
        # Caso o usuário tenha digitado uma pergunta customizada direto no Rofi!
        result = query_vision_ai(img_path, choice)

    # 4. Exibe o resultado e oferece cópia imediata
    post_actions = [
        "📋 Copiar resultado para o Clipboard",
        "🔄 Fazer outra pergunta sobre esta mesma captura",
        "❌ Fechar"
    ]
    next_step = rofi_menu("👁️ Resultado", result, post_actions)

    if next_step.startswith("📋"):
        subprocess.run(["wl-copy"], input=result, text=True)
        notify("👁️ Dragon Eye", "Texto copiado para a área de transferência!")
    elif next_step.startswith("🔄"):
        custom_q = rofi_menu("👁️ Pergunta:", "O que você quer saber sobre a captura?")
        if custom_q:
            ans = query_vision_ai(img_path, custom_q)
            subprocess.run(["wl-copy"], input=ans, text=True)
            rofi_menu("👁️ Resposta (Já copiada!)", ans, ["✅ OK"])

if __name__ == "__main__":
    main()
