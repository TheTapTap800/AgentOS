#!/usr/bin/env bash
# Installs the Hermes Agent binary. Run on first boot (by
# agentos-hermes-install.service), NOT during the image build — the upstream
# installer is interactive/long-running and reliably hangs a no-TTY chroot
# build. On a live box it has a real network + can run in the background.
# Idempotent (marker-guarded) and always exits 0 so it never wedges boot.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh" 2>/dev/null || { AGENTOS_USER=agent; AGENTOS_STATE=/var/lib/agentos; }
trap - ERR 2>/dev/null || true
set +e

MARKER="${AGENTOS_STATE}/.hermes-installed"
[ -e "$MARKER" ] && { echo "[hermes] already installed"; exit 0; }

URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"

# Pre-met deps mean the installer won't stop to sudo-apt anything.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ripgrep ffmpeg build-essential python3-dev libffi-dev pkg-config >/dev/null 2>&1

echo "[hermes] installing Hermes binary (--skip-setup, backgrounded, capped)"
# setsid: detach from any controlling tty so /dev/tty reads fail fast instead of
# blocking. timeout -k: hard-kill if it lingers. Non-fatal regardless.
setsid timeout -k 60 900 sudo -u "$AGENTOS_USER" env DEBIAN_FRONTEND=noninteractive \
  bash -c "curl -fsSL '$URL' | bash -s -- --skip-setup" </dev/null >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] || sudo -u "$AGENTOS_USER" bash -lc 'command -v hermes' >/dev/null 2>&1; then
  mkdir -p "$AGENTOS_STATE"; date -u +%FT%TZ >"$MARKER"
  echo "[hermes] install complete"
else
  echo "[hermes] install rc=$rc — will retry next boot (run 'hermes setup' manually if needed)"
fi
exit 0
