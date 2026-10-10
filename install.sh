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

POST-REBOOT runtime installer for HONOR ZQC-P / M1230 on Omarchy.

It does NOT install packages, does NOT touch Limine/mkinitcpio/kernel command
line, and does NOT reboot. Complete the manual boot-staging section in
docs/INSTALL.md and boot it before running this script.
HELP
            exit 0
            ;;
        *) die "unknown argument: $arg" ;;
    esac
done

require_root
assert_omarchy
assert_m1230
assert_dependencies_present
assert_lockdown_off
assert_kernel_build_tree
require_cmds systemctl find grep install ldconfig lsusb timeout flock

if [[ "$ORIGINAL_ROOT" != "$HONOR_REPO_INSTALL_DIR" ]]; then
    log "copying runtime payload to $HONOR_REPO_INSTALL_DIR"
    safe_rm_tree "$HONOR_REPO_INSTALL_DIR"
    install -d -m755 "$(dirname "$HONOR_REPO_INSTALL_DIR")"
    cp -a "$ORIGINAL_ROOT" "$HONOR_REPO_INSTALL_DIR"
    exec /usr/bin/bash "$HONOR_REPO_INSTALL_DIR/install.sh" "$@"
fi

REPO_ROOT="$HONOR_REPO_INSTALL_DIR"
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/lib/common.sh"

[[ -d "$HONOR_UPSTREAM_DIR/.git" ]] || die "prepared HONOR source missing; run preflight.sh first"
grep -q '^\[board M1230\]$' "$HONOR_UPSTREAM_DIR/devices/zqc-p.conf" || die "M1230 adaptation missing from HONOR source"

install -d -m755 "$HONOR_STATE_DIR"
touch "$HONOR_LOG"
chmod 600 "$HONOR_LOG"
exec > >(tee -a "$HONOR_LOG") 2>&1
exec 9>"$HONOR_STATE_DIR/install.lock"
flock -n 9 || die "another HONOR install process is running"

