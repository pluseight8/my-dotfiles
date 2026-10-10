# HONOR MagicBook Pro 14 2026 AI (ZQC-P / M1230) — Bazzite setup

Personal, fail-closed hardware setup for **Bazzite KDE** on the exact laptop:

- vendor: `HONOR`
- product: `ZQC-P`
- board: `M1230`
- board name: `ZQC-P-PCB`
- touchscreen: `2808:5662`
- touchpad: `27c6:0f9a`
- fingerprint: `1c7a:05aa`

The old CachyOS/DriftWM material is preserved in
`backup/pre-bazzite-honor-overhaul-2026-10-10`.

## What it installs

- byte-verified ACPI `I2C_DEVT` override;
- `xe.enable_psr=1`;
- HID-BPF mic-mute descriptor fix;
- HID-BPF left-edge touchpad brightness gesture;
- private patched SDCP libfprint for EgisTec `1c7a:05aa`;
- M1230-only keyboard-backlight LED driver for KDE/UPower;
- forced DSC through the Bazzite OGC kernel debugfs interface;
- boot health check with `RESULT: OK/FAIL`.

## Important design rule

**No script in this repository installs RPM packages or performs a reboot.**

All boot-affecting steps are explicit and manual:

1. you manually run the documented `rpm-ostree install` dependency transaction;
2. you inspect `rpm-ostree status` and reboot yourself;
3. you run `preflight.sh`, which only validates hardware/firmware and prepares
   the pinned support source;
4. you manually stage ACPI/initramfs/PSR commands from `docs/INSTALL.md`;
5. you inspect `rpm-ostree status` and reboot yourself again;
6. only then you run `install.sh`, which is strictly post-reboot/runtime setup;
7. after it succeeds, you choose when to do the final persistence reboot.

`install.sh` contains **no `rpm-ostree` command and no reboot command**.

## Start here

Read [`docs/INSTALL.md`](docs/INSTALL.md) from top to bottom.

The post-reboot runtime install command is:

```bash
sudo ./install.sh --yes
```

Do not enable Secure Boot for this tested setup: the local ACPI override and
out-of-tree keyboard-backlight module are intentionally fail-closed when kernel
lockdown is active.

## Safety model

The setup refuses to continue when DMI does not match M1230, Secure Boot or
lockdown is active, required packages are missing, live ACPI bytes differ from
the audited reference, the pinned support source changes, or a required
post-reboot check fails.

No `curl | bash`, no global SELinux disable, no `rpm-ostree reset`, no automatic
package layering, no automatic reboot, no custom `xe.ko`, and no blind reuse of
EC offsets from another board revision.

See:

- [`docs/INSTALL.md`](docs/INSTALL.md)
- [`docs/AUDIT.md`](docs/AUDIT.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/UPDATES.md`](docs/UPDATES.md)
- [`docs/BIOS-UPDATE.md`](docs/BIOS-UPDATE.md)
- [`docs/OFFICIAL-SOURCES.md`](docs/OFFICIAL-SOURCES.md)
