#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

require_root
assert_omarchy
assert_m1230
assert_omarchy_kernel
assert_lockdown_off
assert_host_dependencies_present
assert_matching_headers
require_cmds limine-mkinitcpio lsinitcpio install grep sed md5sum

[[ -d "$HONOR_UPSTREAM_DIR/.git" ]] \
    || die "prepared HONOR source missing; run sudo ./preflight.sh --yes first"
grep -q '^\[board M1230\]$' "$HONOR_UPSTREAM_DIR/devices/zqc-p.conf" \
    || die "M1230 adaptation missing; rerun preflight"

acpi_state="$(assert_acpi_known)"
log "live ACPI state: $acpi_state"

patched="$HONOR_UPSTREAM_DIR/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml"
hook_src="$HONOR_UPSTREAM_DIR/patch/acpi-override/acpi_override.install"
[[ "$(md5sum "$patched" | awk '{print $1}')" == "$HONOR_ACPI_PATCHED_MD5" ]] \
    || die "patched ACPI payload hash mismatch"
[[ -f "$hook_src" ]] || die "pinned upstream ACPI mkinitcpio hook is missing: $hook_src"

# Use the exact early-CPIO mechanism proven by the HONOR project. The hook is
# installed in /etc so it overrides any packaged hook with the same name.
log "installing the audited ACPI table and pinned early-CPIO hook"
install -d -m755 "$HONOR_ACPI_DIR" "$(dirname "$HONOR_ACPI_HOOK")"
install -m644 "$patched" "$HONOR_ACPI_FILE"
install -m755 "$hook_src" "$HONOR_ACPI_HOOK"

# Clean up the first Omarchy adaptation layout if it exists. Those exact files
# were created by this repository and are no longer used.
rm -f /etc/initcpio/acpi_override/SSDT27_TPD0.aml
rmdir /etc/initcpio/acpi_override 2>/dev/null || true
rm -f /etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf

log "adding the mkinitcpio ACPI hook through a last-sorting /etc drop-in"
install -d -m755 "$(dirname "$HONOR_MKINITCPIO_DROPIN")"
cat > "$HONOR_MKINITCPIO_DROPIN" <<'EOF'
# HONOR ZQC-P/M1230: append the pinned early-CPIO ACPI override hook after
# Omarchy's own hook policy has been sourced.
HOOKS+=(acpi_override)
EOF
chmod 644 "$HONOR_MKINITCPIO_DROPIN"

# Never rewrite Omarchy's /etc/default/limine. Its own hardware features use
# /etc/limine-entry-tool.d, so this adaptation follows the same interface.
conflict="$({
    grep -HsE '(xe|i915)\.enable_psr=' /etc/default/limine 2>/dev/null || true
    find /etc/limine-entry-tool.d -maxdepth 1 -type f \
        ! -path "$HONOR_LIMINE_DROPIN" -print0 2>/dev/null \
        | xargs -0r grep -HsE '(xe|i915)\.enable_psr=' 2>/dev/null || true
} | head -1)"
[[ -z "$conflict" ]] || die "another PSR setting already exists: $conflict
Remove or reconcile it manually before continuing."

log "adding xe.enable_psr=1 through an Omarchy Limine drop-in"
install -d -m755 "$(dirname "$HONOR_LIMINE_DROPIN")"
cat > "$HONOR_LIMINE_DROPIN" <<'EOF'
# HONOR ZQC-P/M1230 OLED: keep Panel Self Refresh at PSR1.
KERNEL_CMDLINE[default]+=" xe.enable_psr=1"
EOF
chmod 644 "$HONOR_LIMINE_DROPIN"

log "rebuilding Omarchy's Limine/mkinitcpio boot images"
limine-mkinitcpio

esp="$(sed -n 's/^ESP_PATH=["'\'']\?\([^"'\'']*\).*/\1/p' /etc/default/limine 2>/dev/null | tail -1)"
esp="${esp:-/boot}"

# limine-mkinitcpio currently warns and continues if one kernel build fails.
# Verify the image that will actually be booted before telling the user to reboot.
machine_id="$(cat /etc/machine-id)"
kernel_name="$(running_kernel_pkgbase)"
image_ok=0
verify_root="$(mktemp -d)"
trap 'rm -rf "$verify_root"' EXIT

# limine-entry-tool prefixes UKIs with its configured UKI prefix. Omarchy's
# current prefix is "omarchy", so linux-omarchy becomes
# /boot/EFI/Linux/omarchy_linux-omarchy.efi. Do not assume one prefix here:
# discover readable candidates and verify their actual early CPIO contents.
declare -a images=(
    "$esp/$machine_id/$kernel_name/initramfs"
    "$esp/EFI/Linux/$kernel_name.efi"
)
while IFS= read -r -d '' uki; do
    images+=("$uki")
done < <(find "$esp/EFI/Linux" -maxdepth 1 -type f -name "*_${kernel_name}.efi" -print0 2>/dev/null)

for image in "${images[@]}"; do
    [[ -r "$image" ]] || continue

    rm -rf "${verify_root:?}"/*
    if (cd "$verify_root" && lsinitcpio --early -x "$image" >/dev/null 2>&1); then
        extracted="$verify_root/kernel/firmware/acpi/SSDT27_TPD0.aml"
        if [[ -f "$extracted" ]]; then
            extracted_hash="$(md5sum "$extracted" | awk '{print $1}')"
            if [[ "$extracted_hash" == "$HONOR_ACPI_PATCHED_MD5" ]]; then
                log "verified audited ACPI override inside boot image: $image"
                image_ok=1
                break
            fi
            warn "ACPI override exists in $image but hash is $extracted_hash (expected $HONOR_ACPI_PATCHED_MD5)"
        else
            warn "no SSDT27_TPD0.aml in early CPIO of $image"
            lsinitcpio --early "$image" 2>/dev/null \
                | grep -E '(^|/)(kernel/firmware/acpi|SSDT|early_cpio)' >&2 || true
        fi
    else
        warn "could not extract early CPIO from $image"
    fi
done
(( image_ok )) || die "rebuilt Limine image does not contain the audited ACPI override; refusing to reboot into an unpatched image"
if [[ -r "$esp/limine.conf" ]]; then
    grep -q 'xe.enable_psr=1' "$esp/limine.conf" \
        || die "limine-mkinitcpio returned, but $esp/limine.conf does not contain xe.enable_psr=1"
    log "verified xe.enable_psr=1 in $esp/limine.conf"
else
    warn "$esp/limine.conf is not readable; the next boot remains the definitive check"
fi

install -d -m755 "$HONOR_STATE_DIR"
printf 'staged=%s\nkernel=%s\nacpi_before=%s\n' \
    "$(date --iso-8601=seconds)" "$(uname -r)" "$acpi_state" \
    > "$HONOR_STATE_DIR/boot-stage.env"
chmod 600 "$HONOR_STATE_DIR/boot-stage.env"

echo
log "BOOT STAGE: OK"
echo
echo "Nothing rebooted automatically."
echo "Reboot yourself now:"
echo "  systemctl reboot"
echo
echo "After logging back in:"
echo "  cd <your my-dotfiles checkout>"
echo "  sudo ./install.sh --yes"
