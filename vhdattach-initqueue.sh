#!/bin/sh
# ============================================================
# vhdattach-initqueue.sh
# Stage: initqueue/settled (Dracut 108)
# Purpose: Verify loop device partitions exist before root mount
# Author : Lukmanul Hakim  (https://www.linkedin.com/in/lukmanulhakimdevops)
# ============================================================

LOG="/run/initramfs/vhd.log"
exec >>"$LOG" 2>&1

echo "[vhdattach] ===== INITQUEUE STAGE START ====="
date

# Cari loop device yang sudah attach
LOOPDEV=$(losetup -a | grep "ubuntu.vhd" | cut -d: -f1 | head -n1)
if [ -z "$LOOPDEV" ]; then
    echo "[vhdattach] WARN: no loop device found!"
    exit 0
fi

echo "[vhdattach] checking partitions on $LOOPDEV..."
udevadm settle --timeout=15 || true
partprobe "$LOOPDEV" || true

# Pastikan partisi root (loopXp2) muncul
ROOT_PART="${LOOPDEV}p2"
for i in $(seq 1 10); do
    if [ -b "$ROOT_PART" ]; then
        echo "[vhdattach] root partition ready: $ROOT_PART"
        lsblk "$ROOT_PART" || true
        break
    fi
    echo "[vhdattach] waiting for $ROOT_PART ($i/10)"
    sleep 1
done

if [ ! -b "$ROOT_PART" ]; then
    echo "[vhdattach] ERROR: root partition $ROOT_PART not ready after wait"
    exit 0
fi

echo "[vhdattach] loop device verified OK"
echo "[vhdattach] ===== INITQUEUE COMPLETE ====="
exit 0
