"""AgentOS dashboard backend.

A thin control plane over the local agent services. Everything it talks to is
on loopback: systemd (via scoped sudo), the Ollama HTTP API, and journald.
Serves the static frontend at / and a small JSON API at /api/*.
"""
from __future__ import annotations

import asyncio
import os
import platform
import shutil
import subprocess
import time
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434")
OLLAMA_URL = f"http://{OLLAMA_HOST}"
FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

# Services the dashboard knows how to monitor and control. The control actions
# are the *only* ones permitted by /etc/sudoers.d/agentos-dashboard.
SERVICES = {
    "ollama": {"label": "Ollama (local inference)", "controllable": ["restart"]},
    "openclaw": {"label": "OpenClaw", "controllable": ["start", "stop", "restart"]},
    "hermes": {"label": "Hermes Agent", "controllable": ["start", "stop", "restart"]},
    "agentos-dashboard": {"label": "Dashboard", "controllable": []},
}

app = FastAPI(title="AgentOS", docs_url=None, redoc_url=None)
_START = time.time()


def _systemctl(*args: str) -> str:
    """Run a read-only systemctl query. Returns stdout (stripped)."""
    try:
        out = subprocess.run(
            ["systemctl", *args],
            capture_output=True, text=True, timeout=5,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def _service_state(unit: str) -> dict:
    active = _systemctl("is-active", f"{unit}.service") or "unknown"
    enabled = _systemctl("is-enabled", f"{unit}.service") or "unknown"
    return {"active": active, "enabled": enabled}


@app.get("/api/health")
def health() -> dict:
    return {"ok": True, "uptime_s": round(time.time() - _START)}


@app.get("/api/status")
def status() -> dict:
    services = {
        name: {**meta, **_service_state(name)}
        for name, meta in SERVICES.items()
    }
    return {
        "host": platform.node(),
        "os": "AgentOS",
        "kernel": platform.release(),
        "arch": platform.machine(),
        "uptime_s": round(time.time() - _START),
        "services": services,
    }


@app.get("/api/models")
async def models() -> dict:
    """Local Ollama models + which are currently loaded."""
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            tags = (await client.get(f"{OLLAMA_URL}/api/tags")).json()
            running = (await client.get(f"{OLLAMA_URL}/api/ps")).json()
        except Exception:
            return {"available": [], "running": [], "reachable": False}
    return {
        "available": [m["name"] for m in tags.get("models", [])],
        "running": [m["name"] for m in running.get("models", [])],
        "reachable": True,
    }


@app.get("/api/logs/{unit}")
def logs(unit: str, lines: int = 120) -> dict:
    if unit not in SERVICES:
        raise HTTPException(404, "unknown service")
    out = subprocess.run(
        ["journalctl", "-u", f"{unit}.service", "-n", str(min(lines, 500)),
         "--no-pager", "--output=short-iso"],
        capture_output=True, text=True, timeout=8,
    )
    return {"unit": unit, "log": out.stdout or out.stderr}


@app.post("/api/agents/{unit}/{action}")
def control(unit: str, action: str) -> dict:
    meta = SERVICES.get(unit)
    if not meta:
        raise HTTPException(404, "unknown service")
    if action not in meta["controllable"]:
        raise HTTPException(403, f"action '{action}' not allowed for {unit}")
    res = subprocess.run(
        ["sudo", "systemctl", action, f"{unit}.service"],
        capture_output=True, text=True, timeout=20,
    )
    if res.returncode != 0:
        raise HTTPException(500, res.stderr.strip() or "control failed")
    return {"unit": unit, "action": action, "state": _service_state(unit)}


# Static frontend last so /api/* wins.
if FRONTEND_DIR.is_dir():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="ui")
