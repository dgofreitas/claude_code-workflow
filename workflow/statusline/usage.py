#!/usr/bin/env python3
"""Linhas extras da statusline: modelo/subagentes, tokens (via tokscale) e limites do plano.

Modo normal: lê o JSON da statusline no stdin e imprime as linhas (a 1ª é a do
modelo, que o statusline.sh junta ao badge do caveman).
Modo --refresh: roda o tokscale e grava o cache (chamado em segundo plano).

O tokscale leva ~10s por execução, então a statusline só lê o cache e dispara
um refresh em background quando ele passa de REFRESH_SECS.

O tokscale lê os logs do CLAUDE_CONFIG_DIR herdado, então cada perfil
(ex.: CLAUDE_CONFIG_DIR=~/.claude-pessoal) conta só os próprios tokens; o cache
é separado por perfil para um não sobrescrever o outro.
"""
import fcntl
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

DEFAULT_PROFILE = os.path.realpath(os.path.expanduser("~/.claude"))
PROFILE = os.path.realpath(os.environ.get("CLAUDE_CONFIG_DIR") or DEFAULT_PROFILE)
CACHE_DIR = os.path.join(os.path.expanduser("~/.cache/claude-statusline"), os.path.basename(PROFILE).lstrip("."))
CACHE = os.path.join(CACHE_DIR, "tokscale.json")
LOCK = os.path.join(CACHE_DIR, "refresh.lock")
REFRESH_SECS = int(os.environ.get("STATUSLINE_TOKSCALE_REFRESH", "120"))
# Vazio = todos os clientes (igual ao TUI do tokscale). Ex.: "claude" ou "claude,opencode".
CLIENTS = os.environ.get("STATUSLINE_TOKSCALE_CLIENTS", "")

DIM, RST = "\033[2m", "\033[0m"
GREEN, YELLOW, RED, CYAN = "\033[32m", "\033[33m", "\033[31m", "\033[36m"
DIAS = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]
# Subagente sem gravar nada há mais que isso é considerado morto (sessão encerrada etc.).
AGENT_STALE_SECS = 15 * 60
MAX_AGENT_GROUPS = 4


def tokscale_bin():
    found = shutil.which("tokscale")
    if found:
        return found
    cands = glob.glob(os.path.expanduser(
        "~/.npm/_npx/*/node_modules/@tokscale/cli-*/bin/tokscale"))
    return max(cands, key=os.path.getmtime) if cands else None


def run_tokscale(binary, period):
    cmd = [binary, period, "--json", "--no-spinner"]
    if CLIENTS:
        cmd += ["-c", CLIENTS]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300).stdout
    d = json.loads(out)
    keys = ("totalInput", "totalOutput", "totalCacheRead", "totalCacheWrite")
    return {k: d.get(k, 0) for k in keys}


def refresh():
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return  # outro refresh já está rodando
        binary = tokscale_bin()
        if not binary:
            return
        data = {"today": run_tokscale(binary, "--today"),
                "week": run_tokscale(binary, "--week"),
                "updated": time.time()}
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, CACHE)


def maybe_spawn_refresh():
    try:
        age = time.time() - os.path.getmtime(CACHE)
    except OSError:
        age = float("inf")
    if age < REFRESH_SECS:
        return
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "--refresh"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def human(n):
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if n >= div:
            return f"{n / div:.1f}{unit}"
    return str(int(n))


def token_lines():
    try:
        with open(CACHE) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return [f"{DIM}tokscale: carregando…{RST}"]
    cols = [("Input", "totalInput"), ("Output", "totalOutput"),
            ("Cache R", "totalCacheRead"), ("Cache W", "totalCacheWrite"), ("Total", None)]
    # O Claude Code faz trim() em cada linha: o cabeçalho precisa começar com texto.
    lines = [f"{CYAN}{'tokens':<6}{RST}" + DIM + "".join(f"{name:>9}" for name, _ in cols) + RST]
    for label, period in (("hoje", "today"), ("7 dias", "week")):
        vals = d[period]
        cells = "".join(f"{human(vals[key] if key else sum(vals.values())):>9}" for _, key in cols)
        lines.append(f"{CYAN}{label:<6}{RST}{cells}")
    return lines


def bar(pct, width=8):
    filled = round(min(max(pct, 0), 100) / 100 * width)
    color = GREEN if pct < 50 else YELLOW if pct < 80 else RED
    return f"{color}{'█' * filled}{DIM}{'░' * (width - filled)}{RST} {color}{pct:3.0f}%{RST}"


