#!/usr/bin/bash
set -euo pipefail

ORIGINAL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ORIGINAL_ROOT/scripts/lib/common.sh"

YES=0
RESUME=0
NO_REBOOT=0
REPAIR=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) YES=1 ;;
        --resume) RESUME=1 ;;
        --no-reboot) NO_REBOOT=1 ;;
        --repair) REPAIR=1 ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./install.sh [--yes] [--no-reboot] [--repair]

The first run validates the exact HONOR ZQC-P/M1230 hardware, installs the ACPI
and PSR settings, registers a resume service, and reboots. The resume service
finishes the HID-BPF, fingerprint, keyboard-backlight, DSC and health-check
setup automatically across the required reboots.
HELP
            exit 0
            ;;
        *) die "unknown argument: $arg" ;;
    esac
done

require_root
assert_bazzite
assert_m1230
require_cmds git python3 rpm-ostree systemctl md5sum install find awk grep flock

if [[ "$ORIGINAL_ROOT" != "$HONOR_REPO_INSTALL_DIR" ]]; then
    log "copying installer payload to $HONOR_REPO_INSTALL_DIR"
    safe_rm_tree "$HONOR_REPO_INSTALL_DIR"
    install -d -m755 "$(dirname "$HONOR_REPO_INSTALL_DIR")"
    cp -a "$ORIGINAL_ROOT" "$HONOR_REPO_INSTALL_DIR"
    exec /usr/bin/bash "$HONOR_REPO_INSTALL_DIR/install.sh" "$@"
fi

REPO_ROOT="$HONOR_REPO_INSTALL_DIR"
source "$REPO_ROOT/scripts/lib/common.sh"

install -d -m755 "$HONOR_STATE_DIR"
touch "$HONOR_LOG"
chmod 600 "$HONOR_LOG"
exec > >(tee -a "$HONOR_LOG") 2>&1
exec 9>"$HONOR_STATE_DIR/install.lock"
flock -n 9 || die "another HONOR M1230 installation process is already running"

