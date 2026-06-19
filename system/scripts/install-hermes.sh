#!/usr/bin/env bash
# Install Nous Research Hermes Agent. Hermes installs via its own script and
# talks to an OpenAI-compatible endpoint; we point it at local Ollama by default
# (the /v1 shim) and allow a cloud fallback through config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

log "installing Hermes Agent"
ensure_user
# Pre-install the installer's "optional" deps (ripgrep, ffmpeg) up front so it
# never stops to prompt for sudo to install them — that prompt is what hangs a
# non-interactive (no-TTY) build.
apt_install ca-certificates curl git python3 python3-venv ripgrep ffmpeg

# Official Nous installer (verified URL). Pin a commit via HERMES_INSTALL_URL
# for reproducible images.
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
if ! command -v hermes >/dev/null 2>&1; then
  # Run as the agent user; feed /dev/null so any interactive read gets EOF
  # instead of blocking, and cap with a timeout so a hang can't wedge the build.
  # Non-fatal: the binary is what we need; one-time `hermes setup` happens later.
  timeout 900 sudo -u "$AGENTOS_USER" bash -c "curl -fsSL '$HERMES_INSTALL_URL' | bash" </dev/null \
    || warn "Hermes installer non-zero/timeout — finish with 'hermes setup' on the box"
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