TARGET_USER="${SUDO_USER:-}"
[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || die "run sudo from your normal Omarchy account"

cat > /etc/honor-m1230.conf <<EOFCONF
HONOR_USER=$TARGET_USER
EOFCONF
chmod 644 /etc/honor-m1230.conf

if (( ! YES )); then
    cat <<'CONFIRM'
This installs only post-reboot runtime fixes:
- HID-BPF micmute + touchpad edge
- private EgisTec SDCP libfprint
- keyboard-backlight module/service
- DSC service
- boot health-check timer

It will NOT call pacman, mkinitcpio, limine-mkinitcpio or reboot.
Type INSTALL to continue:
CONFIRM
    read -r answer
    [[ "$answer" == INSTALL ]] || die "cancelled"
fi

verify_boot_state() {
    log "verifying the manually staged boot state"

    local klog
    klog="$(journalctl -k -b --no-pager 2>/dev/null || true)"

    grep -q 'Table Upgrade: override.*I2C_DEVT' <<<"$klog"         || die "ACPI I2C_DEVT override is not active; complete the manual mkinitcpio/Limine stage and reboot first"

    ! grep -qE 'AE_AML_INTERNAL.*I2C_DEVT|I2C_DEVT.*AE_AML_INTERNAL' <<<"$klog"         || die "AE_AML_INTERNAL returned after the ACPI override"

    ! grep -qi 'locked down.*table override' <<<"$klog"         || die "kernel lockdown rejected the ACPI override"

    compgen -G '/sys/bus/hid/devices/*2808:5662*' >/dev/null         || die "touchscreen 2808:5662 missing"

    if ! compgen -G '/sys/bus/hid/devices/*27C6:0F9A*' >/dev/null        && ! compgen -G '/sys/bus/hid/devices/*27c6:0f9a*' >/dev/null; then
        die "touchpad 27c6:0f9a missing"
    fi

    [[ "$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)" == 1 ]]         || die "xe.enable_psr=1 is not active"
}

install_hid_bpf() {
    log "installing touchscreen micmute HID-BPF"
    retry 3 5 env ALLOW_UNVERIFIED=1         bash "$HONOR_UPSTREAM_DIR/patch/micmute/install.sh"         || die "micmute HID-BPF install failed"

    log "installing touchpad left-edge brightness HID-BPF"
    retry 3 5 env ALLOW_UNVERIFIED=1         bash "$HONOR_UPSTREAM_DIR/patch/touchpad-edge/install.sh"         || die "touchpad-edge HID-BPF install failed"

    [[ -f /etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o ]]         || die "micmute BPF object missing"
    [[ -f /etc/udev-hid-bpf/honor-tops0102-edge.bpf.o ]]         || die "touchpad-edge BPF object missing"
}

install_fingerprint_driver() {
    log "installing private EgisTec SDCP libfprint"
    lsusb -d "$HONOR_FINGERPRINT_ID" >/dev/null 2>&1         || die "fingerprint reader $HONOR_FINGERPRINT_ID missing"

    retry 3 5 env ALLOW_UNVERIFIED=1         bash "$HONOR_UPSTREAM_DIR/patch/fingerprint/install.sh"         || die "EgisTec SDCP libfprint install failed"

    ldconfig
    systemctl restart fprintd.service 2>/dev/null || true

    [[ -d /opt/honor-libfprint-sdcp ]]         || die "/opt/honor-libfprint-sdcp missing"
    ldconfig -p | grep -q '/opt/honor-libfprint-sdcp'         || die "private SDCP libfprint is not first-class in loader cache"
}

install_keyboard_backlight() {
    log "installing M1230 keyboard-backlight LED driver"
    bash "$REPO_ROOT/honor-zqcp-kbdlight/install-omarchy.sh"
    systemctl is-active --quiet honor-zqcp-kbdlight.service         || die "keyboard-backlight service not active"
    [[ -d /sys/class/leds/honor::kbd_backlight ]]         || die "honor::kbd_backlight missing"
}

install_dsc() {
    log "installing DSC force service"
    install -d -m755 /usr/local/lib/honor
    install -m755 "$REPO_ROOT/scripts/force-dsc.sh" /usr/local/lib/honor/force-dsc.sh
    install -m644 "$REPO_ROOT/systemd/honor-force-dsc.service"         /etc/systemd/system/honor-force-dsc.service

    systemctl daemon-reload
    systemctl enable honor-force-dsc.service >/dev/null
    systemctl restart honor-force-dsc.service

    local file
    file="$(find /sys/kernel/debug/dri -path '*/eDP-*/i915_dsc_fec_support' -print -quit 2>/dev/null || true)"
    [[ -n "$file" ]] || die "DSC debugfs file disappeared"
    grep -q 'DSC_Sink_Support: yes' "$file" || die "DSC sink support is no"
    grep -q 'Force_DSC_Enable: yes' "$file" || die "DSC force flag did not stick"
}

install_health_check() {
    log "installing boot health check"
    install -d -m755 /usr/local/lib/honor
    install -m755 "$REPO_ROOT/scripts/health-check.sh" /usr/local/lib/honor/health-check.sh
    install -m644 "$REPO_ROOT/systemd/honor-health-check.service"         /etc/systemd/system/honor-health-check.service
    install -m644 "$REPO_ROOT/systemd/honor-health-check.timer"         /etc/systemd/system/honor-health-check.timer
    systemctl daemon-reload
    systemctl enable --now honor-health-check.timer >/dev/null
}

verify_boot_state
install_hid_bpf
install_fingerprint_driver
install_keyboard_backlight
install_dsc
install_health_check

log "running current-boot health check"
HONOR_USER="$TARGET_USER" /usr/local/lib/honor/health-check.sh --pre-reboot

printf 'installed=%s\nkernel=%s\nuser=%s\n'     "$(date --iso-8601=seconds)" "$(uname -r)" "$TARGET_USER"     > "$HONOR_STATE_DIR/install-complete"
chmod 600 "$HONOR_STATE_DIR/install-complete"

echo
log "RUNTIME INSTALL: OK"
echo
echo "Keyboard backlight is integrated with Omarchy:"
echo "  omarchy-brightness-keyboard cycle"
echo
echo "Configure fingerprint through Omarchy's own security integration:"
echo "  omarchy-setup-security-fingerprint"
echo
echo "When you are ready, do the FINAL persistence reboot yourself:"
echo "  systemctl reboot"
echo
echo "Then wait ~60 seconds and check:"
echo "  cat /var/lib/honor/health-last.txt"
echo
echo "Expected final line: RESULT: OK"
