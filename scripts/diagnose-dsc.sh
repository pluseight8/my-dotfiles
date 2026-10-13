#!/usr/bin/env bash
set -u

echo "=== honor-force-dsc.service ==="
systemctl status honor-force-dsc.service --no-pager -l || true

echo
echo "=== honor-force-dsc journal ==="
journalctl -u honor-force-dsc.service -b --no-pager -n 100 || true

echo
echo "=== DSC debugfs ==="
if ! mountpoint -q /sys/kernel/debug; then
  mount -t debugfs debugfs /sys/kernel/debug || true
fi

found=0
for f in /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support; do
  [[ -e "$f" ]] || continue
  found=1
  echo "===== $f ====="
  cat "$f" || true
done

if (( ! found )); then
  echo "No i915_dsc_fec_support file found."
fi
