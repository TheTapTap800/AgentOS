#!/usr/bin/env bash
# Shared helpers for all AgentOS provisioning scripts.
# Sourced by every install-*.sh. POSIX bash, no external deps beyond coreutils.

set -euo pipefail

# ---- configuration knobs (override via environment) -------------------------
AGENTOS_USER="${AGENTOS_USER:-agent}"
AGENTOS_HOME="${AGENTOS_HOME:-/home/${AGENTOS_USER}}"
AGENTOS_PREFIX="${AGENTOS_PREFIX:-/opt/agentos}"
AGENTOS_STATE="${AGENTOS_STATE:-/var/lib/agentos}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"

# GitHub repo the auto-updater pulls releases from, as "owner/name". Baked into
# /etc/agentos/update.conf at provision time. Empty = auto-update disabled.
AGENTOS_REPO="${AGENTOS_REPO:-TheTapTap800/AgentOS}"

# Default local model pulled by Ollama for the "local" half of hybrid inference.
# Hermes Agent needs >= 64k context; hermes3 satisfies this.
AGENTOS_LOCAL_MODEL="${AGENTOS_LOCAL_MODEL:-hermes3:8b}"

export DEBIAN_FRONTEND=noninteractive

log()  { printf '\033[1;36m[agentos]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[agentos:warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[agentos:err]\033[0m %s\n' "$*" >&2; exit 1; }

# Are we running inside the ISO build chroot (no systemd) vs a live machine?
in_image_build() { [ "${AGENTOS_IMAGE_BUILD:-0}" = "1" ]; }

# Enable a systemd unit, but tolerate the image-build chroot where systemd
# isn't running (we only enable, the unit starts on first real boot).
svc_enable() {
  local unit="$1"
  if in_image_build; then
    systemctl enable "$unit" 2>/dev/null || \
      ln -sf "/etc/systemd/system/${unit}" \
             "/etc/systemd/system/multi-user.target.wants/${unit}" 2>/dev/null || true
  else
    systemctl daemon-reload
    systemctl enable --now "$unit"
  fi
}

# Idempotent apt install.
apt_install() {
  apt-get update -qq
  apt-get install -y --no-install-recommends "$@"
}

# Create the unprivileged agent user if missing.
ensure_user() {
  if ! id "$AGENTOS_USER" >/dev/null 2>&1; then
    log "creating user ${AGENTOS_USER}"
    useradd --create-home --shell /bin/bash "$AGENTOS_USER"
    usermod -aG sudo,video,audio,render "$AGENTOS_USER" 2>/dev/null || true
  fi
  mkdir -p "$AGENTOS_STATE" "$AGENTOS_PREFIX"
  chown -R "$AGENTOS_USER:$AGENTOS_USER" "$AGENTOS_STATE"
}
