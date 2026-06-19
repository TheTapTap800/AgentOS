#!/usr/bin/env bash
# Build the AgentOS installable ISO.
#
# MUST run on a Linux builder as root (WSL2 is fine). It cannot run from
# PowerShell — it needs apt, live-build, loop devices and chroot.
#
#   sudo ./build/build-iso.sh
#
# IMPORTANT (WSL2): live-build's chroot CANNOT live on a /mnt/c (drvfs) path —
# debootstrap needs real Linux filesystem semantics. So we always build in a
# NATIVE scratch dir ($AGENTOS_WORK, default ~/agentos-build) even when the repo
# itself sits on /mnt/c. Only the staged payload is copied from the repo.
#
# Output: <repo>/build/agentos-amd64.iso  (BIOS + UEFI bootable, x86_64).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
OUT_ISO="${BUILD_DIR}/agentos-amd64.iso"

# Native work dir for the chroot/cache. Falls back to /tmp if HOME is on drvfs.
WORK="${AGENTOS_WORK:-${HOME}/agentos-build}"
case "$WORK" in
  /mnt/*) echo "[agentos] ERROR: AGENTOS_WORK ($WORK) is on drvfs; pick a native path"; exit 1 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo -E ./build/build-iso.sh)"; exit 1; }

echo "[agentos] checking builder dependencies"
if ! command -v lb >/dev/null 2>&1; then
  echo "[agentos] installing live-build + tooling"
  apt-get update -qq
  apt-get install -y live-build debootstrap xorriso squashfs-tools rsync
fi

echo "[agentos] preparing native work dir: ${WORK}"
if [ -d "$WORK/cache/bootstrap" ]; then
  echo "[agentos] reusing cached bootstrap (lb clean, keeping cache)"
  ( cd "$WORK" && lb clean >/dev/null 2>&1 || true )
else
  rm -rf "$WORK"
  mkdir -p "$WORK"
fi
# (Re)copy the live-build config tree (auto/, config/) so edits take effect.
rsync -a --delete --exclude cache "${BUILD_DIR}/auto" "$WORK/"
rsync -a "${BUILD_DIR}/config" "$WORK/"

cd "$WORK"

# Stage the repo's runtime payload into the image filesystem at /opt/agentos.
echo "[agentos] staging payload into image"
mkdir -p config/includes.chroot/opt/agentos
rsync -a --exclude '.git' --exclude '.venv' \
  "${REPO_ROOT}/system" "${REPO_ROOT}/dashboard" "${REPO_ROOT}/kiosk" \
  config/includes.chroot/opt/agentos/
cp "${REPO_ROOT}/VERSION" config/includes.chroot/opt/agentos/VERSION

# Optionally bake first-boot identity: laptop pubkey + hostname so the imaged
# box is reachable immediately. Both optional (see build/authorized_keys.example).
mkdir -p config/includes.chroot/etc/agentos
[ -f "${BUILD_DIR}/authorized_keys" ] && {
  echo "[agentos] baking SSH authorized_keys into image"
  install -m 0644 "${BUILD_DIR}/authorized_keys" config/includes.chroot/etc/agentos/authorized_keys; }
[ -f "${BUILD_DIR}/hostname" ] && {
  echo "[agentos] baking hostname into image"
  install -m 0644 "${BUILD_DIR}/hostname" config/includes.chroot/etc/agentos/hostname; }

echo "[agentos] lb config"
lb config

echo "[agentos] lb build (downloads packages; 20-60 min)"
lb build

# live-build emits live-image-amd64.hybrid.iso; normalize + copy back to repo.
if [ -f live-image-amd64.hybrid.iso ]; then
  cp -f live-image-amd64.hybrid.iso "$OUT_ISO"
elif [ -f live-image-amd64.iso ]; then
  cp -f live-image-amd64.iso "$OUT_ISO"
else
  echo "[agentos] ERROR: no ISO produced — check live-build output above"
  exit 1
fi

echo "[agentos] DONE -> ${OUT_ISO}"
ls -lh "$OUT_ISO"
echo "[agentos] flash with:  dd if=${OUT_ISO} of=/dev/sdX bs=4M status=progress && sync"
