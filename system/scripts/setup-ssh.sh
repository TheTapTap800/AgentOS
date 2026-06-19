#!/usr/bin/env bash
# Install + harden SSH and enable the first-boot setup unit. Called by
# provision-all.sh. The actual hostname/key application happens on first boot
# (firstboot-run.sh) so the same image individualizes per machine.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

log "configuring SSH + first-boot unit"
apt_install openssh-server

# Sensible defaults: no root login. Keep password auth on so you can recover a
# box that shipped without a baked key; switch to 'no' once keys are deployed.
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-agentos.conf
install -d /etc/ssh/sshd_config.d
cat >"$SSHD_DROPIN" <<EOF
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
EOF

# Open SSH in the firewall if ufw is the active firewall.
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH 2>/dev/null || true
fi

svc_enable ssh.service 2>/dev/null || svc_enable sshd.service 2>/dev/null || true
svc_enable agentos-firstboot.service

log "SSH configured (root login disabled, first-boot unit armed)"