TARGET_USER="$(state_get TARGET_USER 2>/dev/null || true)"
if [[ -z "$TARGET_USER" ]]; then
    TARGET_USER="${SUDO_USER:-}"
    [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || die "run sudo from your normal desktop account"
    state_set TARGET_USER "$TARGET_USER"
fi

cat > /etc/honor-m1230.conf <<EOFCONF
HONOR_USER=$TARGET_USER
EOFCONF
chmod 644 /etc/honor-m1230.conf

install_resume_service() {
    install -m644 "$REPO_ROOT/systemd/honor-m1230-resume.service" /etc/systemd/system/honor-m1230-resume.service
    systemctl daemon-reload
    systemctl enable honor-m1230-resume.service >/dev/null
}

reboot_or_stop() {
    if (( NO_REBOOT )); then
        warn "reboot required; resume service is enabled and will continue automatically after boot"
        exit 0
    fi
    log "rebooting; installation will resume automatically"
    sync
    systemctl reboot
    exit 0
}

prepare_upstream() {
    local dir="$HONOR_UPSTREAM_DIR"
    if [[ -e "$dir" && ! -f "$HONOR_STATE_DIR/source-managed" ]]; then
        die "$dir already exists and is not marked as managed by this installer; move it away first"
    fi

    if [[ ! -d "$dir/.git" ]]; then
        safe_rm_tree "$dir"
        log "cloning pinned HONOR support source"
        retry 3 10 git clone --no-checkout "$HONOR_UPSTREAM_URL" "$dir" || die "HONOR source clone failed"
    fi

    retry 3 10 git -C "$dir" fetch --prune origin || die "HONOR source fetch failed"
    git -C "$dir" reset --hard
    git -C "$dir" clean -fdx
    git -C "$dir" checkout --detach "$HONOR_UPSTREAM_COMMIT"
    [[ "$(git -C "$dir" rev-parse 'HEAD^{tree}')" == "$HONOR_UPSTREAM_TREE" ]] || die "pinned HONOR source tree hash mismatch"
    python3 "$REPO_ROOT/scripts/prepare-honor-upstream.py" "$dir"
    touch "$HONOR_STATE_DIR/source-managed"
}

find_live_i2c_devt() {
    local f oem
    for f in /sys/firmware/acpi/tables/SSDT*; do
        [[ -e "$f" ]] || continue
        oem="$(dd if="$f" bs=1 skip=16 count=8 status=none 2>/dev/null | tr -d '\0 ' || true)"
        if [[ "$oem" == "I2C_DEVT" ]]; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

stage1() {
    log "stage 1/3: preflight, pinned source, ACPI override and PSR1"
    assert_secure_boot_off
    assert_selinux_enforcing
    assert_kernel_build_tree
    assert_no_pending_deployment

    ostree admin pin 0 >/dev/null 2>&1 || warn "current deployment may already be pinned"
    prepare_upstream

    local live stock patched live_md5 stock_md5 patched_md5
    live="$(find_live_i2c_devt)" || die "live I2C_DEVT ACPI table not found"
    stock="$HONOR_UPSTREAM_DIR/dump/acpi/zqc-p/SSDT27_orig.aml"
    patched="$HONOR_UPSTREAM_DIR/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml"
    [[ -f "$stock" && -f "$patched" ]] || die "pinned ACPI reference files missing"

    live_md5="$(md5sum "$live" | awk '{print $1}')"
    stock_md5="$(md5sum "$stock" | awk '{print $1}')"
    patched_md5="$(md5sum "$patched" | awk '{print $1}')"

    [[ "$stock_md5" == "$HONOR_ACPI_STOCK_MD5" ]] || die "pinned stock ACPI hash changed: $stock_md5"
    [[ "$patched_md5" == "$HONOR_ACPI_PATCHED_MD5" ]] || die "pinned patched ACPI hash changed: $patched_md5"
    [[ "$live_md5" == "$stock_md5" ]] || die "live I2C_DEVT differs from audited reference: $live_md5"
    log "ACPI stock reference matches live firmware exactly"

    install -d -m755 /etc/honor-magicbook/acpi /etc/dracut.conf.d
    install -m644 "$patched" /etc/honor-magicbook/acpi/SSDT27_TPD0.aml
    cat > /etc/dracut.conf.d/90-honor-acpi.conf <<'DRACUT'
acpi_override="yes"
acpi_table_dir="/etc/honor-magicbook/acpi"
DRACUT

    rpm-ostree initramfs --enable

    local arg
    while read -r arg; do
        [[ "$arg" == xe.enable_psr=* && "$arg" != xe.enable_psr=1 ]] || continue
        rpm-ostree kargs --delete-if-present="$arg"
    done < <(rpm-ostree kargs | tr ' ' '\n')
    rpm-ostree kargs --append-if-missing="xe.enable_psr=1"

    install_resume_service
    state_set STAGE 2
    reboot_or_stop
}

verify_after_acpi_reboot() {
    log "verifying ACPI override, touch devices and PSR1"
    local klog
    klog="$(journalctl -k -b --no-pager 2>/dev/null || true)"
    grep -q 'Table Upgrade: override.*I2C_DEVT' <<<"$klog" || die "ACPI I2C_DEVT override is not active after reboot"
    ! grep -qE 'AE_AML_INTERNAL.*I2C_DEVT|I2C_DEVT.*AE_AML_INTERNAL' <<<"$klog" || die "AE_AML_INTERNAL returned after ACPI override"
    ! grep -qi 'locked down.*table override' <<<"$klog" || die "kernel lockdown rejected the ACPI override"

    compgen -G '/sys/bus/hid/devices/*2808:5662*' >/dev/null || die "touchscreen 2808:5662 missing"
    { compgen -G '/sys/bus/hid/devices/*27C6:0F9A*' >/dev/null || compgen -G '/sys/bus/hid/devices/*27c6:0f9a*' >/dev/null; } || die "touchpad 27c6:0f9a missing"
    [[ "$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)" == 1 ]] || die "xe.enable_psr is not 1"
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

    local dsc_file display_info
    dsc_file="$(find /sys/kernel/debug/dri -path '*/eDP-*/i915_dsc_fec_support' -print -quit 2>/dev/null || true)"
    [[ -n "$dsc_file" ]] || die "DSC debugfs file missing"
    grep -q 'Force_DSC_Enable: yes' "$dsc_file" || die "DSC force is not enabled"
    display_info="$(find /sys/kernel/debug/dri -name i915_display_info -print -quit 2>/dev/null || true)"
    [[ -n "$display_info" ]] || die "i915_display_info missing"
    grep -m1 -E 'pipe src=.*bpp=' "$display_info" | grep -q 'bpp=30' || die "display is not bpp=30"
    grep -m1 -E 'pipe src=.*bpp=' "$display_info" | grep -q 'dither=no' || die "display still uses dithering"
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

stage2() {
    log "stage 2/3: hardware fixes and services"
    assert_secure_boot_off
    assert_selinux_enforcing
    assert_kernel_build_tree
    verify_after_acpi_reboot
    install_hid_bpf
    install_fingerprint
    install_keyboard_backlight
    install_dsc
    install_health_check

    systemctl restart upower.service 2>/dev/null || true
    restart_powerdevil_for_user "$TARGET_USER"

    log "keeping build dependencies for future repairability (optional cleanup is documented)"

    state_set STAGE 3
    reboot_or_stop
}

stage3() {
    log "stage 3/3: final persistence audit after clean reboot"
    assert_secure_boot_off
    assert_selinux_enforcing
    sleep 10

    if ! HONOR_USER="$TARGET_USER" /usr/local/lib/honor/health-check.sh; then
        die "final health check failed; see /var/lib/honor/health-last.txt"
    fi

    systemctl disable honor-m1230-resume.service >/dev/null 2>&1 || true
    state_set STAGE "done"
    printf 'completed=%s\nkernel=%s\nuser=%s\n' \
        "$(date --iso-8601=seconds)" "$(uname -r)" "$TARGET_USER" \
        > "$HONOR_STATE_DIR/install-complete"

    notify_user "$TARGET_USER" "Bazzite hardware setup finished: RESULT OK"
    log "installation complete: RESULT OK"
    log "fingerprint enrollment, if not already done: fprintd-enroll -f right-index-finger"
}

if (( ! RESUME )); then
    if (( REPAIR )); then
        log "repair requested: re-running full fail-closed validation from stage 1"
        state_set STAGE 1
        rm -f "$HONOR_STATE_DIR/install-complete"
    fi
    complete="$(state_get STAGE 2>/dev/null || true)"
    if [[ "$complete" == "done" ]]; then
        log "installation is already complete; running health check"
        HONOR_USER="$TARGET_USER" /usr/local/lib/honor/health-check.sh
        exit $?
    fi

    if (( ! YES )); then
        cat <<EOFCONFIRM
This will modify the host Bazzite installation on the exact HONOR ZQC-P/M1230:
- local initramfs with the audited ACPI override
- xe.enable_psr=1 kernel argument
- HID-BPF touch fixes
- private fingerprint libfprint
- M1230 keyboard-backlight kernel module
- DSC systemd service
- automatic health checks

It will reboot automatically and resume by itself.
Type INSTALL to continue:
EOFCONFIRM
        read -r answer
        [[ "$answer" == INSTALL ]] || die "cancelled"
    fi
fi

stage="$(state_get STAGE 2>/dev/null || true)"
[[ -n "$stage" ]] || stage=1
case "$stage" in
    1) stage1 ;;
    2) stage2 ;;
    3) stage3 ;;
    done)
        HONOR_USER="$TARGET_USER" /usr/local/lib/honor/health-check.sh
        ;;
    *) die "invalid installer state: $stage" ;;
esac