#!/usr/bin/bash
set -euo pipefail

if ! mountpoint -q /sys/kernel/debug; then
    mount -t debugfs debugfs /sys/kernel/debug
fi

DSC_FILE=""
for _ in $(seq 1 200); do
    DSC_FILE="$(find /sys/kernel/debug/dri \
        -path '*/eDP-*/i915_dsc_fec_support' \
        -print -quit 2>/dev/null || true)"
    [[ -n "$DSC_FILE" ]] && break
    sleep 0.1
done

[[ -n "$DSC_FILE" ]] || {
    echo "HONOR: i915_dsc_fec_support not found" >&2
    exit 1
}

grep -q 'DSC_Sink_Support: yes' "$DSC_FILE" || {
    echo "HONOR: internal panel does not report DSC support" >&2
    exit 1
}

[[ -w "$DSC_FILE" ]] || {
    echo "HONOR: DSC debugfs control is not writable" >&2
    exit 1
}

# Force the panel's advertised 10 bpc as the DSC input depth before enabling
# compression. Without this, the generic force-DSC path can inherit the
# reduced 8 bpc baseline and come up at bpp=24 even though this OLED advertises
# 10 bpc. The connector-local debugfs knob is provided by the Intel display
# driver specifically for forcing DSC input BPC.
DSC_BPC_FILE="$(dirname "$DSC_FILE")/i915_dsc_bpc"
[[ -w "$DSC_BPC_FILE" ]] || {
    echo "HONOR: i915_dsc_bpc control is missing or not writable: $DSC_BPC_FILE" >&2
    exit 1
}

echo 10 > "$DSC_BPC_FILE"
echo 1 > "$DSC_FILE"

for _ in $(seq 1 50); do
    if grep -q 'Force_DSC_Enable: yes' "$DSC_FILE"; then
        if grep -q 'DSC_Enabled: yes' "$DSC_FILE"; then
            echo "HONOR: DSC force is enabled and DSC is active"
        else
            echo "HONOR: DSC force is enabled; activation is pending the next display modeset"
        fi
        exit 0
    fi
    sleep 0.1
done

echo "HONOR: kernel did not accept Force_DSC_Enable" >&2
cat "$DSC_FILE" >&2 || true
exit 1
