#!/usr/bin/env bash
set -uo pipefail

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

recover_signature() {
    local hypr_dir
    hypr_dir="$(find "$runtime/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)"
    [[ -n "$hypr_dir" ]] || return 1
    export HYPRLAND_INSTANCE_SIGNATURE="${hypr_dir##*/}"
}

[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || recover_signature || true

monitor=""
for _ in $(seq 1 100); do
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || recover_signature || true

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

# Hyprland can transiently return exit status 7/NOTRUNNING while the internal
# output is deliberately DPMS-cycled. The command may still have been accepted
# (and on M1230 it is enough to activate the already-armed DSC state), so do not
# let that transient status abort the oneshot before we turn the panel back on.
hyprctl dispatch dpms off "$monitor" >/dev/null 2>&1 || true
sleep 1

panel_on=0
for _ in $(seq 1 50); do
    if ! hyprctl dispatch dpms on "$monitor" >/dev/null 2>&1; then
        recover_signature || true
        sleep 0.2
        continue
    fi

    json="$(hyprctl monitors -j 2>/dev/null || true)"
    if jq -e --arg mon "$monitor" '.[] | select(.name == $mon and .dpmsStatus == true)' <<<"$json" >/dev/null 2>&1; then
        panel_on=1
        break
    fi
    sleep 0.2
done

(( panel_on )) || {
    echo "HONOR: eDP panel did not return after the DPMS modeset" >&2
    exit 1
}

echo "HONOR: post-login eDP modeset completed"
