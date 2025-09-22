#!/bin/bash
check() { return 0; }

depends() {
    echo "dm"
    return 0
}

install() {
    # utilities to include
    inst_multiple losetup kpartx partx mount blkid udevadm findmnt
    # our hook: run in pre-mount stage (after devices ready, before root mount)
    inst_hook pre-mount 05 "$moddir/vhdattach-early.sh"
}
