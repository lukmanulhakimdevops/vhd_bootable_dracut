#!/bin/bash
# module-setup.sh - installs vhdattach module contents into initramfs
check() { return 0; }
depends() { echo "dm"; return 0; }

install() {
    # utilities required in initramfs
    inst_multiple losetup kpartx partx mount blkid udevadm findmnt grep cut sed awk sleep mkdir umount dmesg kmod
    # optional: plymouth if present on host will not break if absent
    inst_multiple plymouth plymouthd plymouth-theme-* 2>/dev/null || true

    # very-early: ensure VHD attached before dracut resolves root=
    inst_hook initqueue 01 "$moddir/vhdattach-initqueue.sh"
    # fallback pre-mount for environments preferring pre-mount hook
    inst_hook pre-mount 05 "$moddir/vhdattach-early.sh"
    # pre-pivot: update /etc/fstab in final root
    inst_hook pre-pivot 90 "$moddir/fstab-overlay.sh"

    # include runtime config from host if exists
    if [ -f /etc/dracut.conf.d/90-vhdattach.conf ]; then
        inst_simple /etc/dracut.conf.d/90-vhdattach.conf /etc/dracut.conf.d/90-vhdattach.conf
    fi
}
