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
