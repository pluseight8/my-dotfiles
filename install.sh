#!/usr/bin/bash
set -euo pipefail

ORIGINAL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ORIGINAL_ROOT/scripts/lib/common.sh"

YES=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) YES=1 ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./install.sh [--yes]

POST-REBOOT installer only.

It refuses to run until the manual pre-reboot phase is active:
- dependencies already installed and booted
- audited ACPI override active
- xe.enable_psr=1 active

This script does NOT run rpm-ostree and does NOT reboot the machine.
HELP
            exit 0
            ;;
        *) die "unknown argument: $arg" ;;
    esac
done

require_root
assert_bazzite
assert_m1230
assert_host_dependencies_present
assert_secure_boot_off
assert_selinux_enforcing
assert_kernel_build_tree
require_cmds git python3 systemctl md5sum install find awk grep flock ldconfig lsusb authselect

if [[ "$ORIGINAL_ROOT" != "$HONOR_REPO_INSTALL_DIR" ]]; then
    log "copying installer payload to $HONOR_REPO_INSTALL_DIR"
    safe_rm_tree "$HONOR_REPO_INSTALL_DIR"
    install -d -m755 "$(dirname "$HONOR_REPO_INSTALL_DIR")"
    cp -a "$ORIGINAL_ROOT" "$HONOR_REPO_INSTALL_DIR"
    exec /usr/bin/bash "$HONOR_REPO_INSTALL_DIR/install.sh" "$@"
fi

REPO_ROOT="$HONOR_REPO_INSTALL_DIR"
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/lib/common.sh"

install -d -m755 "$HONOR_STATE_DIR"
touch "$HONOR_LOG"
chmod 600 "$HONOR_LOG"
exec > >(tee -a "$HONOR_LOG") 2>&1
exec 9>"$HONOR_STATE_DIR/install.lock"
flock -n 9 || die "another HONOR M1230 installation process is already running"

