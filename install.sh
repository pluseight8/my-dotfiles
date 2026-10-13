#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

YES=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) YES=1 ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./install.sh [--yes]

POST-REBOOT runtime installer for HONOR ZQC-P/M1230 on Omarchy.

It refuses to run until the staged ACPI override and xe.enable_psr=1 are
actually active in the current boot. It never reboots the machine.
HELP
            exit 0
            ;;
        *) die "unknown argument: $arg" ;;
    esac
done

require_root
assert_omarchy
assert_m1230
assert_omarchy_kernel
assert_lockdown_off
assert_host_dependencies_present
assert_matching_headers
assert_hid_bpf_kernel_support
require_cmds git python3 systemctl md5sum install find awk grep lsusb ldconfig journalctl runuser jq

[[ -d "$HONOR_UPSTREAM_DIR/.git" ]] \
    || die "prepared HONOR source missing; run preflight.sh and stage-boot.sh first"
grep -q '^\[board M1230\]$' "$HONOR_UPSTREAM_DIR/devices/zqc-p.conf" \
    || die "M1230 adaptation missing from the pinned HONOR source"

TARGET_USER="${SUDO_USER:-}"
[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] \
    || die "run sudo from your normal Omarchy desktop account"

install -d -m755 "$HONOR_STATE_DIR"
touch "$HONOR_LOG"
chmod 600 "$HONOR_LOG"
exec > >(tee -a "$HONOR_LOG") 2>&1
exec 9>"$HONOR_STATE_DIR/install.lock"
flock -n 9 || die "another HONOR M1230 installation is already running"

cat > /etc/honor-m1230.conf <<EOF
HONOR_USER=$TARGET_USER
HONOR_ACPI_PATCHED_MD5=$HONOR_ACPI_PATCHED_MD5
EOF
chmod 644 /etc/honor-m1230.conf

verify_boot_stage() {
    log "verifying the rebooted boot stage"

    local klog live_hash psr
    klog="$(journalctl -k -b --no-pager 2>/dev/null || true)"

    # The live ACPI table bytes are the authoritative proof. Kernel log wording
    # changes between kernel releases, so a missing informational message must
    # not turn a successfully loaded override into a false negative.
    live_hash="$(current_i2c_hash)" || die "live I2C_DEVT not found"
    [[ "$live_hash" == "$HONOR_ACPI_PATCHED_MD5" ]] \
        || die "current I2C_DEVT is not the audited patched table: $live_hash. Run stage-boot.sh, reboot, then retry."

    ! grep -qE 'AE_AML_INTERNAL.*I2C_DEVT|I2C_DEVT.*AE_AML_INTERNAL' <<<"$klog" \
        || die "I2C_DEVT returned AE_AML_INTERNAL after the override"
    ! grep -qi 'locked down.*table override' <<<"$klog" \
        || die "kernel lockdown rejected the ACPI override"

    if grep -qiE 'Table Upgrade:.*I2C_DEVT|ACPI:.*I2C_DEVT.*override' <<<"$klog"; then
        log "kernel log also confirms the I2C_DEVT override"
    else
        warn "kernel log did not use the expected override wording; live I2C_DEVT hash is authoritative and matches"
    fi

    compgen -G '/sys/bus/hid/devices/*2808:5662*' >/dev/null \
        || die "touchscreen 2808:5662 is missing after the ACPI override"
    { compgen -G '/sys/bus/hid/devices/*27C6:0F9A*' >/dev/null \
      || compgen -G '/sys/bus/hid/devices/*27c6:0f9a*' >/dev/null; } \
        || die "touchpad 27c6:0f9a is missing after the ACPI override"

    psr="$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)"
    [[ "$psr" == 1 ]] || die "xe.enable_psr is '${psr:-missing}', expected 1"

    log "boot stage is active"
}

if (( ! YES )); then
    cat <<'CONFIRM'
This installs the post-reboot M1230 runtime fixes:
- touchscreen mic-mute HID-BPF
- touchpad-edge HID-BPF
- EgisTec 1c7a:05aa SDCP fingerprint driver
- keyboard-backlight LED module/service
- DSC force service
- boot health-check timer

It does NOT replace xe.ko, does NOT edit Omarchy's /etc/default/limine and
does NOT reboot.
Type INSTALL to continue:
CONFIRM
    read -r answer
    [[ "$answer" == INSTALL ]] || die "cancelled"
fi

verify_boot_stage

log "installing touchscreen mic-mute HID-BPF"
retry 2 10 env ALLOW_UNVERIFIED=1 \
    bash "$HONOR_UPSTREAM_DIR/patch/micmute/install.sh" \
    || die "micmute HID-BPF install failed"

log "installing touchpad left-edge brightness HID-BPF"
retry 2 10 env ALLOW_UNVERIFIED=1 \
    bash "$HONOR_UPSTREAM_DIR/patch/touchpad-edge/install.sh" \
    || die "touchpad-edge HID-BPF install failed"

