#!/usr/bin/env bash
# Configure a minimal Wayland kiosk: cage compositor launches Chromium in
# fullscreen pointed at the local dashboard. No desktop environment, no shell —
# the box boots straight into the "pretty interface". Appliance feel.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
source "$HERE/common.sh"

log "configuring kiosk session"
ensure_user

# cage = single-app Wayland kiosk compositor. surf = zero-chrome WebKit browser
# (suckless), run as an X client via cage's built-in Xwayland. chromium/cog are
# not installable debs on Ubuntu, so surf is the reliable kiosk renderer.
# seatd/greetd handle autologin into the Wayland session with no display mgr.
apt_install cage surf xwayland seatd greetd fonts-inter

systemctl enable seatd.service 2>/dev/null || svc_enable seatd.service
usermod -aG video,input,render,seat "$AGENTOS_USER" 2>/dev/null || true

install -d "${AGENTOS_PREFIX}/kiosk"
install -m 0755 "${REPO_ROOT}/kiosk/agentos-kiosk.sh" "${AGENTOS_PREFIX}/kiosk/agentos-kiosk.sh"

# greetd: autologin agent user straight into the cage kiosk session.
install -d /etc/greetd
cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "${AGENTOS_PREFIX}/kiosk/agentos-kiosk.sh"
user = "${AGENTOS_USER}"
EOF

systemctl enable greetd.service 2>/dev/null || svc_enable greetd.service
# Boot to graphical kiosk, not a text console.
systemctl set-default graphical.target 2>/dev/null || true

log "kiosk configured — boots into dashboard on port ${DASHBOARD_PORT}"
