This version is **production-ready**, written for **Ubuntu 25.10** **Dracut 108+**, **GRUB 2.12+**, and **UEFI systems**, using only **kernel-level VHD attach** (`ntfs3`, `loop`, `partprobe`) — **no FUSE**, **no vdfuse**.
All logs go to `/run/initramfs/vhd.log`.

---

## 📁 Directory Layout of the Dracut Module

```
/usr/lib/dracut/modules.d/90vhdattach/
├── module-setup.sh
├── vhdattach-early.sh
├── vhdattach-initqueue.sh
└── 90-vhdattach.conf
```

---

## 🧩 `/usr/lib/dracut/modules.d/90vhdattach/module-setup.sh`

```bash
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
    # Essential tools to be included in initramfs
    inst_multiple \
        losetup kpartx partx mount blkid udevadm findmnt partprobe date seq \
        sleep dmesg mkdir tee basename dirname cat lsblk

    # Kernel drivers required for NTFS and loop
    instmods loop ntfs3 dm_mod dm_snapshot

    # Hook stages
    inst_hook pre-mount 05 "$moddir/vhdattach-early.sh"
    inst_hook initqueue/settled 90 "$moddir/vhdattach-initqueue.sh"
}
```

---

## 🧩 `/usr/lib/dracut/modules.d/90vhdattach/90-vhdattach.conf`

```bash
# ============================================================
# Configuration for vhdattach (Dracut 108+)
# ============================================================
hostonly="no"
add_drivers+=" loop ntfs3 dm_mod dm_snapshot "
add_dracutmodules+=" vhdattach "
dracut_log_level="debug"
```

---

## 🧩 `/usr/lib/dracut/modules.d/90vhdattach/vhdattach-early.sh`

```bash
#!/bin/sh
# ============================================================
# vhdattach-early.sh
# Stage: pre-mount (Dracut 108)
# Purpose: Mount NTFS host and attach the VHD file
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
    echo "[vhdattach] ERROR: failed to mount host!"
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
```

---

## 🧩 `/usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh`

```bash
#!/bin/sh
# ============================================================
# vhdattach-initqueue.sh
# Stage: initqueue/settled (Dracut 108)
# Purpose: Ensure loop device partitions are ready before root mount
# ============================================================

LOG="/run/initramfs/vhd.log"
exec >>"$LOG" 2>&1

echo "[vhdattach] ===== INITQUEUE STAGE START ====="
date

# Find the loop device already attached
LOOPDEV=$(losetup -a | grep "ubuntu.vhd" | cut -d: -f1 | head -n1)
if [ -z "$LOOPDEV" ]; then
    echo "[vhdattach] WARN: no loop device found!"
    exit 0
fi

echo "[vhdattach] checking partitions on $LOOPDEV..."
udevadm settle --timeout=15 || true
partprobe "$LOOPDEV" || true

# Ensure the root partition (loopXp2) is available
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
```

---

## 🧠 Workflow Overview

| Stage                    | Hook                     | Purpose                                                         |
| ------------------------ | ------------------------ | --------------------------------------------------------------- |
| **1. pre-mount**         | `vhdattach-early.sh`     | Mount NTFS host (RW), attach `.vhd` via `losetup`, trigger udev |
| **2. initqueue/settled** | `vhdattach-initqueue.sh` | Wait until `loop0p2` exists, verify partitions, write logs      |
| **3. root mount**        | handled by dracut        | Root filesystem is mounted from inside the `.vhd`               |

---

## ✅ Expected Results

* `/run/initramfs/vhd.log` logs the entire sequence from attach to verification.
* No more `initqueue timeout` errors.
* No emergency shell because `loop0p2` is ready before root mount.
* The `.vhd` root and host NTFS are both mounted **read/write**.

---

## 💾 Rebuild initramfs

```bash
sudo dracut -fv --add vhdattach --kver $(uname -r)
```

---

## 🔍 Extra Debugging

Add these to GRUB for debugging:

```
rd.debug rd.shell=1
```

Then in the emergency shell:

```bash
cat /run/initramfs/vhd.log
```

---

## ✅ Final `grub.cfg` (Production-Ready for GRUB 2.12+ EFI)