TARGET_USER="${SUDO_USER:-}"
[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || die "run sudo from your normal desktop account"

cat > /etc/honor-m1230.conf <<EOFCONF
HONOR_USER=$TARGET_USER
EOFCONF
chmod 644 /etc/honor-m1230.conf

if (( ! YES )); then
    cat <<'CONFIRM'
This installs the post-reboot HONOR M1230 runtime fixes:
- HID-BPF micmute/touchpad-edge
- private fingerprint libfprint
- keyboard-backlight module/service
- DSC service
- boot health-check

It will NOT modify rpm-ostree and will NOT reboot.
Type INSTALL to continue:
CONFIRM
    read -r answer
    [[ "$answer" == INSTALL ]] || die "cancelled"
fi

verify_manual_pre_reboot_phase() {
    log "verifying the manual pre-reboot phase"

    [[ -r "$HONOR_STATE_DIR/pre-reboot-staged" ]] || die "pre-reboot stage marker missing; run sudo ./pre-reboot.sh --yes, inspect rpm-ostree status, and reboot manually"
    [[ -d "$HONOR_UPSTREAM_DIR/.git" ]] || die "prepared HONOR support source missing: $HONOR_UPSTREAM_DIR"
    grep -q "^\[board M1230\]$" "$HONOR_UPSTREAM_DIR/devices/zqc-p.conf" || die "M1230 adaptation missing from HONOR support source"

    local klog
    klog="$(journalctl -k -b --no-pager 2>/dev/null || true)"
    grep -q 'Table Upgrade: override.*I2C_DEVT' <<<"$klog" || die "ACPI I2C_DEVT override is not active; reboot the staged deployment before running install.sh"
    ! grep -qE 'AE_AML_INTERNAL.*I2C_DEVT|I2C_DEVT.*AE_AML_INTERNAL' <<<"$klog" || die "AE_AML_INTERNAL returned after ACPI override"
    ! grep -qi 'locked down.*table override' <<<"$klog" || die "kernel lockdown rejected the ACPI override"

    compgen -G '/sys/bus/hid/devices/*2808:5662*' >/dev/null || die "touchscreen 2808:5662 missing"
    { compgen -G '/sys/bus/hid/devices/*27C6:0F9A*' >/dev/null || compgen -G '/sys/bus/hid/devices/*27c6:0f9a*' >/dev/null; } || die "touchpad 27c6:0f9a missing"
    [[ "$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)" == 1 ]] || die "xe.enable_psr is not active; reboot the staged deployment first"
}

install_hid_bpf() {
    log "installing touchscreen micmute HID-BPF"
    retry 3 10 env ALLOW_UNVERIFIED=1 \
        bash "$HONOR_UPSTREAM_DIR/patch/micmute/install.sh" || die "micmute HID-BPF install failed"

    log "installing touchpad left-edge brightness HID-BPF"
    retry 3 10 env ALLOW_UNVERIFIED=1 \
        bash "$HONOR_UPSTREAM_DIR/patch/touchpad-edge/install.sh" || die "touchpad-edge HID-BPF install failed"

    [[ -f /etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o ]] || die "micmute BPF object missing"
    [[ -f /etc/udev-hid-bpf/honor-tops0102-edge.bpf.o ]] || die "touchpad-edge BPF object missing"
}

install_fingerprint() {
    log "installing private SDCP libfprint for EgisTec 1c7a:05aa"
    lsusb -d "$HONOR_FINGERPRINT_ID" >/dev/null 2>&1 || die "fingerprint reader $HONOR_FINGERPRINT_ID is not on USB bus"
    retry 3 10 env ALLOW_UNVERIFIED=1 \
        bash "$HONOR_UPSTREAM_DIR/patch/fingerprint/install.sh" || die "fingerprint support install failed"
    ldconfig
    systemctl restart fprintd.service 2>/dev/null || true
    [[ -d /opt/honor-libfprint-sdcp ]] || die "private SDCP libfprint prefix missing"
    ldconfig -p | grep -q '/opt/honor-libfprint-sdcp' || die "private SDCP libfprint not in ld cache"

    if ! authselect enable-feature with-fingerprint; then
        warn "authselect could not enable with-fingerprint automatically; fprintd itself is installed"
    fi
}

install_keyboard_backlight() {
    log "installing M1230 keyboard backlight driver"
    bash "$REPO_ROOT/honor-zqcp-kbdlight/install-bazzite.sh"
    systemctl is-active --quiet honor-zqcp-kbdlight.service || die "keyboard backlight service not active"
    [[ -d /sys/class/leds/honor::kbd_backlight ]] || die "honor::kbd_backlight missing"
}

install_dsc() {
    log "installing DSC service"
    install -d -m755 /usr/local/lib/honor
    install -m755 "$REPO_ROOT/scripts/force-dsc.sh" /usr/local/lib/honor/force-dsc.sh
    install -m644 "$REPO_ROOT/systemd/honor-force-dsc.service" /etc/systemd/system/honor-force-dsc.service
    systemctl daemon-reload
    systemctl enable honor-force-dsc.service >/dev/null
    systemctl restart honor-force-dsc.service
    systemctl is-active --quiet honor-force-dsc.service || die "DSC service not active"

    local dsc_file display_info pipe
    dsc_file="$(find /sys/kernel/debug/dri -path '*/eDP-*/i915_dsc_fec_support' -print -quit 2>/dev/null || true)"
    [[ -n "$dsc_file" ]] || die "DSC debugfs file missing"
    grep -q 'DSC_Enabled: yes' "$dsc_file" || die "DSC is not active"
    grep -q 'Force_DSC_Enable: yes' "$dsc_file" || die "DSC force is not enabled"

    display_info="$(find /sys/kernel/debug/dri -name i915_display_info -print -quit 2>/dev/null || true)"
    [[ -n "$display_info" ]] || die "i915_display_info missing"
    pipe="$(grep -m1 -E 'pipe src=.*bpp=' "$display_info" 2>/dev/null || true)"
    grep -q 'bpp=30' <<<"$pipe" || die "display is not bpp=30"
    grep -q 'dither=no' <<<"$pipe" || die "display still uses dithering"
}

install_health_check() {
    log "installing boot health check"
    install -m755 "$REPO_ROOT/scripts/health-check.sh" /usr/local/lib/honor/health-check.sh
    install -m644 "$REPO_ROOT/systemd/honor-health-check.service" /etc/systemd/system/honor-health-check.service
    install -m644 "$REPO_ROOT/systemd/honor-health-check.timer" /etc/systemd/system/honor-health-check.timer
    systemctl daemon-reload
    systemctl enable honor-health-check.timer >/dev/null
    systemctl restart honor-health-check.timer
}

verify_manual_pre_reboot_phase
install_hid_bpf
install_fingerprint
install_keyboard_backlight
install_dsc
install_health_check

systemctl restart upower.service 2>/dev/null || true
restart_powerdevil_for_user "$TARGET_USER"

log "running current-boot health check"
if ! HONOR_USER="$TARGET_USER" /usr/local/lib/honor/health-check.sh; then
    die "current-boot health check failed; see /var/lib/honor/health-last.txt"
fi

printf 'installed=%s\nkernel=%s\nuser=%s\n' \
    "$(date --iso-8601=seconds)" "$(uname -r)" "$TARGET_USER" \
    > "$HONOR_STATE_DIR/runtime-install-complete"
chmod 600 "$HONOR_STATE_DIR/runtime-install-complete"

echo
log "RUNTIME INSTALL: OK"
echo "No reboot was performed by install.sh."
echo
echo "For the final persistence test, reboot yourself when you are ready:"
echo "  systemctl reboot"
echo
echo "After login wait about 60 seconds, then:"
echo "  cat /var/lib/honor/health-last.txt"
echo
echo "Expected final line: RESULT: OK"
echo
echo "Fingerprint enrollment (normal user):"
echo "  fprintd-enroll -f right-index-finger"
echo "  fprintd-verify"
