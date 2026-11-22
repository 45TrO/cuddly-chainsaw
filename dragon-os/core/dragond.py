#!/usr/bin/env python3
"""
dragond - Daemon de Gerenciamento de Hardware e VRAM do Dragon OS (龙)
Detecta o Tier da máquina e libera VRAM automaticamente sob alta carga.
"""
import os
import re
import shlex
import time
import json
import shutil
import subprocess
import urllib.request

OLLAMA_BASE = "http://127.0.0.1:11434"
# $XDG_RUNTIME_DIR (/run/user/UID, 0700): no /tmp compartilhado outro usuário poderia criar
# ou trocar o arquivo antes e controlar o que Waybar, Starship e dragonctl leem
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or os.path.expanduser("~/.cache/dragon-runtime")
STATE_FILE = os.path.join(RUNTIME_DIR, "dragon_state.json")
MODEL_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$")
ENV_FILE = os.path.expanduser("~/.config/dragon-breath/dragon_env.sh")
MODEL_OVERRIDE = os.path.expanduser("~/.config/dragon-breath/model.override")

# Processos pesados que exigem liberação imediata da VRAM (Jogos/Render/Compilação)
HEAVY_PROCESSES = {"steam", "gamescope", "wine64-preloader", "blender", "obs", "kdenlive"}

