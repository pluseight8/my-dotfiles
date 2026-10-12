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
Usage: sudo ./preflight.sh [--yes]

Read-only validation of the Omarchy host and exact HONOR ZQC-P/M1230 hardware.
It also prepares the pinned upstream HONOR source under /var/opt.

It does NOT change Limine, mkinitcpio, the running kernel or reboot the machine.
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
require_cmds git python3 md5sum dd od awk grep find journalctl

if (( ! YES )); then
    cat <<'CONFIRM'
This will:
- verify the exact HONOR ZQC-P/M1230 identity;
- verify current Omarchy/kernel prerequisites;
- verify the live ACPI table against the audited reference;
- clone the HONOR support repository at one pinned commit;
- add only the M1230 Tier-A profile/recipes locally.

It will NOT modify the boot configuration and will NOT reboot.
Type CHECK to continue:
CONFIRM
    read -r answer
    [[ "$answer" == CHECK ]] || die "cancelled"
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
        retry 3 10 git clone --no-checkout "$HONOR_UPSTREAM_URL" "$dir" \
            || die "HONOR source clone failed"
    fi

    retry 3 10 git -C "$dir" fetch --prune origin \
        || die "HONOR source fetch failed"
    git -C "$dir" checkout --detach "$HONOR_UPSTREAM_COMMIT"

    [[ "$(git -C "$dir" rev-parse 'HEAD^{tree}')" == "$HONOR_UPSTREAM_TREE" ]] \
        || die "pinned HONOR source tree hash mismatch"

    python3 "$ROOT/scripts/prepare-honor-upstream.py" "$dir"
}

log "Omarchy: $(omarchy-version)"
log "kernel: $(uname -r) ($(running_kernel_pkgbase))"
log "preparing pinned HONOR support source"
prepare_upstream

acpi_state="$(assert_acpi_known)"
log "ACPI I2C_DEVT: $acpi_state ($(current_i2c_hash))"

KLOG="$(journalctl -k -b --no-pager 2>/dev/null || true)"
if grep -q 'CPU pipe .* FIFO underrun' <<<"$KLOG"; then
    warn "the current boot logged a display FIFO underrun"
else
    log "no display FIFO underrun found in the current boot log"
fi

echo
log "PREFLIGHT: OK"
echo "No boot configuration was changed."
echo
echo "Next:"
echo "  sudo ./stage-boot.sh"
