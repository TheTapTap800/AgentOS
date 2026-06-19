#!/usr/bin/env bash
# Install OpenClaw (github.com/openclaw/openclaw) as a system service.
# OpenClaw is a Node-based local-first agent; we run it headless under the
# agent user and expose its control surface to the dashboard over loopback.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

# OpenClaw's default gateway port (per upstream docs).
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"

log "installing OpenClaw"
ensure_user

# OpenClaw recommends Node 24 (min 22.19). Install Node 24 LTS via NodeSource.
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -c2-3)" -lt 22 ] 2>/dev/null; then
  apt_install ca-certificates curl gnupg git
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt_install nodejs
fi

# Install the CLI globally so `openclaw` is on PATH for service + user.
npm install -g openclaw@latest || die "npm install openclaw failed"

# Config + workspace live under ~/.openclaw. Memory is markdown, skills are
# SKILL.md files — both created/managed by OpenClaw itself at runtime.
install -d -o "$AGENTOS_USER" -g "$AGENTOS_USER" \
        "${AGENTOS_HOME}/.openclaw" "${AGENTOS_HOME}/.openclaw/workspace"

# Seed config if none present. Schema per upstream: agent.model is "<provider>/<id>".
# We default to the local Ollama model; cloud keys (for e.g. anthropic/*) arrive
# via /etc/agentos/secrets.env at deploy time, never baked into the image.
if [ ! -f "${AGENTOS_HOME}/.openclaw/openclaw.json" ]; then
  cat >"${AGENTOS_HOME}/.openclaw/openclaw.json" <<EOF
{
  "agent": {
    "model": "ollama/${AGENTOS_LOCAL_MODEL}"
  },
  "agents": {
    "defaults": {
      "workspace": "${AGENTOS_HOME}/.openclaw/workspace"
    }
  },
  "providers": {
    "ollama": { "baseUrl": "http://${OLLAMA_HOST}" }
  }
}
EOF
  chown -R "$AGENTOS_USER:$AGENTOS_USER" "${AGENTOS_HOME}/.openclaw"
fi

svc_enable openclaw.service
log "OpenClaw install complete (gateway port ${OPENCLAW_PORT})"
