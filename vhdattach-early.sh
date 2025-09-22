#!/bin/sh
# vhdattach-early.sh - pre-mount fallback (keeps same behavior)
set -e
# (content: same logic as vhdattach-initqueue.sh)
# For brevity in this file, we symlink to the initqueue script at install time.
exec /usr/lib/dracut/modules.d/90vhdattach/vhdattach-initqueue.sh
