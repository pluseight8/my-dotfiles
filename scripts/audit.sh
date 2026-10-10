#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=1; }

while IFS= read -r -d '' file; do
    if bash -n "$file"; then
        pass "bash -n ${file#"$ROOT"/}"
    else
        fail "bash syntax ${file#"$ROOT"/}"
    fi
done < <(find "$ROOT" -type f -name '*.sh' -print0)

if python3 -m py_compile "$ROOT/scripts/prepare-honor-upstream.py"; then
    pass "python syntax"
else
    fail "python syntax"
fi
rm -rf "$ROOT/scripts/__pycache__"

mapfile -d '' EXECS < <(find "$ROOT" -type f \( -name '*.sh' -o -name '*.py' \) ! -name audit.sh -print0)

check_absent() {
    local pattern="$1" label="$2"
    if grep -nHE "$pattern" "${EXECS[@]}" >/dev/null 2>&1; then
        fail "$label"
        grep -nHE "$pattern" "${EXECS[@]}" >&2 || true
    else
        pass "$label"
    fi
}

check_absent 'rpm-ostree|dracut|dnf([[:space:]]|$)|apt-get|SELinuxContext=' 'no Bazzite/Fedora boot-management logic'
check_absent '^[[:space:]]*(sudo[[:space:]]+)?systemctl[[:space:]]+reboot([[:space:]]|$)' 'no script automatically reboots'
check_absent 'curl[^\n]*\|[^\n]*(bash|sh)|wget[^\n]*\|[^\n]*(bash|sh)' 'no pipe-to-shell'
check_absent 'i8042\.dumbkbd' 'no obsolete i8042.dumbkbd'

if grep -nE 'pacman[[:space:]]+-S|omarchy[[:space:]]+pkg[[:space:]]+add|omarchy-pkg-add'     "$ROOT/install.sh" "$ROOT/preflight.sh" >/dev/null 2>&1; then
    fail "install/preflight installs packages"
else
    pass "package installation remains manual"
fi

if grep -nE 'limine-mkinitcpio|mkinitcpio\.conf|limine-entry-tool|KERNEL_CMDLINE'     "$ROOT/install.sh" >/dev/null 2>&1; then
    fail "install.sh mutates boot configuration"
else
    pass "install.sh is boot-config-free"
fi

grep -q "HONOR_UPSTREAM_COMMIT='[0-9a-f]\{40\}'" "$ROOT/config/m1230.env"     && pass "HONOR upstream commit pinned" || fail "HONOR upstream commit not pinned"
grep -q "HONOR_UPSTREAM_TREE='[0-9a-f]\{40\}'" "$ROOT/config/m1230.env"     && pass "HONOR upstream tree pinned" || fail "HONOR upstream tree not pinned"
grep -q "HONOR_ACPI_STOCK_MD5='27bb4879b5af49ac2b613a73cf1ffa0b'" "$ROOT/config/m1230.env"     && pass "stock ACPI hash pinned" || fail "stock ACPI hash missing"
grep -q "HONOR_ACPI_PATCHED_MD5='0ed8b48df42f797b55714fab5aadaf42'" "$ROOT/config/m1230.env"     && pass "patched ACPI hash pinned" || fail "patched ACPI hash missing"

grep -q 'DMI_MATCH(DMI_BOARD_VERSION, "M1230")' "$ROOT/honor-zqcp-kbdlight/honor_zqcp_kbdlight.c"     && pass "keyboard driver DMI-bound" || fail "keyboard driver DMI guard missing"

if grep -qE 'poll_ms|sync_work|schedule_delayed_work\(&sync' "$ROOT/honor-zqcp-kbdlight/honor_zqcp_kbdlight.c"; then
    fail "keyboard driver has periodic Fn+Space polling"
else
    pass "keyboard driver has no periodic Fn+Space polling"
fi

grep -q '^Before=display-manager.service$' "$ROOT/systemd/honor-force-dsc.service"     && pass "DSC ordered before display manager" || fail "DSC ordering missing"

if grep -q 'SELinuxContext=' "$ROOT/systemd/honor-force-dsc.service"; then
    fail "Fedora SELinux workaround leaked into Omarchy port"
else
    pass "no Fedora SELinux DSC workaround"
fi

python3 - "$ROOT/docs/OFFICIAL-SOURCES.md" <<'PY' || FAIL=1
import re, sys
text=open(sys.argv[1], encoding="utf-8").read()
allowed=(
    "https://omarchy.org/",
    "https://github.com/omacom/omarchy",
    "https://github.com/omacom/omarchy-iso",
    "https://github.com/omacom/omarchy-pkgs",
    "https://archlinux.org/",
    "https://man.archlinux.org/",
)
bad=[u for u in re.findall(r"https?://[^\s)]+", text) if not u.startswith(allowed)]
if bad:
    print("[FAIL] non-official research URL(s):", *bad, sep="\n  ", file=sys.stderr)
    raise SystemExit(1)
print("[PASS] official-source URL allowlist")
PY

if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' SHFILES < <(find "$ROOT" -type f -name '*.sh' -print0)
    if shellcheck --severity=warning -x "${SHFILES[@]}"; then
        pass "shellcheck"
    else
        fail "shellcheck"
    fi
else
    printf '[SKIP] shellcheck unavailable\n'
fi

if [[ -d "$ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
    git -C "$ROOT" diff --check && pass "git diff --check" || fail "git diff --check"
fi

if ((FAIL)); then
    echo "AUDIT RESULT: FAIL"
    exit 1
fi
echo "AUDIT RESULT: OK"
