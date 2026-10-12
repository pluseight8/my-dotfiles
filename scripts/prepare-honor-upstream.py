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

# M1230 is not in the upstream profile yet. Keep it deliberately at `probed`:
# only Tier-A fixes whose inputs are derived from the running machine are listed.
profile = repo / "devices/zqc-p.conf"
text = profile.read_text()
board = """
[board M1230]
status=probed
origin=pluseight8 M1230 hardware observation
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

# Reuse only recipes whose runtime/device checks make them safe on this unit.
# No M1010 fan, battery, OLED floor, audio or hotkey constants are inherited.
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

# Keep the prepared dependency inspectable and clean. This is a local commit;
# nothing is pushed to the upstream repository.
subprocess.run(
    ["git", "config", "user.name", "HONOR M1230 Omarchy adapter"],
    cwd=repo,
    check=True,
)
subprocess.run(
    ["git", "config", "user.email", "honor-m1230@localhost"],
    cwd=repo,
    check=True,
)
subprocess.run(
    [
        "git",
        "add",
        "devices/zqc-p.conf",
        "patch/acpi-override/zqc-p/M1230/recipe.conf",
        "patch/psr-band/zqc-p/M1230/recipe.conf",
        "patch/micmute/zqc-p/M1230/recipe.conf",
        "patch/touchpad-edge/zqc-p/M1230/recipe.conf",
        "patch/fingerprint/zqc-p/M1230/recipe.conf",
    ],
    cwd=repo,
    check=True,
)
if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo).returncode != 0:
    subprocess.run(
        ["git", "commit", "-m", "local: add M1230 Omarchy-safe profile"],
        cwd=repo,
        check=True,
    )

print("HONOR upstream prepared for ZQC-P/M1230 on Omarchy")
