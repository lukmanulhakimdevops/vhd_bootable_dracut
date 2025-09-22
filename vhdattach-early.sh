#!/bin/sh
set -e
log() { echo "[vhdattach] $*" > /dev/kmsg; }
[ -f /lib/dracut-lib.sh ] && . /lib/dracut-lib.sh
log "start"

for m in loop dm_mod ntfs; do
  modprobe "$m" 2>/dev/null || log "modprobe $m failed/ignored"
done

HOST_UUID="3A8E66518E66062B"
VHD_REL_PATH="/lubuntu.vhd"
MOUNTPOINT="/mnt/host_vhd"
mkdir -p "$MOUNTPOINT"

attempt_mount_by_uuid() {
  [ -b "/dev/disk/by-uuid/$HOST_UUID" ] || return 1
  mount -t ntfs -o ro "/dev/disk/by-uuid/$HOST_UUID" "$MOUNTPOINT" 2>/dev/kmsg && return 0 || { umount "$MOUNTPOINT" 2>/dev/kmsg || true; return 1; }
}

attempt_mount_by_scan() {
  for d in /dev/sd?1 /dev/nvme?n1 /dev/mmcblk?p1; do
    [ -b "$d" ] || continue
    if { blkid "$d" 2>/dev/null | grep -qi ntfs; } || { fdisk -l "$d" 2>/dev/null | grep -qi ntfs; }; then
      mount -t ntfs -o ro "$d" "$MOUNTPOINT" 2>/dev/kmsg && return 0 || continue
    fi
  done
  return 1
}

if ! attempt_mount_by_uuid && ! attempt_mount_by_scan; then
  log "no NTFS host mounted — aborting vhd attach"
  rmdir "$MOUNTPOINT" 2>/dev/null || true
  exit 0
fi

VHD_FULL="$MOUNTPOINT${VHD_REL_PATH}"
if [ ! -f "$VHD_FULL" ]; then
  log "VHD not found: $VHD_FULL"
  umount "$MOUNTPOINT" 2>/dev/kmsg || true
  exit 0
fi

LOOP=$(losetup --show -f "$VHD_FULL" 2>/dev/kmsg) || { log "losetup failed"; umount "$MOUNTPOINT" 2>/dev/kmsg || true; exit 0; }
log "attached VHD -> $LOOP"

if command -v kpartx >/dev/null 2>&1; then
  kpartx -av "$LOOP" 2>/dev/kmsg || log "kpartx warned/fail"
else
  partx -a "$LOOP" 2>/dev/kmsg || log "partx -a failed"
fi

if command -v udevadm >/dev/null 2>&1; then
  udevadm trigger --action=add || true
  udevadm settle --timeout=5 || true
fi

log "done, loop=$LOOP"
exit 0

