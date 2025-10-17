#!/bin/sh
# ============================================================
# vhdattach-early.sh
# Stage: pre-mount (Dracut 108)
# Author : Lukmanul Hakim  (https://www.linkedin.com/in/lukmanulhakimdevops)
# ============================================================

set -e
set -u

LOG="/run/initramfs/vhd.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "[vhdattach] ===== EARLY STAGE START ====="
date

[ -f /lib/dracut-lib.sh ] && . /lib/dracut-lib.sh

HOST_UUID="D8DE7C15DE7BEA60"
VHD_REL_PATH="/ubuntu.vhd"
HOST_MOUNTPOINT="/mnt/vhd_host"
MAX_WAIT=30
WAIT_INTERVAL=1

for mod in loop ntfs3 dm_mod; do
    modprobe "$mod" 2>/dev/null || echo "[vhdattach] warn: modprobe $mod failed"
done

DEV_PATH="/dev/disk/by-uuid/$HOST_UUID"
echo "[vhdattach] waiting for host device $DEV_PATH ..."
for i in $(seq 1 $MAX_WAIT); do
    if [ -b "$DEV_PATH" ]; then
        echo "[vhdattach] found $DEV_PATH"
        break
    fi
    sleep "$WAIT_INTERVAL"
done

if [ ! -b "$DEV_PATH" ]; then
    echo "[vhdattach] ERROR: host device not found after ${MAX_WAIT}s"
    exit 0
fi

mkdir -p "$HOST_MOUNTPOINT"
if ! mount -t ntfs3 -o rw,noatime,windows_names "$DEV_PATH" "$HOST_MOUNTPOINT"; then
    echo "[vhdattach] ERROR: mount host failed!"
    exit 0
fi
echo "[vhdattach] host mounted at $HOST_MOUNTPOINT"

VHD_FILE="$HOST_MOUNTPOINT$VHD_REL_PATH"
if [ ! -f "$VHD_FILE" ]; then
    echo "[vhdattach] ERROR: $VHD_FILE not found"
    umount "$HOST_MOUNTPOINT" || true
    exit 0
fi
echo "[vhdattach] found $VHD_FILE"

LOOPDEV=$(losetup -fP --show "$VHD_FILE")
if [ -z "$LOOPDEV" ]; then
    echo "[vhdattach] ERROR: losetup failed!"
    umount "$HOST_MOUNTPOINT" || true
    exit 0
fi

echo "[vhdattach] loop attached as $LOOPDEV"
partprobe "$LOOPDEV" || true
udevadm trigger --action=add || true
udevadm settle --timeout=15 || true

echo "[vhdattach] partitions now visible:"
lsblk "$LOOPDEV" || true
blkid | grep "$LOOPDEV" || true

echo "[vhdattach] ===== EARLY STAGE COMPLETE ====="
exit 0
