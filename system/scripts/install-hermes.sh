#!/usr/bin/env bash
# Install Nous Research Hermes Agent. Hermes installs via its own script and
# talks to an OpenAI-compatible endpoint; we point it at local Ollama by default
# (the /v1 shim) and allow a cloud fallback through config.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

log "installing Hermes Agent"
ensure_user
# Pre-install EVERY dep the installer would otherwise stop to `sudo apt install`
# (each such prompt reads /dev/tty and hangs a no-TTY build): optional tools
# (ripgrep, ffmpeg) AND the Python build toolchain (build-essential, python3-dev,
# libffi-dev, pkg-config). With these already present the installer skips its
# interactive sudo steps entirely.
apt_install ca-certificates curl git python3 python3-venv \
            ripgrep ffmpeg build-essential python3-dev libffi-dev pkg-config

# Official Nous installer (verified URL). Pin a commit via HERMES_INSTALL_URL
# for reproducible images.
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
if ! command -v hermes >/dev/null 2>&1; then
  # Belt-and-suspenders: grant the agent temporary passwordless sudo so ANY
  # sudo call the installer makes (even ones we didn't pre-empt) can't block on
  # a password prompt. Removed immediately after — never in the shipped image.
  HERMES_SUDOERS=/etc/sudoers.d/agentos-hermes-install
  echo "${AGENTOS_USER} ALL=(ALL) NOPASSWD:ALL" >"$HERMES_SUDOERS"
  chmod 0440 "$HERMES_SUDOERS"
  # Run as agent; feed /dev/null (EOF on any read); cap with a timeout.
  # Non-fatal: the binary is what we need; one-time `hermes setup` happens later.
  # --skip-setup: install the binary but DON'T launch the interactive setup
  # wizard (it reads /dev/tty and blocks). The one-time `hermes setup` is run by
  # the operator later (see AGENTOS_SETUP_HINT.txt).
  timeout 600 sudo -u "$AGENTOS_USER" env DEBIAN_FRONTEND=noninteractive \
      bash -c "curl -fsSL '$HERMES_INSTALL_URL' | bash -s -- --skip-setup" </dev/null \
    || warn "Hermes installer non-zero/timeout — finish with 'hermes setup' on the box"
  rm -f "$HERMES_SUDOERS"
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
