#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

repo = Path(sys.argv[1] if len(sys.argv) > 1 else "/var/opt/honor-magicbook-linux")
if not (repo / ".git").exists():
    raise SystemExit(f"not a git repo: {repo}")


def sh(*args):
    return subprocess.check_output(args, cwd=repo, text=True).strip()

expected = "95631852eeda83b8a32a4913f5431475daad3ca1"
head = sh("git", "rev-parse", "HEAD")
if head != expected:
    raise SystemExit(f"expected pinned upstream {expected}, got {head}")

# ----- M1230 profile ---------------------------------------------------------
p = repo / "devices/zqc-p.conf"
s = p.read_text()
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
if "[board M1230]" not in s:
    p.write_text(s.rstrip() + "\n\n" + board + "\n")

recipes = {
    "patch/acpi-override/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/psr-band/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/micmute/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/touchpad-edge/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1010\n",
    "patch/fingerprint/zqc-p/M1230/recipe.conf": "same_as=zqc-p/M1050\n",
}
for rel, content in recipes.items():
    out = repo / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content)

# ----- fingerprint: immutable /usr ------------------------------------------
fp = repo / "patch/fingerprint/install.sh"
s = fp.read_text()
old = '''    ninja -C "$GITDIR/build" >/dev/null || die "build failed"
    ninja -C "$GITDIR/build" install >/dev/null || die "install failed"
'''
new = '''    ninja -C "$GITDIR/build" >/dev/null || die "build failed"

    # Bazzite/Fedora Atomic: /usr is read-only. Stage the Meson install and
    # copy only the private /opt prefix plus the generated udev rule to /etc.
    STAGE="${WORK}/stage"
    mkdir -p "$STAGE"
    DESTDIR="$STAGE" ninja -C "$GITDIR/build" install >/dev/null \\
        || die "staged install failed"

    rm -rf "$PREFIX"
    [[ -d "$STAGE$PREFIX" ]] \\
        || die "staged prefix missing: $STAGE$PREFIX"
    install -d "$(dirname "$PREFIX")"
    cp -a "$STAGE$PREFIX" "$PREFIX"

    UDEV_RULE="$STAGE/usr/lib/udev/rules.d/70-libfprint-2.rules"
    if [[ -f "$UDEV_RULE" ]]; then
        install -Dm644 "$UDEV_RULE" /etc/udev/rules.d/70-libfprint-2.rules
        udevadm control --reload
        udevadm trigger --subsystem-match=usb --action=add 2>/dev/null || true
    fi

    restorecon -RF "$PREFIX" /etc/udev/rules.d/70-libfprint-2.rules \\
        >/dev/null 2>&1 || true
'''
if old in s:
    s = s.replace(old, new, 1)
elif "staged install failed" not in s:
    raise SystemExit("fingerprint installer no longer matches audited upstream")
fp.write_text(s)

# ----- touchpad edge: current udev-hid-bpf has no list-loaded ---------------
tp = repo / "patch/touchpad-edge/install.sh"
s = tp.read_text()
old_add = 'udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null 2>&1 || true'
new_add = 'udev-hid-bpf add "$DEV" "${INSTALL_DIR}/${OBJ_NAME}" >/dev/null || die "udev-hid-bpf add failed"'
if old_add in s:
    s = s.replace(old_add, new_add, 1)
elif "udev-hid-bpf add failed" not in s:
    raise SystemExit("touchpad-edge add command no longer matches audited upstream")

old_verify = '''edge_attached() { udev-hid-bpf list-loaded 2>/dev/null | grep -q "$PROG_TAG"; }
gate_wait_until 10 edge_attached \\
    || die "the program is not attached to the device"

log "attached"
'''
new_verify = '''# Current Fedora/Bazzite udev-hid-bpf no longer exposes list-loaded. The add
# command above is authoritative; boot-time attachment is handled by udev.
log "attached"
'''
if old_verify in s:
    s = s.replace(old_verify, new_verify, 1)
elif "Current Fedora/Bazzite udev-hid-bpf no longer exposes list-loaded" not in s:
    raise SystemExit("touchpad-edge verification no longer matches audited upstream")
tp.write_text(s)

# Record the adaptation as a local commit so git status stays clean and future
# inspection is simple.
subprocess.run(["git", "config", "user.name", "HONOR M1230 Bazzite installer"], cwd=repo, check=True)
subprocess.run(["git", "config", "user.email", "honor-m1230@localhost"], cwd=repo, check=True)
subprocess.run(["git", "add", "devices/zqc-p.conf", "patch/acpi-override/zqc-p/M1230/recipe.conf",
                "patch/psr-band/zqc-p/M1230/recipe.conf", "patch/micmute/zqc-p/M1230/recipe.conf",
                "patch/touchpad-edge/zqc-p/M1230/recipe.conf", "patch/fingerprint/zqc-p/M1230/recipe.conf",
                "patch/fingerprint/install.sh", "patch/touchpad-edge/install.sh"], cwd=repo, check=True)
if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo).returncode != 0:
    subprocess.run(["git", "commit", "-m", "local: M1230 Bazzite adaptation"], cwd=repo, check=True)

print("HONOR upstream prepared for M1230/Bazzite")
