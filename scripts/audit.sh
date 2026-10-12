#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=1; }

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

# Executable safety policy -----------------------------------------------------
mapfile -d '' EXE_FILES < <(
    find "$ROOT" -type f \( -name '*.sh' -o -name '*.py' \) \
        ! -name audit.sh -print0
)

check_absent() {
    local pattern="$1" label="$2"
    if grep -nHE "$pattern" "${EXE_FILES[@]}" >/dev/null 2>&1; then
        fail "$label"
        grep -nHE "$pattern" "${EXE_FILES[@]}" >&2 || true
    else
        pass "$label"
    fi
}

check_absent 'rpm-ostree' 'no rpm-ostree/Bazzite executable path'
check_absent 'setenforce[[:space:]]+0|SELINUX=disabled|selinux=0' 'no SELinux/lockdown bypass'
check_absent 'curl[^\n]*\|[^\n]*(bash|sh)|wget[^\n]*\|[^\n]*(bash|sh)' 'no curl/wget pipe-to-shell'
check_absent 'patch/(edp-dsc|cdclk-ptl)/install\.sh' 'no custom xe/CDCLK installer'
check_absent 'sudo[[:space:]]+rm[[:space:]]+-rf[[:space:]]+/' 'no raw sudo rm -rf on absolute paths'

# The user owns package installation.
for main in preflight.sh stage-boot.sh install.sh; do
    if grep -nE '^[[:space:]]*(sudo[[:space:]]+)?pacman[[:space:]]+-S' "$ROOT/$main" >/dev/null 2>&1; then
        fail "$main installs packages"
    else
        pass "$main does not install packages"
    fi
done

# No script crosses the reboot boundary itself.
if grep -nE '^[[:space:]]*(sudo[[:space:]]+)?(systemctl[[:space:]]+reboot|reboot|shutdown[[:space:]]+-r)([[:space:]]|$)' \
    "${EXE_FILES[@]}" >/dev/null 2>&1; then
    fail "a script automatically reboots the machine"
else
    pass "no script automatically reboots the machine"
fi

# Omarchy owns /etc/default/limine. Reading it is allowed; writing it is not.
if grep -nE '(sed[[:space:]]+-i.*|tee[[:space:]]+|>[[:space:]]*)/etc/default/limine' \
    "${EXE_FILES[@]}" >/dev/null 2>&1; then
    fail "a script writes /etc/default/limine"
else
    pass "no script writes /etc/default/limine"
fi

# Required pins/invariants -----------------------------------------------------
grep -q "HONOR_UPSTREAM_COMMIT='[0-9a-f]\{40\}'" "$ROOT/config/m1230.env" \
    && pass 'HONOR upstream pinned by full commit SHA' \
    || fail 'HONOR upstream is not pinned by full SHA'

grep -q "HONOR_UPSTREAM_TREE='[0-9a-f]\{40\}'" "$ROOT/config/m1230.env" \
    && pass 'HONOR upstream tree pinned' \
    || fail 'HONOR upstream tree is not pinned'

grep -q "HONOR_ACPI_STOCK_MD5='27bb4879b5af49ac2b613a73cf1ffa0b'" "$ROOT/config/m1230.env" \
    && pass 'stock ACPI hash pinned' \
    || fail 'stock ACPI hash missing'

grep -q "HONOR_ACPI_PATCHED_MD5='0ed8b48df42f797b55714fab5aadaf42'" "$ROOT/config/m1230.env" \
    && pass 'patched ACPI hash pinned' \
    || fail 'patched ACPI hash missing'

grep -q 'status=probed' "$ROOT/scripts/prepare-honor-upstream.py" \
    && pass 'M1230 profile stays below verified' \
    || fail 'M1230 trust level changed'

grep -q 'fixes=acpi-override psr-band micmute touchpad-edge fingerprint' \
    "$ROOT/scripts/prepare-honor-upstream.py" \
    && pass 'M1230 only lists audited Tier-A upstream fixes' \
    || fail 'M1230 fix allow-list changed'

grep -q 'HOOKS+=(acpi_override)' "$ROOT/stage-boot.sh" \
    && pass 'mkinitcpio ACPI hook installed through drop-in' \
    || fail 'mkinitcpio ACPI drop-in missing'

grep -q 'KERNEL_CMDLINE\[default\]+=" xe.enable_psr=1"' "$ROOT/stage-boot.sh" \
    && pass 'Omarchy Limine drop-in carries PSR setting' \
    || fail 'Omarchy PSR drop-in missing'

grep -q 'limine-mkinitcpio' "$ROOT/stage-boot.sh" \
    && pass 'Omarchy boot images rebuilt with limine-mkinitcpio' \
    || fail 'limine-mkinitcpio missing'

grep -q 'DMI_MATCH(DMI_BOARD_VERSION, "M1230")' \
    "$ROOT/honor-zqcp-kbdlight/honor_zqcp_kbdlight.c" \
    && pass 'keyboard module DMI-bound to M1230' \
    || fail 'keyboard module DMI guard missing'

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
