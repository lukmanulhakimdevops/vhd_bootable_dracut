#!/bin/bash
# ============================================================
# Dracut 108+ module-setup.sh
# ============================================================

check() { return 0; }

depends() {
    echo "dm"
    return 0
}

install() {
    # Tools penting yang harus dibawa ke initramfs
    inst_multiple \
        losetup kpartx partx mount blkid udevadm findmnt partprobe \
        sleep dmesg mkdir tee basename dirname cat lsblk

    # Kernel drivers untuk NTFS & loop
    instmods loop ntfs3 dm_mod dm_snapshot

    # Hooks
    inst_hook pre-mount 05 "$moddir/vhdattach-early.sh"
    inst_hook initqueue/settled 90 "$moddir/vhdattach-initqueue.sh"
}