```bash
menuentry "Ubuntu from VHD (Native Loopboot)" {
    insmod part_gpt
    insmod ntfs
    insmod ext2
    insmod loopback
    insmod gzio

    # 1️⃣ Locate the NTFS host partition containing ubuntu.vhd
    search --no-floppy --fs-uuid --set=hostdisk D8DE7C15DE7BEA60
    echo "Host NTFS disk UUID=D8DE7C15DE7BEA60 found at ($hostdisk)"

    # 2️⃣ Attach the VHD file to a GRUB loop device
    loopback loop0 ($hostdisk)/ubuntu.vhd
    echo "Attached ubuntu.vhd as (loop0)"

    # 3️⃣ Set root to the Linux partition inside the VHD (usually GPT2)
    set root=(loop0,gpt2)

    # 4️⃣ Load the kernel
    echo "Booting kernel from (loop0,gpt2)..."
    linux ($root)/boot/vmlinuz-6.17.0-5-generic \
        root=UUID=e846e489-b692-442c-bf30-691d1a8d0bbd \
        rootfstype=ext4 \
        ro rootwait rootdelay=5 \
        rd.auto rd.retry=3 \
        rd.luks=0 rd.md=0 rd.dm=0 \
        vhd.uuid=D8DE7C15DE7BEA60 \
        vhd.path=/ubuntu.vhd \
        quiet splash loglevel=3 \
        rd.emergency=ignore rd.shell=1

    # 5️⃣ Load initramfs
    initrd ($root)/boot/initrd.img-6.17.0-5-generic

    # 6️⃣ Boot kernel
    boot
}
```

---

### ⚙️ Notes

| Option                      | Explanation                                                 |
| --------------------------- | ----------------------------------------------------------- |
| `root=UUID=`                | Must point to the root partition inside the `.vhd`.         |
| `rootfstype=ext4`           | Prevents filesystem autodetection delay.                    |
| `rd.auto rd.retry=3`        | Makes Dracut automatically retry device detection.          |
| `rd.luks=0 rd.md=0 rd.dm=0` | Skips cryptsetup, mdraid, and device-mapper init for speed. |
| `vhd.uuid` and `vhd.path`   | Passed to Dracut hooks for reference.                       |
| `rd.emergency=ignore`       | Avoids dropping into emergency shell during boot.           |

---

### ✅ Boot Checklist

1. `/boot/vmlinuz-*` and `/boot/initrd.img-*` exist **inside** the `.vhd`.
2. The `.vhd` file resides on NTFS partition `UUID=D8DE7C15DE7BEA60`.
3. The Dracut module `vhdattach` is bundled into initramfs.
4. The `root=UUID=` matches the ext4 root partition inside the VHD.
5. `loopback loop0 ($hostdisk)/ubuntu.vhd` works successfully in GRUB.

---
## 📂 EFI Boot Loader Structure (Windows + Ubuntu VHD)

On a typical UEFI dual-boot setup, your EFI partition (FAT32, usually `/dev/sda1`) will look like this:

```
/EFI/
├── Microsoft/
│   ├── Boot/
│   │   ├── bootmgfw.efi
│   │   └── BCD
│   └── ...
├── UbuntuVHD/
│   ├── grubx64.efi
│   └── grub.cfg   ← this is our configuration file
└── Boot/
    └── bootx64.efi (UEFI fallback)
```

You can create a new BCD entry via PowerShell:

```powershell
bcdedit /create /d "Ubuntu from VHD" /application BOOTSECTOR
```

or using **EasyUEFI**, then set its path to:

```
\EFI\UbuntuVHD\grubx64.efi
```

---
on Windows PowerShell (as Administrator):

```powershell
bcdedit /copy {bootmgr} /d "Ubuntu from VHD"
bcdedit /set {new-guid} path \EFI\UbuntuVHD\grubx64.efi
```

---

## ✅ Final Result

At boot time:

* Windows Boot Manager → choose **“Ubuntu from VHD”**
* GRUB EFI (`\EFI\UbuntuVHD\grubx64.efi`) loads `.vhd` from NTFS
* Kernel attaches `.vhd` via Dracut `vhdattach`
* Root filesystem (`/`) mounts from inside the VHD

Result: **True native Ubuntu boot** directly from a `.vhd` stored on Windows — single EFI, single disk, zero virtualization.
Perfect for hybrid DevOps workflows and portable Linux environments.

This setup gives you a **fully native Linux boot directly from a `.vhd` file** stored on a Windows NTFS partition — **fast**, **clean**, and **debug-friendly**.
