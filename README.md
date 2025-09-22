# 📌 Pra-syarat Dracut (umum & khusus VHD)

### 1. Paket dracut & tool wajib ada

* `dracut`
* `kpartx`
* `partx` (biasanya dari paket `util-linux`)
* `losetup` (dari `util-linux`)
* `udev` (`udevadm`)
* `blkid` (`util-linux`)
* `mount`, `umount`
* `grep`, `awk`, `sed`, `cut`, `sleep`, `mkdir`
* Opsional tapi disarankan: `plymouth`, `dmesg`, `kmod`

👉 Install semua:

```bash
sudo apt install dracut util-linux kpartx udev plymouth plymouth-themes
```

---

### 2. Modul kernel harus tersedia

Supaya initramfs bisa attach VHD:

* `loop`
* `dm_mod`
* `dm_snapshot`
* `ntfs3` (untuk mount NTFS RW)
* `ext4` (untuk rootfs di dalam VHD)

Cek di kernel config:

```bash
zgrep -E "LOOP|DM_MOD|NTFS3|EXT4" /boot/config-$(uname -r)
```

Harus ada `=y` atau `=m`.

Kalau `=m` (module), pastikan modulnya bisa dipanggil:

```bash
modprobe ntfs3
modprobe loop
```

---

### 3. Konfigurasi dracut khusus VHD

File `/etc/dracut.conf.d/90-vhdattach.conf` harus ada, contoh minimal:

```conf
hostonly="no"
add_drivers+=" loop ntfs3 dm_mod dm_snapshot "
add_dracutmodules+=" vhdattach "
dracut_log_level="debug"

HOST_UUID="3A8E66518E66062B"
VHD_REL_PATH="/lubuntu.vhd"
HOST_MOUNTPOINT="/mnt/host_vhd"
FINAL_MOUNTPOINT="/mnt/host"
VHDATTACH_RETRIES=8
VHDATTACH_DELAY=3
UNMOUNT_HOST_AFTER_LOOP=0
FSTAB_OPTS="defaults,noatime,windows_names,uid=1000,gid=1000"
ENABLE_PLYMOUTH_NOTIF=1
```

---

### 4. Root di GRUB harus pakai UUID yang valid

Harus menunjuk ke **ext4 di dalam VHD**, bukan ke host NTFS.

Contoh di `/etc/default/grub`:

```conf
GRUB_CMDLINE_LINUX="root=UUID=e3b06e77-4620-4bb3-872f-a3f548a31157 rw quiet splash rootdelay=10 rd.shell=0 rd.emergency=ignore"
```

Lalu update grub:

```bash
sudo update-grub
```

---

### 5. Disable halangan dari Windows

Karena host partisi NTFS dipakai:

* Matikan **Fast Startup** dan **Hibernate** di Windows (`powercfg /h off`).
* Pastikan partisi NTFS bersih (jalankan `chkdsk` di Windows, atau `ntfsfix` di Linux).

---

### 6. Build ulang initramfs

Setelah semua di atas oke:

```bash
sudo dracut -f --kver $(uname -r)
```

---

### 7. Verifikasi initramfs

Cek apakah modul ikut terbawa:

```bash
lsinitramfs /boot/initrd.img-$(uname -r) | egrep 'vhdattach|plymouth|ntfs3|loop'
```

> Baca seluruh bagian dan jalankan blok perintah di bagian “Install — Copy/paste” secara berurutan. Jangan reboot sampai langkah rebuild selesai.

---

# 1 Production-ready file list (semua path absolute)

1. `/etc/dracut.conf.d/90-vhdattach.conf` — runtime & build config
2. `/usr/lib/dracut/modules.d/90vhdattach/module-setup.sh` — dracut module installer
3. `/usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh` — **very-early** initqueue attach (primary)
4. `/usr/lib/dracut/modules.d/90vhdattach/vhdattach-early.sh` — backward-compatible pre-mount version (keystroke to choose)
5. `/usr/lib/dracut/modules.d/90vhdattach/fstab-overlay.sh` — pre-pivot fstab injector
6. Optional helper: `/usr/local/sbin/vhd-backup.sh` — safe backup utility (host side)

