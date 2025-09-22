#!/bin/sh
# vhdattach-initqueue.sh - very-early initqueue hook
set -e

logk() { echo "[vhdattach] $*" > /dev/kmsg; }

# load dracut helpers if present
[ -f /lib/dracut-lib.sh ] && . /lib/dracut-lib.sh

logk "initqueue start"

# Defaults (final values come from /etc/dracut.conf.d/90-vhdattach.conf if present)
HOST_UUID="${HOST_UUID:-3A8E66518E66062B}"
VHD_REL_PATH="${VHD_REL_PATH:-/lubuntu.vhd}"
HOST_MOUNTPOINT="${HOST_MOUNTPOINT:-/mnt/host_vhd}"
RETRIES="${VHDATTACH_RETRIES:-8}"
DELAY="${VHDATTACH_DELAY:-3}"
UNMOUNT_AFTER_LOOP="${UNMOUNT_HOST_AFTER_LOOP:-0}"
FSTAB_OPTS="${FSTAB_OPTS:-defaults,noatime,windows_names,uid=1000,gid=1000}"
ENABLE_PLY="${ENABLE_PLYMOUTH_NOTIF:-0}"

# Source config inside initramfs if present
if [ -f /etc/dracut.conf.d/90-vhdattach.conf ]; then
  # shellcheck disable=SC1090
  . /etc/dracut.conf.d/90-vhdattach.conf || logk "warning: failed to source config"
fi

# ensure kernel modules
for m in loop dm_mod ntfs3; do
  modprobe "$m" 2>/dev/null || logk "modprobe $m failed/ignored"
done

mkdir -p "$HOST_MOUNTPOINT"

do_mount_ntfs3() {
  dev="$1"
  logk "mount attempt $dev -> $HOST_MOUNTPOINT (ntfs3 rw)"
  if mount -t ntfs3 -o rw "$dev" "$HOST_MOUNTPOINT" 2>/dev/kmsg; then
    logk "mounted $dev (ntfs3 rw)"
    return 0
  fi
  return 1
}

attempt_mount_by_uuid() {
  [ -b "/dev/disk/by-uuid/$HOST_UUID" ] || return 1
  do_mount_ntfs3 "/dev/disk/by-uuid/$HOST_UUID" && return 0
  umount "$HOST_MOUNTPOINT" 2>/dev/kmsg || true
  return 1
}

attempt_mount_by_scan() {
  for d in /dev/sd?1 /dev/nvme?n1 /dev/mmcblk?p1; do
    [ -b "$d" ] || continue
    if blkid "$d" 2>/dev/null | grep -qi ntfs; then
      do_mount_ntfs3 "$d" && return 0
      umount "$HOST_MOUNTPOINT" 2>/dev/kmsg || true
    fi
  done
  return 1
}

try_mount_host() {
  i=0
  while [ "$i" -lt "$RETRIES" ]; do
    logk "host mount attempt $((i+1))/$RETRIES"
    if attempt_mount_by_uuid || attempt_mount_by_scan; then
      return 0
    fi
    logk "host mount failed; sleeping ${DELAY}s then udev trigger"
    sleep "$DELAY"
    if command -v udevadm >/dev/null 2>&1; then
      udevadm trigger --action=add || true
      udevadm settle --timeout=10 || true
    fi
    i=$((i+1))
  done
  return 1
}

# Run mounting
if ! try_mount_host; then
  logk "WARNING: host mount failed after retries - continuing without VHD attach"
  exit 0
fi

VHD_FULL="${HOST_MOUNTPOINT}${VHD_REL_PATH}"
if [ ! -f "$VHD_FULL" ]; then
  logk "INFO: VHD not present at $VHD_FULL - unmount host and continue"
  umount "$HOST_MOUNTPOINT" 2>/dev/kmsg || true
  exit 0
fi

# notify plymouth (if available and enabled)
if [ "$ENABLE_PLY" -eq 1 ] && command -v plymouth >/dev/null 2>&1; then
  plymouth message --text="Attaching VHD..."
fi

# attach as loop RW
LOOP=$(losetup --show -f "$VHD_FULL" 2>/dev/kmsg) || {
  logk "ERROR: losetup failed for $VHD_FULL"
  umount "$HOST_MOUNTPOINT" 2>/dev/kmsg || true
  exit 0
}
logk "attached VHD -> $LOOP"

# expose partitions inside VHD
if command -v kpartx >/dev/null 2>&1; then
  kpartx -av "$LOOP" 2>/dev/kmsg || logk "kpartx returned warnings"
else
  partx -a "$LOOP" 2>/dev/kmsg || logk "partx -a returned warnings"
fi

# wait for udev to settle and symlinks to be created
if command -v udevadm >/dev/null 2>&1; then
  udevadm trigger --action=add || true
  udevadm settle --timeout=15 || true
fi

# optionally unmount host partition after loop up (default leave mounted)
if [ "$UNMOUNT_AFTER_LOOP" -eq 1 ]; then
  umount "$HOST_MOUNTPOINT" 2>/dev/kmsg || logk "warning: unmount host failed"
fi

if [ "$ENABLE_PLY" -eq 1 ] && command -v plymouth >/dev/null 2>&1; then
  plymouth message --text="VHD attached"
fi

logk "vhdattach-initqueue finished (loop=${LOOP})"
exit 0
