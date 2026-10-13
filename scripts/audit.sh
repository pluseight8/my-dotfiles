#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=1; }

check_present() {
    local pattern="$1" file="$2" label="$3"
    if grep -qE "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label"
    fi
}

check_absent_files() {
    local pattern="$1" label="$2"
    shift 2
    if grep -nHE "$pattern" "$@" >/dev/null 2>&1; then
        fail "$label"
        grep -nHE "$pattern" "$@" >&2 || true
    else
        pass "$label"
    fi
}

# Syntax ----------------------------------------------------------------------
while IFS= read -r -d '' f; do
    if bash -n "$f"; then
        pass "bash -n ${f#$ROOT/}"
    else
        fail "bash syntax ${f#$ROOT/}"
    fi
done < <(find "$ROOT" -type f -name '*.sh' -print0)

if python3 -m py_compile "$ROOT/scripts/prepare-honor-upstream.py"; then
    pass "python syntax prepare-honor-upstream.py"
else
    fail "python syntax prepare-honor-upstream.py"
fi
rm -rf "$ROOT/scripts/__pycache__"

# Git executable bits: several bring-up failures were just mode regressions. --
for f in     setup.sh     preflight.sh     stage-boot.sh     install.sh     scripts/audit.sh     scripts/diagnose-dsc.sh     scripts/diagnose-dsc-session.sh     scripts/dsc-modeset-user.sh     scripts/force-dsc.sh     scripts/health-check.sh     scripts/resume-runtime.sh     honor-zqcp-kbdlight/install-omarchy.sh; do
    mode="$(git -C "$ROOT" ls-files -s -- "$f" | awk '{print $1}')"
    if [[ "$mode" == 100755 ]]; then
        pass "executable bit: $f"
    else
        fail "missing executable bit: $f (mode=${mode:-untracked})"
    fi
done

mapfile -d '' EXE_FILES < <(
    find "$ROOT" -type f \( -name '*.sh' -o -name '*.py' \)         ! -name audit.sh -print0
)

# Safety policy ---------------------------------------------------------------
check_absent_files 'rpm-ostree'     'no rpm-ostree/Bazzite executable path' "${EXE_FILES[@]}"
check_absent_files 'setenforce[[:space:]]+0|SELINUX=disabled|selinux=0'     'no SELinux/lockdown bypass' "${EXE_FILES[@]}"
check_absent_files 'curl[^\n]*\|[^\n]*(bash|sh)|wget[^\n]*\|[^\n]*(bash|sh)'     'no curl/wget pipe-to-shell' "${EXE_FILES[@]}"
check_absent_files 'patch/(edp-dsc|cdclk-ptl)/install\.sh'     'no custom Xe/CDCLK installer' "${EXE_FILES[@]}"
check_absent_files 'makepkg.*linux-omarchy|pacman[[:space:]].*-U.*linux-omarchy'     'no local linux-omarchy build/install path' "${EXE_FILES[@]}"
check_absent_files 'sudo[[:space:]]+rm[[:space:]]+-rf[[:space:]]+/'     'no raw sudo rm -rf on absolute paths' "${EXE_FILES[@]}"

[[ ! -e "$ROOT/scripts/install-edp-dsc-kernel.sh" ]]     && pass 'obsolete local-kernel installer absent'     || fail 'obsolete local-kernel installer still exists'
[[ ! -e "$ROOT/patches/0990-honor-m1230-edp-dsc.patch" ]]     && pass 'obsolete local-kernel patch absent'     || fail 'obsolete local-kernel patch still exists'

# Low-level phases never surprise-install packages. setup.sh is the explicit
# user-facing orchestrator that may install dependencies after confirmation.
for main in preflight.sh stage-boot.sh install.sh; do
    if grep -nE '^[[:space:]]*(sudo[[:space:]]+)?pacman[[:space:]]+-S' "$ROOT/$main" >/dev/null 2>&1; then
        fail "$main installs packages"
    else
        pass "$main does not install packages"
    fi
