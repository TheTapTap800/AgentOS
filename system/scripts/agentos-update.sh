#!/usr/bin/env bash
# AgentOS over-the-air updater. Polls the GitHub Releases API for the configured
# repo; if the latest release tag is newer than what's installed, downloads that
# tag's source payload and re-runs the (idempotent) provisioner. Run by
# agentos-update.timer. Safe to run by hand.
#
# Scope: updates the live payload (agents config, dashboard, kiosk, scripts,
# systemd units). It does NOT reflash the base OS/kernel — that needs a fresh
# ISO install. Most "pushed updates" are payload-level, so this covers them.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

CONF=/etc/agentos/update.conf
# Allow /etc/agentos/update.conf to override REPO and toggle.
[ -f "$CONF" ] && . "$CONF"

REPO="${AGENTOS_REPO:-}"
[ -n "$REPO" ] || { log "auto-update disabled (no repo configured)"; exit 0; }

CURRENT="$(cat "${AGENTOS_STATE}/VERSION" 2>/dev/null || echo "0.0.0")"
API="https://api.github.com/repos/${REPO}/releases/latest"

log "checking ${REPO} for updates (current: ${CURRENT})"
LATEST_JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null || true)"
[ -n "$LATEST_JSON" ] || { warn "could not reach GitHub releases API"; exit 0; }

# Extract tag_name without jq (busybox-safe).
TAG="$(printf '%s' "$LATEST_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
[ -n "$TAG" ] || { warn "no release tag found"; exit 0; }
VER="${TAG#v}"   # strip leading v

if [ "$VER" = "$CURRENT" ]; then
  log "already up to date (${CURRENT})"
  exit 0
fi

log "update available: ${CURRENT} -> ${VER}; downloading payload"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TARBALL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
if ! curl -fsSL "$TARBALL" -o "$TMP/src.tgz"; then
  warn "download failed: ${TARBALL}"; exit 1
fi
tar -xzf "$TMP/src.tgz" -C "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -type d -name '*-*' | head -1)"
[ -d "$SRC" ] || { warn "could not unpack payload"; exit 1; }

log "applying payload to ${AGENTOS_PREFIX}"
for d in system dashboard kiosk; do
  [ -d "$SRC/$d" ] && rsync -a --exclude '.venv' "$SRC/$d" "${AGENTOS_PREFIX}/"
done
chmod +x "${AGENTOS_PREFIX}/system/scripts/"*.sh "${AGENTOS_PREFIX}/kiosk/"*.sh 2>/dev/null || true

log "re-provisioning"
bash "${AGENTOS_PREFIX}/system/scripts/provision-all.sh"

mkdir -p "$AGENTOS_STATE"
printf '%s\n' "$VER" >"${AGENTOS_STATE}/VERSION"
log "updated to ${VER}"