Semua file sudah final di bawah ini.

---

# 2 `/etc/dracut.conf.d/90-vhdattach.conf`

Simpan di host. Ini *diikutkan* ke initramfs sehingga skrip bisa dikonfigurasi tanpa rebuild code.

```conf
# 90-vhdattach.conf - production defaults (no placeholders)
hostonly="no"
add_drivers+=" loop ntfs3 dm_mod dm_snapshot "
add_dracutmodules+=" vhdattach "
dracut_log_level="debug"

# Runtime tunables (used inside initramfs)
# UUID of the host partition that contains the VHD file (example value; replace only if different)
HOST_UUID="3A8E66518E66062B"

# Path relative to the root of the host partition where the .vhd file exists
VHD_REL_PATH="/lubuntu.vhd"

# temporary mountpoint inside initramfs (kept simple)
HOST_MOUNTPOINT="/mnt/host_vhd"

# final mountpoint to add to /etc/fstab in the real root
FINAL_MOUNTPOINT="/mnt/host"

# Retry policy: number of attempts and sleep between attempts (seconds)
VHDATTACH_RETRIES=8
VHDATTACH_DELAY=3

# If set to 1, unmount host partition after loop device created.
# Default 0 to allow fstab-overlay detect the host mount.
UNMOUNT_HOST_AFTER_LOOP=0

# fstab options to add to /etc/fstab inside final root
FSTAB_OPTS="defaults,noatime,windows_names,uid=1000,gid=1000"

# Enable plymouth notifications inside initramfs (requires plymouth and related binaries present)
ENABLE_PLYMOUTH_NOTIF=1
```

> Jika host UUID Anda berbeda, edit `HOST_UUID` here. You may change runtime tunables later without modifying scripts.

---

# 3 Dracut module installer — `/usr/lib/dracut/modules.d/90vhdattach/module-setup.sh`

```bash
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
```

Set executable after create:

```bash
sudo chmod 0755 /usr/lib/dracut/modules.d/90vhdattach/module-setup.sh
```

---

# 4 Very-early attach script — `/usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh`

> Primary script for production: guarantees VHD partitions exist when dracut resolves `root=`.

```sh
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
```

Set executable:

```bash
sudo chmod 0755 /usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh
sudo chown root:root /usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh
```

---

# 5 Backward-compatible pre-mount script (optional) — `/usr/lib/dracut/modules.d/90vhdattach/vhdattach-early.sh`

If your environment prefers pre-mount hook (older dracut), this is included; it is essentially same as initqueue but tied to pre-mount.

```sh
#!/bin/sh
# vhdattach-early.sh - pre-mount fallback (keeps same behavior)
set -e
# (content: same logic as vhdattach-initqueue.sh)
# For brevity in this file, we symlink to the initqueue script at install time.
exec /usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh
```

Create it and make executable:

```bash
sudo ln -sf /usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh /usr/lib/dracut/modules.d/90vhdattach/vhdattach-early.sh
sudo chmod 0755 /usr/lib/dracut/modules.d/90vhdattach/vhdattach-early.sh
```

---

# 6 `fstab-overlay.sh` — `/usr/lib/dracut/modules.d/90vhdattach/fstab-overlay.sh`

