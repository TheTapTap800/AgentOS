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
# live-build builds the rootfs; grub-mkrescue + xorriso build the bootable ISO.
# (This old live-build can't make a noble-compatible bootloader, so we assemble
#  the ISO ourselves with modern grub2 — true BIOS + UEFI hybrid.)
NEED="live-build debootstrap xorriso squashfs-tools rsync mtools grub-common grub-pc-bin grub-efi-amd64-bin"
if ! command -v lb >/dev/null 2>&1 || ! command -v grub-mkrescue >/dev/null 2>&1; then
  echo "[agentos] installing build toolchain"
  apt-get update -qq
  apt-get install -y $NEED
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

# Build only through the chroot stage: bootstrap + package install + our
# provisioning hook. We deliberately DO NOT run `lb binary` — its ancient
# bootloader code is incompatible with noble. We assemble the ISO below.
echo "[agentos] lb bootstrap (cached after first run)"
lb bootstrap
echo "[agentos] lb chroot (installs packages + runs AgentOS provisioning hook)"
lb chroot

CHROOT="$WORK/chroot"
[ -d "$CHROOT" ] || { echo "[agentos] ERROR: chroot not built"; exit 1; }

# Make sure no virtual filesystems are still bind-mounted in the chroot.
for m in dev/pts dev proc sys run; do
  mountpoint -q "$CHROOT/$m" && umount -lf "$CHROOT/$m" 2>/dev/null || true
done

echo "[agentos] assembling ISO tree"
ISOROOT="$WORK/iso"
rm -rf "$ISOROOT"
mkdir -p "$ISOROOT/live" "$ISOROOT/boot/grub"

# Newest kernel + initrd from the chroot.
KERNEL="$(ls -1 "$CHROOT"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)"
INITRD="$(ls -1 "$CHROOT"/boot/initrd.img-* 2>/dev/null | sort -V | tail -1)"
[ -n "$KERNEL" ] && [ -n "$INITRD" ] || { echo "[agentos] ERROR: kernel/initrd missing in chroot"; exit 1; }
cp "$KERNEL" "$ISOROOT/live/vmlinuz"
cp "$INITRD" "$ISOROOT/live/initrd.img"

echo "[agentos] squashing root filesystem (this takes a few minutes)"
mksquashfs "$CHROOT" "$ISOROOT/live/filesystem.squashfs" \
  -noappend -comp xz -wildcards \
  -e "boot/vmlinuz-*" -e "boot/initrd.img-*" \
  -e "proc/*" -e "sys/*" -e "dev/*" -e "run/*" -e "tmp/*" \
  -e "var/cache/apt/archives/*.deb"

# GRUB menu. live-boot mounts /live/filesystem.squashfs as root from boot=live.
cat >"$ISOROOT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
menuentry "AgentOS" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}
menuentry "AgentOS (safe graphics)" {
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd.img
}
EOF

echo "[agentos] grub-mkrescue -> ${OUT_ISO} (BIOS + UEFI hybrid)"
grub-mkrescue -o "$OUT_ISO" "$ISOROOT" \
  -- -volid AGENTOS

[ -f "$OUT_ISO" ] || { echo "[agentos] ERROR: ISO not produced"; exit 1; }

echo "[agentos] DONE -> ${OUT_ISO}"
ls -lh "$OUT_ISO"
echo "[agentos] flash with:  dd if=${OUT_ISO} of=/dev/sdX bs=4M status=progress && sync"
