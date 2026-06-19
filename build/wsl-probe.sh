#!/usr/bin/env bash
# Quick WSL2 readiness probe for the ISO build.
echo "USER=$(whoami)"
echo "--- passwordless sudo? ---"
if sudo -n true 2>/dev/null; then echo "PASSWORDLESS_SUDO=yes"; else echo "PASSWORDLESS_SUDO=no"; fi
echo "--- disk (wsl home) ---"
df -h "$HOME" | tail -1
echo "--- live-build present? ---"
command -v lb || echo "lb=absent"
echo "--- network ---"
if getent hosts archive.ubuntu.com >/dev/null 2>&1; then echo "dns_ok"; else echo "dns_fail"; fi
echo "--- systemd in wsl? ---"
if [ -d /run/systemd/system ]; then echo "systemd=running"; else echo "systemd=absent"; fi