def get_vram_info():
    """Retorna (total_mb, used_mb) para GPUs NVIDIA, AMD ou fallback de RAM."""
    # 1. NVIDIA (via nvidia-smi)
    if shutil.which("nvidia-smi"):
        try:
            out = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=memory.total,memory.used", "--format=csv,noheader,nounits"],
                text=True, timeout=2
            ).strip().split("\n")[0]
            total, used = map(int, out.split(","))
            return total, used, "NVIDIA"
        except Exception:
            pass

    # 2. AMD (via sysfs DRM)
    try:
        for card in ["card0", "card1", "card2"]:
            base = f"/sys/class/drm/{card}/device"
            if os.path.exists(f"{base}/mem_info_vram_total"):
                with open(f"{base}/mem_info_vram_total") as f:
                    total = int(f.read().strip()) // (1024 * 1024)
                with open(f"{base}/mem_info_vram_used") as f:
                    used = int(f.read().strip()) // (1024 * 1024)
                if total > 512:
                    return total, used, "AMD"
    except Exception:
        pass

    # 3. Fallback: Memória RAM do Sistema (APUs / CPU Only)
    with open("/proc/meminfo") as f:
        mem = {line.split(":")[0]: int(line.split()[1]) // 1024 for line in f if ":" in line}
    total = mem.get("MemTotal", 8192)
    avail = mem.get("MemAvailable", 4096)
    return total, total - avail, "UMA/CPU"

def detect_tier(vram_total, gpu_type):
    """Classifica o hardware nas 3 edições do Dragon OS."""
    if gpu_type == "UMA/CPU" or vram_total < 6000:
        return {
            "tier": "Wyrm",
            "icon": "🐍",
            "model": "qwen2.5-coder:1.5b",
            "vision_model": "moondream",
            "vram_limit_pct": 85
        }
    elif vram_total < 14000:
        return {
            "tier": "Drake",
            "icon": "🦎",
            "model": "qwen2.5-coder:7b",
            "vision_model": "moondream",
            "vram_limit_pct": 88
        }
    else:
        return {
            "tier": "Imperial Dragon",
            "icon": "🐉",
            "model": "qwen2.5-coder:14b",
            "vision_model": "llava",
            "vram_limit_pct": 90
        }

def get_loaded_models():
    """Consulta o Ollama (/api/ps) para ver quais modelos estão na VRAM agora."""
    try:
        req = urllib.request.Request(f"{OLLAMA_BASE}/api/ps")
        with urllib.request.urlopen(req, timeout=2) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return [m["name"] for m in data.get("models", [])]
    except Exception:
        return []

def evict_all_models(reason=""):
    """Descarrega imediatamente todos os modelos da VRAM (keep_alive: 0)."""
    loaded = get_loaded_models()
    for model in loaded:
        payload = json.dumps({"model": model, "keep_alive": 0}).encode("utf-8")
        req = urllib.request.Request(
            f"{OLLAMA_BASE}/api/generate",
            data=payload,
            headers={"Content-Type": "application/json"}
        )
        try:
            urllib.request.urlopen(req, timeout=3)
        except Exception:
            pass
    if loaded:
        subprocess.Popen([
            "notify-send", "-u", "low", "-t", "3000",
            "🐉 dragond: VRAM Liberada",
            f"Modelos descarregados ({', '.join(loaded)}) — Motivo: {reason}"
        ])

def has_heavy_process():
    """Verifica se algum jogo ou app pesado de GPU está aberto."""
    try:
        out = subprocess.check_output(["ps", "-eo", "comm"], text=True)
        running = set(out.splitlines())
        found = HEAVY_PROCESSES.intersection(running)
        return next(iter(found), None)
    except Exception:
        return None

def _atomic_write(path, data):
    """Grava em arquivo temporário e troca de uma vez: leitores nunca veem JSON pela metade."""
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        f.write(data)
    os.replace(tmp, path)

def read_model_override():
    """Modelo escolhido com 'dragonctl model' (tem prioridade sobre o modelo do Tier)."""
    try:
        with open(MODEL_OVERRIDE) as f:
            name = f.read().strip()
    except OSError:
        return None
    # O valor vai para o dragon_env.sh (lido com 'source' pelo Zsh): só nomes de modelo válidos
    return name if MODEL_NAME_RE.match(name) else None

def write_env_and_state(profile, vram_total, vram_used, gpu_type, loaded_models):
    model = read_model_override() or profile["model"]
    os.makedirs(os.path.dirname(ENV_FILE), exist_ok=True)
    env = (
        f'export DRAGON_TIER={shlex.quote(profile["tier"])}\n'
        f'export DRAGON_MODEL={shlex.quote(model)}\n'
        f'export DRAGON_VISION_MODEL={shlex.quote(profile["vision_model"])}\n'
    )
    _atomic_write(ENV_FILE, env)

    state = {
        "tier": profile["tier"],
        "icon": profile["icon"],
        "gpu_type": gpu_type,
        "default_model": model,
        "tier_model": profile["model"],
        "vision_model": profile["vision_model"],
        "vram_total_mb": vram_total,
        "vram_used_mb": vram_used,
        "vram_pct": round((vram_used / max(vram_total, 1)) * 100, 1),
        "loaded_models": loaded_models
    }
    os.makedirs(RUNTIME_DIR, mode=0o700, exist_ok=True)
    _atomic_write(STATE_FILE, json.dumps(state))

def main():
    vram_total, vram_used, gpu_type = get_vram_info()
    profile = detect_tier(vram_total, gpu_type)
    print(f"[dragond] Iniciando no modo {profile['icon']} {profile['tier']} ({gpu_type} - {vram_total}MB)")

    while True:
        vram_total, vram_used, gpu_type = get_vram_info()
        loaded = get_loaded_models()
        usage_pct = (vram_used / max(vram_total, 1)) * 100

        # 1. Verifica se há processos pesados ou pressão de VRAM
        heavy_app = has_heavy_process()
        if heavy_app and loaded:
            evict_all_models(f"App pesado ativo: {heavy_app}")
            loaded = []
        elif usage_pct > profile["vram_limit_pct"] and loaded:
            evict_all_models(f"Uso de memória crítico ({usage_pct:.0f}%)")
            loaded = []

        # 2. Atualiza estado para o Zsh e para a Waybar lerem em tempo real
        write_env_and_state(profile, vram_total, vram_used, gpu_type, loaded)
        time.sleep(5)

if __name__ == "__main__":
    main()
