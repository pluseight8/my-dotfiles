#!/usr/bin/env bash
set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || {
    echo "HONOR: hyprctl is missing" >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    echo "HONOR: jq is missing" >&2
    exit 1
}

runtime="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export XDG_RUNTIME_DIR="$runtime"

# UWSM normally imports HYPRLAND_INSTANCE_SIGNATURE into the user manager.
# If this service is started before that variable is visible, recover the live
# instance from Hyprland's runtime directory instead of silently doing nothing.
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hypr_dir="$(find "$runtime/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)"
    [[ -n "$hypr_dir" ]] && export HYPRLAND_INSTANCE_SIGNATURE="${hypr_dir##*/}"
fi

monitor=""
for _ in $(seq 1 100); do
    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        hypr_dir="$(find "$runtime/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)"
        [[ -n "$hypr_dir" ]] && export HYPRLAND_INSTANCE_SIGNATURE="${hypr_dir##*/}"
    fi

    json="$(hyprctl monitors -j 2>/dev/null || true)"
    monitor="$(jq -r '.[] | select(.name | startswith("eDP-")) | .name' <<<"$json" 2>/dev/null | head -n1)"
    [[ -n "$monitor" && "$monitor" != null ]] && break
    sleep 0.2
done

[[ -n "$monitor" && "$monitor" != null ]] || {
    echo "HONOR: no live internal eDP monitor became available" >&2
    exit 1
}

echo "HONOR: triggering one Hyprland modeset on $monitor"
hyprctl dispatch dpms off "$monitor" >/dev/null
sleep 1
hyprctl dispatch dpms on "$monitor" >/dev/null
sleep 1

# Make sure the compositor still answers after the cycle.
hyprctl monitors -j >/dev/null
echo "HONOR: post-login eDP modeset completed"
