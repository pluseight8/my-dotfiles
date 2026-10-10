#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

repo = Path(sys.argv[1] if len(sys.argv) > 1 else "/var/opt/honor-magicbook-linux")
if not (repo / ".git").exists():
    raise SystemExit(f"not a git repo: {repo}")

EXPECTED = "95631852eeda83b8a32a4913f5431475daad3ca1"
head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
if head != EXPECTED:
    raise SystemExit(f"expected pinned upstream {EXPECTED}, got {head}")

profile = repo / "devices/zqc-p.conf"
text = profile.read_text()
board = """
[board M1230]
status=probed
origin=local M1230 hardware observation
platform=pantherlake
dgpu=none
cpu=Intel(R) Core(TM) Ultra X7 358H
dmi_board=ZQC-P-PCB
dmi_sku=C233
touchscreen_hid=2808:5662
touchpad_hid=27c6:0f9a
audio_ssid=1ee7:209d
fingerprint_usb=1c7a:05aa
camera_usb=30c9:012c
panel=oled
backlight_max=704
fixes=acpi-override psr-band micmute touchpad-edge fingerprint
""".strip()
if "[board M1230]" not in text:
    profile.write_text(text.rstrip() + "\n\n" + board + "\n")

recipes = {
    "patch/acpi-override/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/psr-band/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/micmute/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/touchpad-edge/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/fingerprint/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1050\n",
}
for rel, body in recipes.items():
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)

# Use exact matching Omarchy kernel headers, never a downloaded Linux mirror.
fetch_block = '''ksrc_resolve
log "headers = ${KSRC_TAG}"
for h in hid_bpf.h hid_bpf_helpers.h hid_report_descriptor_helpers.h; do
    ksrc_fetch "drivers/hid/bpf/progs/${h}" "${WORK}/${h}"
done
'''
local_block = '''KBUILD="/usr/lib/modules/${KVER}/build"
log "headers = local Omarchy kernel tree: ${KBUILD}"
for h in hid_bpf.h hid_bpf_helpers.h hid_report_descriptor_helpers.h; do
    src="${KBUILD}/drivers/hid/bpf/progs/${h}"
    [[ -f "$src" ]] || die "linux-omarchy-headers is missing $src"
    cp "$src" "${WORK}/${h}"
done
'''
for rel in ("patch/micmute/install.sh", "patch/touchpad-edge/install.sh"):
    p = repo / rel
    data = p.read_text()
    if fetch_block in data:
        data = data.replace(fetch_block, local_block, 1)
    elif "headers = local Omarchy kernel tree" not in data:
        raise SystemExit(f"{rel}: HID-BPF header block drifted from audited upstream")
    data = data.replace(
        "for t in clang bpftool curl udev-hid-bpf udevadm; do",
        "for t in clang bpftool udev-hid-bpf udevadm; do",
        1,
    )
    p.write_text(data)

# Arch udev-hid-bpf 2.3 has add/remove/list-devices, not the old list-loaded.
tp = repo / "patch/touchpad-edge/install.sh"
data = tp.read_text()
data = data.replace(
    'udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null 2>&1 || true',
    'udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null || die "udev-hid-bpf add failed"',
    1,
)
old_verify = '''edge_attached() { udev-hid-bpf list-loaded 2>/dev/null | grep -q "$PROG_TAG"; }
gate_wait_until 10 edge_attached \\
    || die "the program is not attached to the device"

log "attached"
'''
new_verify = '''# Current Arch udev-hid-bpf has no list-loaded command. A successful add is
# authoritative; persistence is handled by the installed udev rule.
log "attached"
'''
if old_verify in data:
    data = data.replace(old_verify, new_verify, 1)
elif "Current Arch udev-hid-bpf has no list-loaded command" not in data:
    raise SystemExit("touchpad-edge verification drifted from audited upstream")
tp.write_text(data)

# Live micmute attach must also fail loudly if the loader rejects it.
mm = repo / "patch/micmute/install.sh"
data = mm.read_text()
data = data.replace(
    'udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null 2>&1 || true',
    'udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null || die "udev-hid-bpf add failed"',
    1,
)
mm.write_text(data)

# Keep the private EgisTec SDCP lib under /opt and put its generated local udev
# rule in /etc instead of leaving an unowned file in /usr.
fp = repo / "patch/fingerprint/install.sh"
data = fp.read_text()
old = '''    ninja -C "$GITDIR/build" >/dev/null || die "build failed"
    ninja -C "$GITDIR/build" install >/dev/null || die "install failed"
'''
new = '''    ninja -C "$GITDIR/build" >/dev/null || die "build failed"

    STAGE="${WORK}/stage"
    mkdir -p "$STAGE"
    DESTDIR="$STAGE" ninja -C "$GITDIR/build" install >/dev/null \\
        || die "staged install failed"

    rm -rf "$PREFIX"
    [[ -d "$STAGE$PREFIX" ]] || die "staged prefix missing: $STAGE$PREFIX"
    install -d "$(dirname "$PREFIX")"
    cp -a "$STAGE$PREFIX" "$PREFIX"

    UDEV_RULE="$STAGE/usr/lib/udev/rules.d/70-libfprint-2.rules"
    if [[ -f "$UDEV_RULE" ]]; then
        install -Dm644 "$UDEV_RULE" /etc/udev/rules.d/70-libfprint-2.rules
        udevadm control --reload
        udevadm trigger --subsystem-match=usb --action=add 2>/dev/null || true
    fi
'''
if old in data:
    data = data.replace(old, new, 1)
elif "staged install failed" not in data:
    raise SystemExit("fingerprint install block drifted from audited upstream")
fp.write_text(data)

subprocess.run(["git", "config", "user.name", "HONOR M1230 Omarchy adapter"], cwd=repo, check=True)
subprocess.run(["git", "config", "user.email", "honor-m1230@localhost"], cwd=repo, check=True)
subprocess.run([
    "git", "add",
    "devices/zqc-p.conf",
    "patch/acpi-override/zqc-p/M1230/recipe.conf",
    "patch/psr-band/zqc-p/M1230/recipe.conf",
    "patch/micmute/zqc-p/M1230/recipe.conf",
    "patch/touchpad-edge/zqc-p/M1230/recipe.conf",
    "patch/fingerprint/zqc-p/M1230/recipe.conf",
    "patch/micmute/install.sh",
    "patch/touchpad-edge/install.sh",
    "patch/fingerprint/install.sh",
], cwd=repo, check=True)
if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo).returncode != 0:
    subprocess.run(["git", "commit", "-m", "local: M1230 Omarchy adaptation"], cwd=repo, check=True)

print("HONOR support source prepared for M1230 / Omarchy")
