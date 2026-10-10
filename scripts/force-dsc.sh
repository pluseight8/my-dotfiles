#!/usr/bin/bash
set -euo pipefail

mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug

for _ in $(seq 1 150); do
    DSC_FILE=$(find /sys/kernel/debug/dri \
      -path '*/eDP-*/i915_dsc_fec_support' \
      -print -quit 2>/dev/null || true)

    if [[ -n "$DSC_FILE" ]]; then
        grep -q 'DSC_Sink_Support: yes' "$DSC_FILE" || {
            echo "HONOR: panel does not report DSC support" >&2
            exit 1
        }
        echo 1 > "$DSC_FILE"
        exit 0
    fi

    sleep 0.2
done

echo "HONOR: i915_dsc_fec_support not found" >&2
exit 1
