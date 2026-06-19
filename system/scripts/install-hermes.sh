#!/usr/bin/env bash
# Install Nous Research Hermes Agent. Hermes installs via its own script and
# talks to an OpenAI-compatible endpoint; we point it at local Ollama by default
# (the /v1 shim) and allow a cloud fallback through config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

log "installing Hermes Agent"
ensure_user
apt_install ca-certificates curl git python3 python3-venv

# Official Nous installer (verified URL). Pin a commit via HERMES_INSTALL_URL
# for reproducible images.
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
if ! command -v hermes >/dev/null 2>&1; then
  # Run installer as the agent user so the binary lands in their PATH.
  sudo -u "$AGENTOS_USER" bash -c "curl -fsSL '$HERMES_INSTALL_URL' | bash" || \
    warn "Hermes installer returned non-zero; verify network/URL"
fi

install -d -o "$AGENTOS_USER" -g "$AGENTOS_USER" "${AGENTOS_HOME}/.hermes"

# NOTE: Hermes is configured through an INTERACTIVE wizard (`hermes setup`) —
# upstream documents no file-based or headless serve flow. So we cannot fully
# bake its provider/model config into the image. We drop a target endpoint hint
# the operator uses during the one-time wizard, and a marker the dashboard reads.
#   Endpoint to enter:  http://${OLLAMA_HOST}/v1   (leave API key blank)
#   Model needs >= 64k context (hermes3 satisfies this).
cat >"${AGENTOS_HOME}/.hermes/AGENTOS_SETUP_HINT.txt" <<EOF
Run once to finish Hermes setup (interactive):
    ssh ${AGENTOS_USER}@<box>    # or use the kiosk TTY (Ctrl+Alt+F2)
    hermes setup
When asked for a provider, choose "Custom endpoint" and enter:
    http://${OLLAMA_HOST}/v1
Leave the API key blank. Pick a model with >= 64k context (e.g. ${AGENTOS_LOCAL_MODEL}).
For cloud fallback, choose an Anthropic/OpenAI provider and the key is read
from /etc/agentos/secrets.env.
EOF
chown -R "$AGENTOS_USER:$AGENTOS_USER" "${AGENTOS_HOME}/.hermes"

svc_enable hermes.service
log "Hermes Agent installed. One-time 'hermes setup' required — see ~/.hermes/AGENTOS_SETUP_HINT.txt"