def limit_part(label, lim):
    if not lim:
        return f"{label} {DIM}— (após a 1ª resposta){RST}"
    pct = float(lim.get("used_percentage") or 0)
    reset = lim.get("resets_at")
    tail = ""
    if reset:
        dt = datetime.fromtimestamp(float(reset))
        left = max(0, int(dt.timestamp() - time.time()))
        d, h, m = left // 86400, left % 86400 // 3600, left % 3600 // 60
        when = f"{DIAS[dt.weekday()]} {dt:%H:%M}" if d else f"{dt:%H:%M}"
        eta = f"{d}d{h:02d}h" if d else f"{h}h{m:02d}"
        tail = f" {DIM}↻ {when} ({eta}){RST}"
    return f"{label} {bar(pct)}{tail}"


def model_name(model_id):
    """claude-sonnet-5-5 -> Sonnet 5.5, claude-haiku-4-5-20251001 -> Haiku 4.5."""
    m = re.match(r"claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$", model_id or "")
    if not m:
        return model_id or "?"
    family, major, minor = m.groups()
    return f"{family.capitalize()} {major}" + (f".{minor}" if minor else "")


def last_entry(path):
    """Última entrada user/assistant do transcript (lê só o final do arquivo)."""
    with open(path, "rb") as f:
        size = f.seek(0, os.SEEK_END)
        for chunk in (256 * 1024, size):
            f.seek(max(0, size - chunk))
            for raw in reversed(f.read().splitlines()):
                try:
                    e = json.loads(raw)
                except ValueError:
                    continue
                if e.get("type") in ("user", "assistant"):
                    return e
            if chunk >= size:
                break
    return None


def agent_model(path):
    """Modelo e effort da resposta mais recente do subagente."""
    with open(path, "rb") as f:
        size = f.seek(0, os.SEEK_END)
        f.seek(max(0, size - 1024 * 1024))
        for raw in reversed(f.read().splitlines()):
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            if e.get("type") == "assistant":
                return e.get("message", {}).get("model"), e.get("effort")
    return None, None


def running_agents(transcript_path):
    """Subagentes da sessão atual que ainda não terminaram.

    Terminado = última entrada é uma resposta do assistant com stop_reason end_turn.
    """
    if not transcript_path:
        return []
    sub_dir = os.path.join(transcript_path[:-len(".jsonl")], "subagents")
    now = time.time()
    agents = []
    for path in glob.glob(os.path.join(sub_dir, "agent-*.jsonl")):
        try:
            if now - os.path.getmtime(path) > AGENT_STALE_SECS:
                continue
            last = last_entry(path)
        except OSError:
            continue
        if not last or (last["type"] == "assistant"
                        and last.get("message", {}).get("stop_reason") == "end_turn"):
            continue
        try:
            with open(path[:-len(".jsonl")] + ".meta.json") as f:
                kind = json.load(f).get("agentType") or "agent"
        except (OSError, ValueError):
            kind = "agent"
        model, effort = agent_model(path)
        agents.append((kind, model_name(model) if model else "…", effort))
    return agents


def with_effort(name, effort):
    return f"{name} {DIM}·{RST} {effort}" if effort else name


def model_line(status):
    model = (status.get("model") or {}).get("display_name") or "?"
    effort = (status.get("effort") or {}).get("level")
    line = f"{CYAN}modelo{RST} {with_effort(model, effort)}"
    if PROFILE != DEFAULT_PROFILE:
        name = os.path.basename(PROFILE).removeprefix(".claude-").lstrip(".")
        line = f"{CYAN}conta{RST} {name}  {DIM}│{RST}  " + line
    groups = {}
    for kind, name, eff in running_agents(status.get("transcript_path")):
        groups[(kind, name, eff)] = groups.get((kind, name, eff), 0) + 1
    if groups:
        parts = [f"{kind}{f' ×{n}' if n > 1 else ''} {DIM}{name}{f' · {eff}' if eff else ''}{RST}"
                 for (kind, name, eff), n in sorted(groups.items())]
        extra = len(parts) - MAX_AGENT_GROUPS
        parts = parts[:MAX_AGENT_GROUPS] + ([f"{DIM}+{extra}{RST}"] if extra > 0 else [])
        line += f"  {DIM}│{RST}  {CYAN}agentes{RST} " + ", ".join(parts)
    return line


def main():
    try:
        status = json.load(sys.stdin)
    except ValueError:
        status = {}
    maybe_spawn_refresh()
    lines = [model_line(status)] + token_lines()
    rl = status.get("rate_limits") or {}
    lines.append(f"{CYAN}{'plano':<6}{RST}  " + limit_part("5h", rl.get("five_hour"))
                 + f"  {DIM}│{RST}  " + limit_part("semana", rl.get("seven_day")))
    print("\n".join(lines))


if __name__ == "__main__":
    if "--refresh" in sys.argv:
        refresh()
    else:
        main()
