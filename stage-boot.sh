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
require_cmds limine-mkinitcpio install grep sed md5sum

[[ -d "$HONOR_UPSTREAM_DIR/.git" ]] \
    || die "prepared HONOR source missing; run sudo ./preflight.sh --yes first"
grep -q '^\[board M1230\]$' "$HONOR_UPSTREAM_DIR/devices/zqc-p.conf" \
    || die "M1230 adaptation missing; rerun preflight"

acpi_state="$(assert_acpi_known)"
log "live ACPI state: $acpi_state"

# Arch's current mkinitcpio ships an official acpi_override install hook. It
# uses add_file_early(), which is exactly what Linux ACPI table upgrades need.
[[ -f /usr/lib/initcpio/install/acpi_override ]] \
    || die "mkinitcpio acpi_override hook is missing: /usr/lib/initcpio/install/acpi_override"

patched="$HONOR_UPSTREAM_DIR/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml"
[[ "$(md5sum "$patched" | awk '{print $1}')" == "$HONOR_ACPI_PATCHED_MD5" ]] \
    || die "patched ACPI payload hash mismatch"

log "installing the audited ACPI table into mkinitcpio's override directory"
install -d -m755 "$HONOR_ACPI_DIR"
install -m644 "$patched" "$HONOR_ACPI_FILE"

log "adding the mkinitcpio ACPI hook through an /etc drop-in"
install -d -m755 "$(dirname "$HONOR_MKINITCPIO_DROPIN")"
cat > "$HONOR_MKINITCPIO_DROPIN" <<'EOF'
# HONOR ZQC-P/M1230: put /etc/initcpio/acpi_override/*.aml in the early,
# uncompressed CPIO using mkinitcpio's official acpi_override hook.
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
