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

# Dangerous-pattern policy ----------------------------------------------------
check_absent() {
    local pattern="$1" label="$2"
    local files=()
    mapfile -d '' files < <(find "$ROOT" -type f \( -name '*.sh' -o -name '*.py' \) ! -name audit.sh -print0)
    if grep -nHE "$pattern" "${files[@]}" >/dev/null 2>&1; then
        fail "$label"
        grep -nHE "$pattern" "${files[@]}" >&2 || true
    else
        pass "$label"
    fi
}

check_absent 'setenforce[[:space:]]+0|SELINUX=disabled|selinux=0' 'no global SELinux disable'
check_absent 'rpm-ostree[[:space:]]+reset' 'no destructive rpm-ostree reset'
check_absent 'rpm-ostree[[:space:]]+install' 'installer never layers packages automatically'
check_absent 'i8042\.dumbkbd' 'no obsolete i8042.dumbkbd'
check_absent 'patch/(edp-dsc|cdclk-ptl)/install\.sh' 'no custom xe/CDCLK installers'
check_absent 'curl[^\n]*\|[^\n]*(bash|sh)|wget[^\n]*\|[^\n]*(bash|sh)' 'no curl/wget pipe-to-shell'
check_absent 'sudo[[:space:]]+rm[[:space:]]+-rf[[:space:]]+/' 'no raw sudo rm -rf on absolute paths'

# Explicit reboot/package boundary --------------------------------------------
mapfile -t EXEC_SCRIPTS < <(find "$ROOT" -type f -name '*.sh' ! -name audit.sh -print)
if grep -nE '^[[:space:]]*(sudo[[:space:]]+)?systemctl[[:space:]]+reboot([[:space:]]|$)' \
    "${EXEC_SCRIPTS[@]}" >/dev/null 2>&1; then
    fail "a script automatically reboots the machine"
else
    pass "no script automatically reboots the machine"
fi

if grep -nE '^[[:space:]]*(sudo[[:space:]]+)?rpm-ostree[[:space:]]+' "$ROOT/install.sh" >/dev/null 2>&1; then
    fail "install.sh executes rpm-ostree"
else
    pass "install.sh is rpm-ostree-free"
fi

# Required hardening -----------------------------------------------------------
grep -q "HONOR_UPSTREAM_COMMIT='[0-9a-f]\{40\}'" "$ROOT/config/m1230.env" \
    && pass 'HONOR upstream pinned by full commit SHA' \
    || fail 'HONOR upstream is not pinned by full SHA'

grep -q "HONOR_ACPI_STOCK_MD5='27bb4879b5af49ac2b613a73cf1ffa0b'" "$ROOT/config/m1230.env" \
    && pass 'stock ACPI hash pinned' || fail 'stock ACPI hash missing'

grep -q "HONOR_ACPI_PATCHED_MD5='0ed8b48df42f797b55714fab5aadaf42'" "$ROOT/config/m1230.env" \
    && pass 'patched ACPI hash pinned' || fail 'patched ACPI hash missing'

grep -q 'SELinuxContext=system_u:system_r:unconfined_service_t:s0' "$ROOT/systemd/honor-force-dsc.service" \
    && pass 'DSC has per-service SELinux context' || fail 'DSC SELinux context missing'

grep -q 'ExecStart=/usr/bin/bash /usr/local/lib/honor/force-dsc.sh' "$ROOT/systemd/honor-force-dsc.service" \
    && pass 'DSC uses standard bash entrypoint' || fail 'DSC bash entrypoint missing'

grep -q 'DMI_MATCH(DMI_BOARD_VERSION, "M1230")' "$ROOT/honor-zqcp-kbdlight/honor_zqcp_kbdlight.c" \
    && pass 'keyboard module DMI-bound to M1230' || fail 'keyboard module DMI guard missing'

if grep -qE 'poll_ms|schedule_delayed_work\(&sync|sync_work' "$ROOT/honor-zqcp-kbdlight/honor_zqcp_kbdlight.c"; then
    fail 'keyboard driver contains periodic Fn+Space polling'
else
    pass 'keyboard driver has no periodic Fn+Space polling'
fi

# Official-source document allowlist ------------------------------------------
python3 - "$ROOT/docs/OFFICIAL-SOURCES.md" <<'PY' || FAIL=1
import re, sys
from urllib.parse import urlparse
p=sys.argv[1]
text=open(p, encoding='utf-8').read()
allowed_prefixes=(
    'https://docs.bazzite.gg/',
    'https://github.com/ublue-os/bazzite',
    'https://github.com/fedora-selinux/selinux-policy',
)
for u in re.findall(r'https?://[^\s)]+', text):
    if not u.startswith(allowed_prefixes):
        print(f'[FAIL] non-official source URL: {u}', file=sys.stderr)
        raise SystemExit(1)
print('[PASS] official-source document uses allowlisted hosts')
PY

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

# Git whitespace if this is a checkout ---------------------------------------
if [[ -d "$ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
    if git -C "$ROOT" diff --check; then
        pass 'git diff --check'
    else
        fail 'git diff --check'
    fi
fi

if (( FAIL )); then
    echo 'AUDIT RESULT: FAIL'
    exit 1
fi

echo 'AUDIT RESULT: OK'