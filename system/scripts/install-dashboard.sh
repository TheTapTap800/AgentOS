#!/usr/bin/env bash
# Install the AgentOS web dashboard (FastAPI backend + static frontend).
# This is the "pretty interface" the kiosk boots into. Bound to loopback.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
source "$HERE/common.sh"

DASH_SRC="${REPO_ROOT}/dashboard"
DASH_DST="${AGENTOS_PREFIX}/dashboard"

log "installing AgentOS dashboard"
apt_install python3 python3-venv python3-pip rsync

install -d "$DASH_DST"
rsync -a --delete "$DASH_SRC/" "$DASH_DST/"

# Isolated venv so we never touch system python.
python3 -m venv "${DASH_DST}/.venv"
"${DASH_DST}/.venv/bin/pip" install --upgrade pip >/dev/null
"${DASH_DST}/.venv/bin/pip" install -r "${DASH_DST}/backend/requirements.txt"

# Allow the dashboard (running as the agent user) to control the agent services
# without a password — scoped to exactly these units, nothing else.
cat >/etc/sudoers.d/agentos-dashboard <<EOF
${AGENTOS_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start openclaw.service, \
  /usr/bin/systemctl stop openclaw.service, \
  /usr/bin/systemctl restart openclaw.service, \
  /usr/bin/systemctl start hermes.service, \
  /usr/bin/systemctl stop hermes.service, \
  /usr/bin/systemctl restart hermes.service, \
  /usr/bin/systemctl restart ollama.service
EOF
chmod 0440 /etc/sudoers.d/agentos-dashboard

svc_enable agentos-dashboard.service
log "dashboard install complete (http://127.0.0.1:${DASHBOARD_PORT})"