log "installing EgisTec 1c7a:05aa SDCP fingerprint support"
lsusb -d "$HONOR_FINGERPRINT_ID" >/dev/null 2>&1 \
    || die "fingerprint reader $HONOR_FINGERPRINT_ID is not on the USB bus"
retry 2 10 env ALLOW_UNVERIFIED=1 \
    bash "$HONOR_UPSTREAM_DIR/patch/fingerprint/install.sh" \
    || die "fingerprint support install failed"
ldconfig
systemctl try-restart fprintd.service >/dev/null 2>&1 || true

log "installing M1230 keyboard backlight support"
bash "$ROOT/honor-zqcp-kbdlight/install-omarchy.sh"

log "installing DSC force service"
install -d -m755 /usr/local/lib/honor
install -m755 "$ROOT/scripts/force-dsc.sh" /usr/local/lib/honor/force-dsc.sh
install -m644 "$ROOT/systemd/honor-force-dsc.service" /etc/systemd/system/honor-force-dsc.service
systemctl daemon-reload
systemctl enable honor-force-dsc.service >/dev/null
systemctl restart honor-force-dsc.service
systemctl is-active --quiet honor-force-dsc.service \
    || die "honor-force-dsc.service did not become active"
log "DSC force accepted; if DSC_Enabled is still 'no', the next modeset/reboot will activate it"

log "installing post-login DSC modeset helper"
install -m755 "$ROOT/scripts/dsc-modeset-user.sh" /usr/local/lib/honor/dsc-modeset-user.sh
install -m644 "$ROOT/systemd/honor-dsc-modeset.service" /etc/systemd/user/honor-dsc-modeset.service

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
USER_UID="$(id -u "$TARGET_USER")"
USER_GROUP="$(id -gn "$TARGET_USER")"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || die "cannot resolve home for $TARGET_USER"
install -d -m755 -o "$TARGET_USER" -g "$USER_GROUP" "$USER_HOME/.config/systemd/user/graphical-session.target.wants"
ln -sfn /etc/systemd/user/honor-dsc-modeset.service     "$USER_HOME/.config/systemd/user/graphical-session.target.wants/honor-dsc-modeset.service"
chown -h "$TARGET_USER:$USER_GROUP"     "$USER_HOME/.config/systemd/user/graphical-session.target.wants/honor-dsc-modeset.service"

ALLOW_PENDING_DSC=1
if [[ -S "/run/user/$USER_UID/bus" ]]; then
    USER_SYSTEMCTL=(runuser -u "$TARGET_USER" -- env         XDG_RUNTIME_DIR="/run/user/$USER_UID"         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"         systemctl --user)
    "${USER_SYSTEMCTL[@]}" daemon-reload
    if "${USER_SYSTEMCTL[@]}" restart honor-dsc-modeset.service; then
        sleep 2
        ALLOW_PENDING_DSC=0
        log "post-login DSC modeset helper completed in the current session"
    else
        warn "live DSC modeset helper could not run; it is enabled for the next graphical login"
    fi
else
    warn "user D-Bus is not available; DSC modeset helper is enabled for the next graphical login"
fi

log "installing boot health check"
install -m755 "$ROOT/scripts/health-check.sh" /usr/local/lib/honor/health-check.sh
install -m644 "$ROOT/systemd/honor-health-check.service" /etc/systemd/system/honor-health-check.service
install -m644 "$ROOT/systemd/honor-health-check.timer" /etc/systemd/system/honor-health-check.timer
systemctl daemon-reload
systemctl enable --now honor-health-check.timer >/dev/null

log "running the health check now"
if ! HONOR_ALLOW_PENDING_DSC="$ALLOW_PENDING_DSC" \
    HONOR_USER="$TARGET_USER" \
    HONOR_ACPI_PATCHED_MD5="$HONOR_ACPI_PATCHED_MD5" \
    /usr/local/lib/honor/health-check.sh; then
    die "health check failed; see /var/lib/honor/health-last.txt"
fi

printf 'installed=%s\nkernel=%s\nuser=%s\nomarchy=%s\n' \
    "$(date --iso-8601=seconds)" "$(uname -r)" "$TARGET_USER" "$(omarchy-version)" \
    > "$HONOR_STATE_DIR/runtime-install-complete"
chmod 600 "$HONOR_STATE_DIR/runtime-install-complete"

echo
log "RUNTIME INSTALL: OK"
echo
echo "No reboot was performed."
echo
echo "Now, as your NORMAL user, let Omarchy enroll the finger and configure"
echo "sudo / polkit / the Omarchy lock screen:"
echo
echo "  omarchy-setup-security-fingerprint"
echo
echo "After any Omarchy/kernel update, wait about a minute after reboot and run:"
echo
echo "  cat /var/lib/honor/health-last.txt"
