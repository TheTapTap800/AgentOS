#!/usr/bin/env bash
# Runs ONCE on first boot (via agentos-firstboot.service). Makes a freshly
# imaged box reachable from your laptop: sets hostname and installs your SSH
# public key for the agent user. Idempotent + guarded by a done-marker.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

CONF_DIR="/etc/agentos"
MARKER="${AGENTOS_STATE}/.firstboot-done"

[ -e "$MARKER" ] && { log "firstboot already done"; exit 0; }
log "first-boot setup"

ensure_user

# --- hostname -----------------------------------------------------------------
# Baked at build time (build/hostname) or pushed via Ansible -> /etc/agentos/hostname.
if [ -f "${CONF_DIR}/hostname" ]; then
  NEW_HOST="$(tr -d '[:space:]' <"${CONF_DIR}/hostname")"
  if [ -n "$NEW_HOST" ]; then
    log "setting hostname to ${NEW_HOST}"
    hostnamectl set-hostname "$NEW_HOST" 2>/dev/null || echo "$NEW_HOST" >/etc/hostname
  fi
fi

# --- ssh authorized key -------------------------------------------------------
# Drop your laptop's public key at build/authorized_keys (baked) or push to
# /etc/agentos/authorized_keys. Without it the box has no remote key access.
if [ -f "${CONF_DIR}/authorized_keys" ]; then
  log "installing SSH authorized_keys for ${AGENTOS_USER}"
  install -d -m 0700 -o "$AGENTOS_USER" -g "$AGENTOS_USER" "${AGENTOS_HOME}/.ssh"
  install -m 0600 -o "$AGENTOS_USER" -g "$AGENTOS_USER" \
    "${CONF_DIR}/authorized_keys" "${AGENTOS_HOME}/.ssh/authorized_keys"
else
  warn "no /etc/agentos/authorized_keys — remote key login unavailable until you add one"
fi

# --- optional custom login password -------------------------------------------
# Bake build/password (plaintext, one line) or push /etc/agentos/password to set
# a per-box login password on first boot. Applied once, then shredded.
if [ -s "${CONF_DIR}/password" ]; then
  PW="$(head -n1 "${CONF_DIR}/password" | tr -d '\r\n')"
  if [ -n "$PW" ]; then
    log "setting ${AGENTOS_USER} password from ${CONF_DIR}/password"
    echo "${AGENTOS_USER}:${PW}" | chpasswd
  fi
  shred -u "${CONF_DIR}/password" 2>/dev/null || rm -f "${CONF_DIR}/password"
fi

systemctl enable --now ssh.service 2>/dev/null || systemctl enable --now sshd.service 2>/dev/null || true

mkdir -p "$AGENTOS_STATE"
date -u +%FT%TZ >"$MARKER"
log "first-boot setup complete"
