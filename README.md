# HONOR MagicBook Pro 14 2026 AI (ZQC-P / M1230) — Omarchy

Hardware bring-up for the exact **HONOR ZQC-P / M1230** laptop on current
**Omarchy**.

This repository adapts the research and fixes from
[`rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010`](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010)
without blindly running its generic `apply_patch.sh`.

The target machine is intentionally fail-closed:

- vendor: `HONOR`
- product: `ZQC-P`
- board revision: `M1230`
- board name: `ZQC-P-PCB`
- touchscreen: `2808:5662`
- touchpad: `27c6:0f9a`
- fingerprint: `1c7a:05aa`
- audio subsystem: `1ee7:209d`

## What this Omarchy adaptation does

It installs only the fixes that have been observed or can be safely identified
on this M1230:

- byte-checked ACPI `I2C_DEVT` override for touchpad/touchscreen enumeration;
- `xe.enable_psr=1` through an **Omarchy Limine drop-in**;
- HID-BPF phantom mic-mute fix for the touchscreen;
- HID-BPF left-edge brightness gesture for the touchpad;
- private SDCP-capable libfprint for the EgisTec `1c7a:05aa` reader;
- M1230-only keyboard-backlight LED driver (`honor::kbd_backlight`);
- DSC force service for the internal OLED, avoiding a foreign `xe.ko`;
- boot health check with a single `RESULT: OK/FAIL`.

## What it deliberately does *not* do

- no `rpm-ostree` or Bazzite logic;
- no direct edits to `/etc/default/limine`;
- no custom `xe.ko` copied from or rebuilt against a vanilla kernel;
- no blind reuse of M1010/M1050 EC offsets or Tier-B fixes;
- no automatic reboot;
- no `curl | bash`;
- no Secure-Boot/lockdown bypass.

The old `cdclk-ptl` module patch is also not installed. Omarchy's current
7.2.8-based kernel already contains the stable Panther Lake CDCLK sanitization
fix, so carrying another `xe.ko` for it would add risk without adding a fix.

## Installation model

The process has a hard reboot boundary:

1. install host dependencies manually;
2. run `preflight.sh`;
3. run `stage-boot.sh`;
4. reboot **yourself**;
5. run `install.sh`;
6. enroll the fingerprint and let Omarchy configure its own PAM/lock integration.

Start with [`docs/INSTALL.md`](docs/INSTALL.md). Do not skip the preflight.

The scripts never reboot the laptop for you.