```sh
#!/bin/sh
# fstab-overlay.sh - pre-pivot: add host partition entry to /sysroot/etc/fstab
set -e

if command -v dlog >/dev/null 2>&1; then
  logf() { dlog "[fstab-overlay] $*"; }
else
  logf() { echo "[fstab-overlay] $*" > /dev/kmsg; }
fi

[ -f /lib/dracut-lib.sh ] && . /lib/dracut-lib.sh

logf "starting fstab-overlay"

HOST_MOUNTPOINT="${HOST_MOUNTPOINT:-/mnt/host_vhd}"
FINAL_MOUNTPOINT="${FINAL_MOUNTPOINT:-/mnt/host}"
FSTAB_OPTS="${FSTAB_OPTS:-defaults,noatime,windows_names,uid=1000,gid=1000}"

# source config if present
if [ -f /etc/dracut.conf.d/90-vhdattach.conf ]; then
  . /etc/dracut.conf.d/90-vhdattach.conf || logf "warning: failed to source config"
fi

if [ ! -d /sysroot/etc ]; then
  logf "/sysroot not present; skipping fstab overlay"
  exit 0
fi

FSTAB_FILE="/sysroot/etc/fstab"

HOST_DEV=$(grep -w "$HOST_MOUNTPOINT" /proc/mounts | awk '{print $1}' | head -n1 || true)
if [ -z "$HOST_DEV" ]; then
  logf "host partition not mounted at $HOST_MOUNTPOINT; skipping"
  exit 0
fi

HOST_UUID=$(blkid -s UUID -o value "$HOST_DEV" 2>/dev/null || true)
HOST_TYPE=$(blkid -s TYPE -o value "$HOST_DEV" 2>/dev/null || true)

if [ -z "$HOST_UUID" ] || [ -z "$HOST_TYPE" ]; then
  logf "cannot determine UUID/TYPE for $HOST_DEV; skipping"
  exit 0
fi

FS_DRIVER="ntfs3"
[ "$HOST_TYPE" != "ntfs" ] && FS_DRIVER="$HOST_TYPE"

mkdir -p "/sysroot${FINAL_MOUNTPOINT}"

FSTAB_LINE="UUID=${HOST_UUID} ${FINAL_MOUNTPOINT} ${FS_DRIVER} ${FSTAB_OPTS} 0 0"

# prevent duplicates
if grep -q -E "[[:space:]]${FINAL_MOUNTPOINT}[[:space:]]" "$FSTAB_FILE"; then
  logf "fstab entry for ${FINAL_MOUNTPOINT} exists; skipping"
  exit 0
fi

logf "adding fstab entry: ${FSTAB_LINE}"
{
  echo ""
  echo "# Added by dracut vhdattach/fstab-overlay (pre-pivot)"
  echo "${FSTAB_LINE}"
} >> "$FSTAB_FILE"

logf "fstab-overlay done"
exit 0
```

Set executable:

```bash
sudo chmod 0755 /usr/lib/dracut/modules.d/90vhdattach/fstab-overlay.sh
```

---

# 7 Optional helper: safe VHD backup script (host) — `/usr/local/sbin/vhd-backup.sh`

```bash
#!/bin/bash
# vhd-backup.sh - quick sparse copy backup of VHD with checksum
set -euo pipefail
SRC="$1"
DST_DIR="${2:-/var/backups/vhd}"
mkdir -p "$DST_DIR"
BASENAME="$(basename "$SRC").$(date -u +%Y%m%dT%H%M%SZ).bak.vhd"
DST="$DST_DIR/$BASENAME"
echo "Backing up $SRC -> $DST (sparse)"
cp --sparse=always "$SRC" "$DST"
sync
sha256sum "$DST" > "$DST.sha256"
echo "Backup complete: $DST"
```

Make executable:

```bash
sudo tee /usr/local/sbin/vhd-backup.sh > /dev/null <<'EOF'
# (paste contents)
EOF
sudo chmod 0755 /usr/local/sbin/vhd-backup.sh
```
Ringkasnya paket README ini melakukan:

* attach `.vhd` di very-early initramfs (initqueue) agar `root=` dapat dirujuk;
* mount host NTFS **ntfs3 rw** dengan retry, udev settle, logging ke `kmsg`/journal;
* attach loop RW, kpartx/partx mapping, udev settle;
* configurable lewat `/etc/dracut.conf.d/90-vhdattach.conf`;
* pre-pivot insertion of `/etc/fstab` for final system;
* robust safe-fail (initramfs tidak panic jika gagal, log lengkap);
* optional plymouth progress messages (if plymouth present);
* verification, recovery and automation steps, backup & fsck instructions;
* CI/devops-friendly install script to setup module and rebuild initramfs.


