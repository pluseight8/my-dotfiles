#!/usr/bin/bash
set -u

PRE_REBOOT=0
[[ "${1:-}" == "--pre-reboot" ]] && PRE_REBOOT=1

LOG=/var/lib/honor/health-last.txt
mkdir -p /var/lib/honor
exec > >(tee "$LOG") 2>&1

FAIL=0
ok()   { echo "[ OK ] $*"; }
warn() { echo "[WARN] $*"; }
bad()  { echo "[FAIL] $*"; FAIL=1; }

echo "HONOR ZQC-P M1230 / Omarchy health check"
echo "kernel: $(uname -r)"
echo

command -v omarchy >/dev/null 2>&1 && ok "Omarchy CLI present" || bad "Omarchy CLI missing"

KLOG="$(journalctl -k -b --no-pager 2>/dev/null || true)"
if grep -qE 'AE_AML_INTERNAL.*I2C_DEVT|I2C_DEVT.*AE_AML_INTERNAL' <<<"$KLOG"; then
    bad "ACPI I2C_DEVT returned AE_AML_INTERNAL"
elif grep -q 'Table Upgrade: override.*I2C_DEVT' <<<"$KLOG"; then
    ok "ACPI I2C_DEVT override active"
else
    bad "ACPI I2C_DEVT override not confirmed"
fi

compgen -G '/sys/bus/hid/devices/*2808:5662*' >/dev/null     && ok "touchscreen 2808:5662" || bad "touchscreen 2808:5662 missing"

if compgen -G '/sys/bus/hid/devices/*27C6:0F9A*' >/dev/null ||    compgen -G '/sys/bus/hid/devices/*27c6:0f9a*' >/dev/null; then
    ok "touchpad 27c6:0f9a"
else
    bad "touchpad 27c6:0f9a missing"
fi

PSR="$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)"
[[ "$PSR" == 1 ]] && ok "xe.enable_psr=1" || bad "xe.enable_psr=${PSR:-missing}"

[[ -f /etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o ]]     && ok "micmute HID-BPF object installed" || bad "micmute HID-BPF object missing"
[[ -f /etc/udev-hid-bpf/honor-tops0102-edge.bpf.o ]]     && ok "touchpad-edge HID-BPF object installed" || bad "touchpad-edge HID-BPF object missing"

systemctl is-active --quiet honor-hid-bpf-reapply.service     && ok "micmute re-apply service active" || bad "micmute re-apply service not active"

PHANTOM="$({ grep -l UNKNOWN /sys/class/input/input*/name 2>/dev/null || true; }     | xargs -r grep -H 2808 2>/dev/null || true)"
[[ -z "$PHANTOM" ]] && ok "phantom KEY_MICMUTE absent" || bad "phantom KEY_MICMUTE returned"

systemctl is-active --quiet honor-zqcp-kbdlight.service     && ok "keyboard backlight service active" || bad "keyboard backlight service not active"
[[ -d /sys/class/leds/honor::kbd_backlight ]]     && ok "honor::kbd_backlight present" || bad "honor::kbd_backlight missing"

mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
DSC_FILE="$(find /sys/kernel/debug/dri -path '*/eDP-*/i915_dsc_fec_support' -print -quit 2>/dev/null || true)"
if [[ -n "$DSC_FILE" ]]; then
    DSC="$(cat "$DSC_FILE" 2>/dev/null || true)"
    grep -q 'DSC_Sink_Support: yes' <<<"$DSC"         && ok "DSC sink supported" || bad "DSC sink unsupported"
    grep -q 'Force_DSC_Enable: yes' <<<"$DSC"         && ok "DSC force enabled" || bad "DSC force not enabled"

    if grep -q 'DSC_Enabled: yes' <<<"$DSC"; then
        ok "DSC active"
    elif ((PRE_REBOOT)); then
        warn "DSC is forced; final clean boot still needs to prove it active"
    else
        bad "DSC forced but not active"
    fi
else
    bad "i915_dsc_fec_support missing"
fi

DISPLAY_INFO="$(find /sys/kernel/debug/dri -name i915_display_info -print -quit 2>/dev/null || true)"
if [[ -n "$DISPLAY_INFO" ]]; then
    PIPE="$(grep -m1 -E 'pipe src=.*bpp=' "$DISPLAY_INFO" 2>/dev/null || true)"
    if grep -q 'bpp=30' <<<"$PIPE" && grep -q 'dither=no' <<<"$PIPE"; then
        ok "display: bpp=30, dither=no"
    elif ((PRE_REBOOT)); then
        warn "display state before final boot: ${PIPE:-unknown}"
    else
        bad "display state: ${PIPE:-unknown}"
    fi
else
    bad "i915_display_info missing"
fi

FP_PRESENT=0
for d in /sys/bus/usb/devices/*; do
    [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
    if [[ "$(cat "$d/idVendor")" == 1c7a && "$(cat "$d/idProduct")" == 05aa ]]; then
        FP_PRESENT=1
        break
    fi
done
((FP_PRESENT)) && ok "fingerprint USB 1c7a:05aa present" || bad "fingerprint USB 1c7a:05aa missing"

[[ -d /opt/honor-libfprint-sdcp ]]     && ok "private EgisTec SDCP libfprint installed" || bad "private EgisTec SDCP libfprint missing"
ldconfig -p 2>/dev/null | grep -q '/opt/honor-libfprint-sdcp'     && ok "private SDCP libfprint is in loader cache" || bad "private SDCP libfprint missing from loader cache"

echo
if ((FAIL)); then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: OK"
