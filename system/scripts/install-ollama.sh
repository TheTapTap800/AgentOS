#!/usr/bin/env bash
# Install Ollama (local-inference half of the hybrid setup) + pull a default
# Hermes-capable model. Cloud providers are wired separately via agent config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

log "installing Ollama runtime"
apt_install ca-certificates curl

if ! command -v ollama >/dev/null 2>&1; then
  # Official installer; OLLAMA_VERSION pinnable for reproducible images.
  curl -fsSL https://ollama.com/install.sh | sh
fi

# Bind to localhost only — the dashboard and agents reach it over loopback.
mkdir -p /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/agentos.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST}"
Environment="OLLAMA_KEEP_ALIVE=15m"
EOF

svc_enable ollama.service

# Pull the default local model. During image build the daemon isn't running,
# so defer the pull to first boot via a oneshot unit.
if in_image_build; then
  log "deferring model pull (${AGENTOS_LOCAL_MODEL}) to first boot"
  cat >/etc/systemd/system/agentos-model-pull.service <<EOF
[Unit]
Description=AgentOS first-boot model pull
After=ollama.service network-online.target
Wants=network-online.target
ConditionPathExists=!${AGENTOS_STATE}/.model-pulled

[Service]
Type=oneshot
ExecStart=/usr/bin/env OLLAMA_HOST=${OLLAMA_HOST} ollama pull ${AGENTOS_LOCAL_MODEL}
ExecStartPost=/usr/bin/touch ${AGENTOS_STATE}/.model-pulled
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  svc_enable agentos-model-pull.service
else
  log "pulling local model ${AGENTOS_LOCAL_MODEL} (may take a while)"
  OLLAMA_HOST="$OLLAMA_HOST" ollama pull "$AGENTOS_LOCAL_MODEL" || \
    warn "model pull failed; run 'ollama pull ${AGENTOS_LOCAL_MODEL}' manually"
fi

log "Ollama install complete"
