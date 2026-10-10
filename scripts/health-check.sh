#!/usr/bin/bash
set -u

LOG=/var/lib/honor/health-last.txt
mkdir -p /var/lib/honor
exec > >(tee "$LOG") 2>&1

FAIL=0
ok()   { echo "[ OK ] $*"; }
warn() { echo "[WARN] $*"; }
bad()  { echo "[FAIL] $*"; FAIL=1; }

USER_NAME="${HONOR_USER:-}"

printf 'HONOR ZQC-P M1230 health check\n'
printf 'kernel: %s\n\n' "$(uname -r)"

KLOG="$(journalctl -k -b --no-pager 2>/dev/null || true)"
if grep -qE 'AE_AML_INTERNAL.*I2C_DEVT|I2C_DEVT.*AE_AML_INTERNAL' <<<"$KLOG"; then
    bad "ACPI I2C_DEVT returned AE_AML_INTERNAL"
elif grep -q 'Table Upgrade: override.*I2C_DEVT' <<<"$KLOG"; then
    ok "ACPI I2C_DEVT override active"
else
    bad "ACPI I2C_DEVT override not confirmed"
fi

if compgen -G '/sys/bus/hid/devices/*2808:5662*' >/dev/null; then
    ok "touchscreen 2808:5662"
else
    bad "touchscreen 2808:5662 missing"
fi

if compgen -G '/sys/bus/hid/devices/*27C6:0F9A*' >/dev/null || \
   compgen -G '/sys/bus/hid/devices/*27c6:0f9a*' >/dev/null; then
    ok "touchpad 27c6:0f9a"
else
    bad "touchpad 27c6:0f9a missing"
fi

PSR="$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)"
[[ "$PSR" == "1" ]] && ok "xe.enable_psr=1" || bad "xe.enable_psr=${PSR:-missing}"

[[ -f /etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o ]] \
    && ok "micmute HID-BPF object installed" \
    || bad "micmute HID-BPF object missing"

[[ -f /etc/udev-hid-bpf/honor-tops0102-edge.bpf.o ]] \
    && ok "touchpad-edge HID-BPF object installed" \
    || bad "touchpad-edge HID-BPF object missing"

systemctl is-active --quiet honor-hid-bpf-reapply.service \
    && ok "micmute re-apply service active" \
    || bad "micmute re-apply service not active"

PHANTOM="$({
    grep -l UNKNOWN /sys/class/input/input*/name 2>/dev/null || true
} | xargs -r grep -H 2808 2>/dev/null || true)"
[[ -z "$PHANTOM" ]] && ok "phantom KEY_MICMUTE absent" || {
    bad "phantom KEY_MICMUTE returned"
    echo "$PHANTOM"
}

systemctl is-active --quiet honor-zqcp-kbdlight.service \
    && ok "keyboard backlight service active" \
    || bad "keyboard backlight service not active"

[[ -d /sys/class/leds/honor::kbd_backlight ]] \
    && ok "honor::kbd_backlight present" \
    || bad "honor::kbd_backlight missing"

systemctl is-active --quiet honor-force-dsc.service \
    && ok "DSC service active" \
    || bad "DSC service not active"

mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
DSC_FILE="$(find /sys/kernel/debug/dri -path '*/eDP-*/i915_dsc_fec_support' -print -quit 2>/dev/null || true)"
if [[ -n "$DSC_FILE" ]]; then
    DSC="$(cat "$DSC_FILE" 2>/dev/null || true)"
    grep -q 'DSC_Sink_Support: yes' <<<"$DSC" \
        && ok "DSC sink supported" || bad "DSC sink unsupported"
    grep -q 'Force_DSC_Enable: yes' <<<"$DSC" \
        && ok "DSC force enabled" || bad "DSC force not enabled"
    grep -q 'DSC_Enabled: yes' <<<"$DSC" \
        && ok "DSC active" || warn "DSC forced but not active yet"
else
    bad "i915_dsc_fec_support missing"
fi

DISPLAY_INFO="$(find /sys/kernel/debug/dri -name i915_display_info -print -quit 2>/dev/null || true)"
if [[ -n "$DISPLAY_INFO" ]]; then
    PIPE="$(grep -m1 -E 'pipe src=.*bpp=' "$DISPLAY_INFO" 2>/dev/null || true)"
    if grep -q 'bpp=30' <<<"$PIPE" && grep -q 'dither=no' <<<"$PIPE"; then
        ok "display: bpp=30, dither=no"
    elif [[ -n "$PIPE" ]]; then
        warn "display state: $PIPE"
    else
        warn "display pipe state not found"
    fi
else
    warn "i915_display_info missing"
fi

FP_PRESENT=0
for d in /sys/bus/usb/devices/*; do
    [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
    if [[ "$(cat "$d/idVendor")" == "1c7a" && "$(cat "$d/idProduct")" == "05aa" ]]; then
        FP_PRESENT=1
        break
    fi
done
(( FP_PRESENT )) && ok "fingerprint USB 1c7a:05aa present" || bad "fingerprint USB 1c7a:05aa missing"

if [[ -d /opt/honor-libfprint-sdcp ]]; then
    ok "private SDCP libfprint directory exists"
    if ldconfig -p 2>/dev/null | grep -q '/opt/honor-libfprint-sdcp'; then
        ok "private SDCP libfprint is in ld cache"
    else
        bad "private SDCP libfprint missing from ld cache"
    fi
else
    bad "/opt/honor-libfprint-sdcp missing"
fi

if [[ -n "$USER_NAME" ]] && command -v fprintd-list >/dev/null 2>&1; then
    FP_OUT="$(timeout 20 fprintd-list "$USER_NAME" 2>&1 || true)"
    if grep -qiE 'no fingers enrolled|finger' <<<"$FP_OUT"; then
        ok "fprintd responds for $USER_NAME"
    else
        warn "fprintd check inconclusive for $USER_NAME"
    fi
fi

printf '\n'
if (( FAIL )); then
    echo "RESULT: FAIL"
    exit 1
fi

echo "RESULT: OK"
