#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

require_root
assert_omarchy
assert_m1230
assert_dependencies_present
assert_lockdown_off
assert_kernel_build_tree
require_cmds git python3 md5sum dd tr awk find mountpoint

if [[ -e "$HONOR_UPSTREAM_DIR" && ! -d "$HONOR_UPSTREAM_DIR/.git" ]]; then
    die "$HONOR_UPSTREAM_DIR exists but is not the expected git repository"
fi

if [[ -d "$HONOR_UPSTREAM_DIR/.git" ]]; then
    remote="$(git -C "$HONOR_UPSTREAM_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$remote" == "$HONOR_UPSTREAM_URL" ]] || die "unexpected origin in $HONOR_UPSTREAM_DIR: $remote"
    git -C "$HONOR_UPSTREAM_DIR" reset --hard
    git -C "$HONOR_UPSTREAM_DIR" clean -fdx
else
    install -d -m755 "$(dirname "$HONOR_UPSTREAM_DIR")"
    retry 3 10 git clone --no-checkout "$HONOR_UPSTREAM_URL" "$HONOR_UPSTREAM_DIR" || die "HONOR source clone failed"
fi

retry 3 10 git -C "$HONOR_UPSTREAM_DIR" fetch --prune origin || die "HONOR source fetch failed"
git -C "$HONOR_UPSTREAM_DIR" checkout --detach "$HONOR_UPSTREAM_COMMIT"
[[ "$(git -C "$HONOR_UPSTREAM_DIR" rev-parse 'HEAD^{tree}')" == "$HONOR_UPSTREAM_TREE" ]] || die "pinned HONOR source tree hash mismatch"
python3 "$ROOT/scripts/prepare-honor-upstream.py" "$HONOR_UPSTREAM_DIR"

live=""
for f in /sys/firmware/acpi/tables/SSDT*; do
    [[ -e "$f" ]] || continue
    oem="$(dd if="$f" bs=1 skip=16 count=8 status=none 2>/dev/null | tr -d '\0 ' || true)"
    if [[ "$oem" == "I2C_DEVT" ]]; then
        live="$f"
        break
    fi
done
[[ -n "$live" ]] || die "live I2C_DEVT ACPI table not found"

stock="$HONOR_UPSTREAM_DIR/dump/acpi/zqc-p/SSDT27_orig.aml"
patched="$HONOR_UPSTREAM_DIR/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml"
live_md5="$(md5sum "$live" | awk '{print $1}')"
stock_md5="$(md5sum "$stock" | awk '{print $1}')"
patched_md5="$(md5sum "$patched" | awk '{print $1}')"

[[ "$stock_md5" == "$HONOR_ACPI_STOCK_MD5" ]] || die "stock ACPI reference changed: $stock_md5"
[[ "$patched_md5" == "$HONOR_ACPI_PATCHED_MD5" ]] || die "patched ACPI reference changed: $patched_md5"
[[ "$live_md5" == "$stock_md5" ]] || die "live I2C_DEVT differs from the audited stock table: $live_md5"

DSDT=/sys/firmware/acpi/tables/DSDT
for symbol in KBBL GKBM SKBM; do
    grep -aq "$symbol" "$DSDT" || die "DSDT symbol $symbol missing; refusing keyboard EC driver"
done

[[ -r /sys/kernel/btf/vmlinux ]] || die "kernel BTF missing"
KBUILD="/usr/lib/modules/$(uname -r)/build"
for h in hid_bpf.h hid_bpf_helpers.h hid_report_descriptor_helpers.h; do
    [[ -f "$KBUILD/drivers/hid/bpf/progs/$h" ]] || die "matching linux-omarchy-headers is missing $h"
done

mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
DSC_FILE="$(find /sys/kernel/debug/dri -path '*/eDP-*/i915_dsc_fec_support' -print -quit 2>/dev/null || true)"
[[ -n "$DSC_FILE" ]] || die "current linux-omarchy kernel does not expose i915_dsc_fec_support"
grep -q 'DSC_Sink_Support: yes' "$DSC_FILE" || die "internal panel does not report DSC support"

echo
log "PREFLIGHT: OK"
printf 'Omarchy       : %s\n' "$(omarchy-version 2>/dev/null || echo installed)"
printf 'Kernel        : %s\n' "$(uname -r)"
printf 'I2C_DEVT stock: %s\n' "$live_md5"
printf 'Patched AML   : %s\n' "$patched_md5"
printf 'DSC debugfs   : %s\n' "$DSC_FILE"
echo
echo "No boot configuration was changed."
echo "Continue with the MANUAL ACPI + Limine block in docs/INSTALL.md."
