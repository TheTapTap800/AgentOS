#!/usr/bin/env bash
# Master provisioner. Runs every install step in order. Used by BOTH:
#   - the ISO build (inside chroot, with --image-build)
#   - the Ansible remote deploy (on a live, already-installed machine)
# This is the single source of truth for "what AgentOS is".
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--image-build" ]; then
  export AGENTOS_IMAGE_BUILD=1
  shift
fi

source "$HERE/common.sh"

[ "$(id -u)" -eq 0 ] || die "provision-all.sh must run as root"

log "=== AgentOS provisioning starting (image_build=${AGENTOS_IMAGE_BUILD:-0}) ==="

# Install the systemd units shared by all services first (.service + .timer).
install -d /etc/systemd/system
install -m 0644 "$HERE/../units/"*.service /etc/systemd/system/
install -m 0644 "$HERE/../units/"*.timer /etc/systemd/system/ 2>/dev/null || true

ensure_user

bash "$HERE/setup-ssh.sh"
bash "$HERE/install-ollama.sh"
bash "$HERE/install-openclaw.sh"
bash "$HERE/install-hermes.sh"
bash "$HERE/install-dashboard.sh"
bash "$HERE/setup-kiosk.sh"

# --- auto-update wiring -------------------------------------------------------
install -d /etc/agentos
if [ ! -f /etc/agentos/update.conf ]; then
  cat >/etc/agentos/update.conf <<EOF
# AgentOS auto-updater config. Empty AGENTOS_REPO disables OTA updates.
AGENTOS_REPO="${AGENTOS_REPO}"
EOF
fi
# Seed the installed-version marker from the repo's VERSION file.
mkdir -p "$AGENTOS_STATE"
if [ -f "$HERE/../../VERSION" ]; then
  tr -d '[:space:]' <"$HERE/../../VERSION" >"${AGENTOS_STATE}/VERSION"
fi
svc_enable agentos-update.timer

# Record build provenance.
{
  echo "provisioned_at=$(date -u +%FT%TZ)"
  echo "image_build=${AGENTOS_IMAGE_BUILD:-0}"
  echo "local_model=${AGENTOS_LOCAL_MODEL}"
  echo "repo=${AGENTOS_REPO}"
} >"$AGENTOS_STATE/build-info"

log "=== AgentOS provisioning complete ==="
