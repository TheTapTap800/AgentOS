#!/usr/bin/env bash
# Install Nous Research Hermes Agent. Hermes installs via its own script and
# talks to an OpenAI-compatible endpoint; we point it at local Ollama by default
# (the /v1 shim) and allow a cloud fallback through config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

log "configuring Hermes Agent"
ensure_user
# Pre-install the Hermes installer's deps now so the first-boot install is fast
# and never has to stop to sudo-apt anything.
apt_install ca-certificates curl git python3 python3-venv \
            ripgrep ffmpeg build-essential python3-dev libffi-dev pkg-config

# IMPORTANT: we do NOT run the Hermes installer during the image build. Its
# upstream installer is long-running, spawns tty-reading children, and reliably
# hangs a no-TTY chroot build (timeout can't reap it). Instead we defer the
# actual binary install to first boot via agentos-hermes-install.service, which
# runs hermes-bootstrap.sh (detached, capped, idempotent). On a LIVE deploy
# (Ansible, not image build) we just run the bootstrap directly.
if in_image_build; then
  log "deferring Hermes binary install to first boot"
  svc_enable agentos-hermes-install.service
else
  bash "$HERE/hermes-bootstrap.sh" || warn "Hermes bootstrap returned non-zero"
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
log "Hermes configured (binary installs on first boot). One-time 'hermes setup' required — see ~/.hermes/AGENTOS_SETUP_HINT.txt"
