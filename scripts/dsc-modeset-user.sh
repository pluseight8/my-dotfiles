#!/usr/bin/env bash
set -euo pipefail

command -v hyprctl >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

monitor=""
for _ in $(seq 1 50); do
    json="$(hyprctl monitors -j 2>/dev/null || true)"
    monitor="$(jq -r '.[] | select(.name | startswith("eDP-")) | .name' <<<"$json" 2>/dev/null | head -n1)"
    [[ -n "$monitor" && "$monitor" != null ]] && break
    sleep 0.2
done

[[ -n "$monitor" && "$monitor" != null ]] || exit 0

# Force one compositor-owned modeset after the root DSC service has armed
# Force_DSC_Enable. This keeps the stock Omarchy kernel intact.
hyprctl dispatch dpms off "$monitor" >/dev/null 2>&1 || exit 0
sleep 0.8
hyprctl dispatch dpms on "$monitor" >/dev/null 2>&1 || true
