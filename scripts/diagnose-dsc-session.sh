#!/usr/bin/env bash
set -u

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_RUNTIME="/run/user/$TARGET_UID"
TARGET_BUS="unix:path=$TARGET_RUNTIME/bus"

run_user() {
  runuser -u "$TARGET_USER" -- env \
    XDG_RUNTIME_DIR="$TARGET_RUNTIME" \
    DBUS_SESSION_BUS_ADDRESS="$TARGET_BUS" \
    "$@"
}

echo "=== target user ==="
echo "user=$TARGET_USER uid=$TARGET_UID runtime=$TARGET_RUNTIME"

echo
echo "=== honor-dsc-modeset.service ==="
run_user systemctl --user status honor-dsc-modeset.service --no-pager -l || true

echo
echo "=== honor-dsc-modeset journal ==="
run_user journalctl --user -u honor-dsc-modeset.service -b --no-pager -n 100 || true

echo
echo "=== user-manager environment ==="
run_user systemctl --user show-environment 2>/dev/null \
  | grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|PATH)=' || true

echo
echo "=== Hyprland runtime dirs ==="
find "$TARGET_RUNTIME/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n || true

SIG=""
HYPR_DIR="$(find "$TARGET_RUNTIME/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)"
[[ -n "$HYPR_DIR" ]] && SIG="${HYPR_DIR##*/}"

echo
echo "=== hyprctl monitors ==="
if [[ -n "$SIG" ]]; then
  run_user env HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl monitors -j 2>&1 || true
else
  echo "No Hyprland runtime instance found under $TARGET_RUNTIME/hypr"
fi

echo
echo "=== current DSC ==="
for f in /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support; do
  [[ -r "$f" ]] || continue
  echo "===== $f ====="
  cat "$f" 2>/dev/null || sudo cat "$f" 2>/dev/null || true
done