done

# No script crosses the reboot boundary.
if grep -nE '^[[:space:]]*(sudo[[:space:]]+)?(systemctl[[:space:]]+reboot|reboot|shutdown[[:space:]]+-r)([[:space:]]|$)'     "${EXE_FILES[@]}" >/dev/null 2>&1; then
    fail "a script automatically reboots the machine"
else
    pass "no script automatically reboots the machine"
fi

# Omarchy owns /etc/default/limine.
if grep -nE '(sed[[:space:]]+-i.*|tee[[:space:]]+|>[[:space:]]*)/etc/default/limine'     "${EXE_FILES[@]}" >/dev/null 2>&1; then
    fail "a script writes /etc/default/limine"
else
    pass "no script writes /etc/default/limine"
fi

# Pins and exact target --------------------------------------------------------
check_present "HONOR_UPSTREAM_COMMIT='[0-9a-f]{40}'" "$ROOT/config/m1230.env"     'HONOR upstream pinned by full commit SHA'
check_present "HONOR_UPSTREAM_TREE='[0-9a-f]{40}'" "$ROOT/config/m1230.env"     'HONOR upstream tree pinned'
check_present "OMARCHY_ISO_REV='[0-9a-f]{40}'" "$ROOT/config/m1230.env"     'Omarchy ISO review revision pinned'
check_present "HONOR_ACPI_STOCK_MD5='27bb4879b5af49ac2b613a73cf1ffa0b'" "$ROOT/config/m1230.env"     'stock ACPI hash pinned'
check_present "HONOR_ACPI_PATCHED_MD5='0ed8b48df42f797b55714fab5aadaf42'" "$ROOT/config/m1230.env"     'patched ACPI hash pinned'
check_present 'status=probed' "$ROOT/scripts/prepare-honor-upstream.py"     'M1230 profile stays below verified'
check_present 'fixes=acpi-override psr-band micmute touchpad-edge fingerprint'     "$ROOT/scripts/prepare-honor-upstream.py"     'M1230 only lists audited Tier-A upstream fixes'
check_present 'DMI_MATCH\(DMI_BOARD_VERSION, "M1230"\)'     "$ROOT/honor-zqcp-kbdlight/honor_zqcp_kbdlight.c"     'keyboard module DMI-bound to M1230'

# Regression checks from the real M1230 bring-up ------------------------------
check_present '\$id" != omarchy' "$ROOT/scripts/lib/common.sh"     'Omarchy ID=omarchy is accepted'
check_present '^[[:space:]]+glib2-devel$' "$ROOT/scripts/lib/common.sh"     'glib2-devel dependency retained for SDCP build'
check_present '^[[:space:]]+jq$' "$ROOT/scripts/lib/common.sh"     'jq dependency retained for DSC session helper'

check_present "HONOR_ACPI_DIR='/usr/lib/firmware/acpi'" "$ROOT/config/m1230.env"     'ACPI payload uses firmware/acpi early-CPIO source path'
check_present "HONOR_ACPI_HOOK='/etc/initcpio/install/acpi_override'" "$ROOT/config/m1230.env"     'pinned ACPI early-CPIO hook path retained'
check_present "HONOR_MKINITCPIO_DROPIN='/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf'" "$ROOT/config/m1230.env"     'last-sorting mkinitcpio ACPI drop-in retained'
check_present 'HOOKS\+=\(acpi_override\)' "$ROOT/stage-boot.sh"     'mkinitcpio ACPI hook appended through drop-in'
check_present 'lsinitcpio --early -x' "$ROOT/stage-boot.sh"     'boot stage verifies extracted early CPIO'
check_present 'name "\*_\$\{kernel_name\}\.efi"' "$ROOT/stage-boot.sh"     'boot stage discovers Omarchy-prefixed UKIs'
check_present 'KERNEL_CMDLINE\[default\]\+=" xe.enable_psr=1"' "$ROOT/stage-boot.sh"     'Omarchy Limine drop-in carries PSR setting'
check_present 'limine-mkinitcpio' "$ROOT/stage-boot.sh"     'Omarchy boot images rebuilt with limine-mkinitcpio'

