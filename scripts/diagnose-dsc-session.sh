#!/usr/bin/env bash
set -u

echo "=== honor-dsc-modeset.service ==="
systemctl --user status honor-dsc-modeset.service --no-pager -l || true

echo
echo "=== honor-dsc-modeset journal ==="
journalctl --user -u honor-dsc-modeset.service -b --no-pager -n 100 || true

echo
echo "=== user-manager environment ==="
systemctl --user show-environment 2>/dev/null | grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|PATH)=' || true

echo
echo "=== Hyprland runtime dirs ==="
find "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n || true

echo
echo "=== hyprctl monitors ==="
hyprctl monitors -j 2>&1 || true

echo
echo "=== current DSC ==="
for f in /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support; do
  [[ -r "$f" ]] || continue
  echo "===== $f ====="
  cat "$f" 2>/dev/null || sudo cat "$f" 2>/dev/null || true
done
