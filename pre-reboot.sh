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
Usage: sudo ./pre-reboot.sh [--yes]

Stages only the HONOR changes that REQUIRE a reboot:
- audited ACPI I2C_DEVT override through local initramfs
- xe.enable_psr=1 kernel argument

It NEVER reboots the machine and NEVER installs RPM packages.
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
assert_no_pending_deployment
require_cmds git python3 rpm-ostree ostree md5sum install dd tr awk

if (( ! YES )); then
    cat <<'CONFIRM'
This stages the reboot-required HONOR M1230 changes:
- ACPI override in local initramfs
- xe.enable_psr=1 kernel argument

It will NOT reboot.
Type STAGE to continue:
CONFIRM
    read -r answer
    [[ "$answer" == STAGE ]] || die "cancelled"
fi

prepare_upstream() {
    local dir="$HONOR_UPSTREAM_DIR" remote

    if [[ -e "$dir" && ! -d "$dir/.git" ]]; then
        die "$dir exists but is not the expected git repository; move it away first"
    fi

    if [[ -d "$dir/.git" ]]; then
        remote="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
        [[ "$remote" == "$HONOR_UPSTREAM_URL" ]] || die "unexpected origin in $dir: $remote"
        git -C "$dir" reset --hard
        git -C "$dir" clean -fdx
    else
        install -d -m755 "$(dirname "$dir")"
        retry 3 10 git clone --no-checkout "$HONOR_UPSTREAM_URL" "$dir" || die "HONOR source clone failed"
    fi

    retry 3 10 git -C "$dir" fetch --prune origin || die "HONOR source fetch failed"
    git -C "$dir" checkout --detach "$HONOR_UPSTREAM_COMMIT"
    [[ "$(git -C "$dir" rev-parse 'HEAD^{tree}')" == "$HONOR_UPSTREAM_TREE" ]] || die "pinned HONOR source tree hash mismatch"
    python3 "$ROOT/scripts/prepare-honor-upstream.py" "$dir"
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

log "pinning current deployment as an emergency rollback point"
ostree admin pin 0 >/dev/null 2>&1 || warn "current deployment may already be pinned"

log "preparing pinned HONOR support source"
prepare_upstream

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

log "ACPI live table matches audited stock reference exactly"
install -d -m755 /etc/honor-magicbook/acpi /etc/dracut.conf.d "$HONOR_STATE_DIR"
install -m644 "$patched" /etc/honor-magicbook/acpi/SSDT27_TPD0.aml
cat > /etc/dracut.conf.d/90-honor-acpi.conf <<'DRACUT'
acpi_override="yes"
acpi_table_dir="/etc/honor-magicbook/acpi"
DRACUT

log "enabling local initramfs so the ACPI override is included in the next deployment"
rpm-ostree initramfs --enable

log "staging xe.enable_psr=1"
while read -r arg; do
    [[ "$arg" == xe.enable_psr=* && "$arg" != xe.enable_psr=1 ]] || continue
    rpm-ostree kargs --delete-if-present="$arg"
done < <(rpm-ostree kargs | tr ' ' '\n')
rpm-ostree kargs --append-if-missing="xe.enable_psr=1"

printf 'staged=%s\nstock_md5=%s\npatched_md5=%s\n' \
    "$(date --iso-8601=seconds)" "$stock_md5" "$patched_md5" \
    > "$HONOR_STATE_DIR/pre-reboot-staged"
chmod 600 "$HONOR_STATE_DIR/pre-reboot-staged"

echo
log "PRE-REBOOT STAGING: OK"
echo "Nothing has rebooted automatically."
echo
echo "Inspect the staged deployment yourself:"
echo "  rpm-ostree status"
echo
echo "If it looks correct, reboot yourself:"
echo "  systemctl reboot"
echo
echo "After login:"
echo "  cd $HONOR_REPO_INSTALL_DIR"
echo "  sudo ./install.sh --yes"
