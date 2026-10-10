# HONOR MagicBook Pro 14 2026 AI (ZQC-P / M1230) — Bazzite setup

Personal, fail-closed hardware setup for **Bazzite KDE** on the exact laptop:

- vendor: `HONOR`
- product: `ZQC-P`
- board: `M1230`
- board name: `ZQC-P-PCB`
- touchscreen: `2808:5662`
- touchpad: `27c6:0f9a`
- fingerprint: `1c7a:05aa`

The repository is intentionally no longer a generic dotfiles collection. The
old CachyOS/DriftWM material is preserved in the Git branch
`backup/pre-bazzite-honor-overhaul-2026-10-10`.

## What it installs

- byte-verified ACPI `I2C_DEVT` override for touchscreen/touchpad enumeration;
- `xe.enable_psr=1`;
- HID-BPF mic-mute descriptor fix;
- HID-BPF left-edge touchpad brightness gesture;
- private patched SDCP libfprint for EgisTec `1c7a:05aa`;
- M1230-only keyboard-backlight LED driver for KDE/UPower;
- forced DSC through the Bazzite OGC kernel's writable debugfs interface;
- boot health check with a single `RESULT: OK/FAIL` report.

The installation is a three-stage state machine. After the one dependency
transaction, you start the installer once; it performs the required reboots and
resumes itself through systemd. Build tools are kept by default for future
repairability; cleanup is optional.

## Quick start

Read [`docs/INSTALL.md`](docs/INSTALL.md). The short version, after host build
dependencies are present, is:

```bash
sudo ./install.sh --yes
```

Do not enable Secure Boot for this tested setup: the local ACPI override and the
out-of-tree keyboard-backlight module are intentionally fail-closed when kernel
lockdown is active.

## Safety model

The installer refuses to continue when the DMI does not match M1230, Secure
Boot/lockdown is active, the live ACPI table differs from the audited reference,
the pinned support source changes, or a required post-reboot check fails.

No `curl | bash`, no global SELinux disable, no `rpm-ostree reset`, no custom
`xe.ko`, and no blind reuse of EC offsets from other board revisions.

See [`docs/AUDIT.md`](docs/AUDIT.md) for the complete audit and
[`docs/OFFICIAL-SOURCES.md`](docs/OFFICIAL-SOURCES.md) for the official Bazzite
sources used to design the integration.
