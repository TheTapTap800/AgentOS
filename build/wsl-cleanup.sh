#!/usr/bin/env bash
# Kill any stuck AgentOS build processes and unmount stale chroot bind-mounts.
# Run as root in WSL:  wsl -d Ubuntu -u root -- bash .../build/wsl-cleanup.sh
set +e

echo "[cleanup] killing build/installer processes"
pkill -9 -f "build-iso.sh"
pkill -9 -f "lb_chroot"
pkill -9 -f "mksquashfs"
pkill -9 -f "install.sh"
pkill -9 -f "hermes-agent"
pkill -9 -f "ollama.com/install"
# Anything still touching the work dir.
fuser -k -9 /root/agentos-build 2>/dev/null

echo "[cleanup] unmounting stale chroot mounts"
while read -r dev mp rest; do
  case "$mp" in
    */agentos-build/*) umount -lf "$mp" 2>/dev/null && echo "  umounted $mp" ;;
  esac
done < /proc/mounts

echo "[cleanup] remaining build procs:"
pgrep -af "build-iso|hermes-agent|lb_chroot|mksquashfs" || echo "  none"
echo "[cleanup] remaining agentos-build mounts: $(grep -c agentos-build /proc/mounts)"
