# HONOR MagicBook Pro 14 2026 AI (ZQC-P / M1230) — Omarchy

Hardware bring-up for the exact laptop:

- HONOR / ZQC-P / M1230 / ZQC-P-PCB
- Intel Panther Lake / Arc B390
- FocalTech touchscreen `2808:5662`
- Goodix touchpad `27c6:0f9a`
- EgisTec ET171 fingerprint `1c7a:05aa`
- 3120×2080 120 Hz OLED

This branch is built for **Omarchy Quattro / Arch**, not Bazzite. The previous
Bazzite implementation is preserved in
`backup/pre-omarchy-overhaul-2026-10-10`.

## Goal

Restore and integrate the hardware features already proven on this exact M1230:

- ACPI I2C fix for touchscreen + touchpad;
- `xe.enable_psr=1`;
- micmute HID-BPF descriptor fix;
- touchpad left-edge brightness gesture;
- EgisTec SDCP fingerprint support;
- keyboard backlight exposed as `honor::kbd_backlight`;
- Omarchy-native keyboard brightness through `omarchy-brightness-keyboard`;
- DSC + 10-bit output when the current `linux-omarchy` kernel exposes the
  required debugfs control;
- persistent boot health check.

## Design rule

**Nothing hides package installation or reboot-required boot changes.**

Package installation is a manual `pacman` command from the guide.
`preflight.sh` validates the machine and prepares pinned source only. ACPI,
mkinitcpio, Limine and PSR commands are explicit in the guide. You run
`limine-mkinitcpio` and every reboot yourself. `install.sh` is post-reboot
runtime setup only: no package install, no bootloader/initramfs mutation, no
reboot.

Start with [`docs/INSTALL.md`](docs/INSTALL.md).

## Source policy

All Omarchy behavior in this port was derived from the official Omarchy site,
manual, `omacom/omarchy`, `omacom/omarchy-iso` and
`omacom/omarchy-pkgs`. Official Arch package pages were used only to verify
Arch package/CLI details.

The model-specific HONOR payload is the same pinned hardware-support code already
validated on this exact M1230 during the previous bring-up; it is not treated as
an authority on Omarchy.

See [`docs/OFFICIAL-SOURCES.md`](docs/OFFICIAL-SOURCES.md) and
[`docs/AUDIT.md`](docs/AUDIT.md).