check_present 'HONOR_ACPI_PATCHED_MD5="\$HONOR_ACPI_PATCHED_MD5"' "$ROOT/install.sh"     'first runtime health check receives expected ACPI hash'
check_present 'ALLOW_PENDING_DSC=1' "$ROOT/install.sh"     'first runtime install initializes pending DSC state'
check_present 'ALLOW_PENDING_DSC=1' "$ROOT/scripts/resume-runtime.sh"     'runtime resume initializes pending DSC state'

check_present 'After=dbus.socket wayland-session-waitenv.service'     "$ROOT/systemd/honor-dsc-modeset.service"     'DSC user service waits for Omarchy UWSM environment'
check_present 'recover_signature' "$ROOT/scripts/dsc-modeset-user.sh"     'DSC helper can recover Hyprland instance signature'
check_present 'dpmsStatus == true' "$ROOT/scripts/dsc-modeset-user.sh"     'DSC helper verifies actual DPMS state'
check_present 'bpp=24 \(8 bpc\).*stock Omarchy kernel' "$ROOT/scripts/health-check.sh"     'stock-kernel 8-bpc DSC state is accepted'
check_present 'try_user_dsc_modeset' "$ROOT/scripts/health-check.sh"     'health check can self-heal pending DSC from the user session'
check_present 'RESULT: PENDING' "$ROOT/scripts/health-check.sh"     'pre-login DSC state is reported as pending, not healthy'
check_present 'stop honor-health-check.timer' "$ROOT/scripts/health-check.sh"     'health polling stops after a fully healthy boot'
check_present 'OnUnitInactiveSec=30s' "$ROOT/systemd/honor-health-check.timer"     'boot health check retries until graphical DSC is ready'

check_present 'probe --set=iso_uuid --fs-uuid' "$ROOT/docs/OMARCHY-USB-BOOT.md"     'USB boot guide probes current ISO UUID'
check_present 'nomodeset module_blacklist=xe' "$ROOT/docs/OMARCHY-USB-BOOT.md"     'USB boot guide contains proven M1230 temporary graphics workaround'
if grep -Rqs '2026-09-15-21-11-51-00' "$ROOT/docs" "$ROOT/README.md"; then
    fail 'USB documentation hard-codes an old ISO UUID'
else
    pass 'USB documentation does not hard-code an old ISO UUID'
fi

check_present 'current_i2c_hash' "$ROOT/setup.sh"     'guided setup detects stock vs patched live ACPI state'
check_present 'BOOT FIXES STAGED SUCCESSFULLY' "$ROOT/setup.sh"     'guided setup stops clearly at reboot boundary'
check_present 'HONOR M1230 / OMARCHY SETUP COMPLETE' "$ROOT/setup.sh"     'guided setup has an explicit final state'

if [[ -e "$ROOT/honor-zqcp-kbdlight/install-bazzite.sh" ]]; then
    fail 'obsolete Bazzite keyboard installer still exists'
else
    pass 'obsolete Bazzite keyboard installer removed'
fi

# Optional shellcheck ----------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' SHFILES < <(find "$ROOT" -type f -name '*.sh' -print0)
    if shellcheck --severity=warning -x "${SHFILES[@]}"; then
        pass 'shellcheck'
    else
        fail 'shellcheck'
    fi
else
    printf '[SKIP] shellcheck is not installed; bash parser checks still passed\n'
fi

if (( FAIL )); then
    echo 'AUDIT RESULT: FAIL'
    exit 1
fi

echo 'AUDIT RESULT: OK'
