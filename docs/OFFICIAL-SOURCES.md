# Sources reviewed for the Omarchy adaptation

Reviewed on 2026-10-13 after completing a full install/reboot cycle on the
target M1230.

## Omarchy

Primary source:

- https://github.com/omacom/omarchy
- reviewed revision:
  `492b8837deea69663c7a5418871f07ed075a9686`

Relevant interfaces/behavior checked there:

- `/etc/limine-entry-tool.d/*.conf`;
- `limine-mkinitcpio`;
- Omarchy's UWSM/systemd user-session model;
- `wayland-session-waitenv.service`;
- Hyprland session environment handling;
- `omarchy-setup-security-fingerprint`.

## Omarchy package repository

Primary source:

- https://github.com/omacom/omarchy-pkgs
- reviewed revision:
  `e499d021c69d27e0750f77f9af7cd68534c8016f`

This repository intentionally consumes the official `linux-omarchy` package
instead of producing a local replacement.

## Omarchy ISO

Primary source:

- https://github.com/omacom/omarchy-iso
- branch: `quattro`
- reviewed revision:
  `53b80d406cdcb56cd757562e0f31d2c13cb57f47`

The official x86_64 GRUB entry at that revision uses:

```text
/arch/boot/x86_64/vmlinuz-linux-t2
/arch/boot/x86_64/initramfs-linux-t2.img
archisobasedir=arch
archisosearchuuid=<ISO UUID>
quiet splash
xe.enable_panel_replay=0
initramfs_async=0
```

The target M1230 required only the temporary live-USB additions documented in
[OMARCHY-USB-BOOT.md](OMARCHY-USB-BOOT.md):

```text
nomodeset module_blacklist=xe
```

## HONOR hardware research / implementation

Primary project:

- https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010
- pinned commit:
  `95631852eeda83b8a32a4913f5431475daad3ca1`
- pinned Git tree:
  `22f982f1a762dc076c00e287ef69e265cc8a69da`

This source provides:

- audited ZQC-P ACPI bytes;
- the early-CPIO `acpi_override.install` hook;
- HID-BPF implementations;
- the EgisTec SDCP libfprint recipe.

The pinned ACPI hook explicitly copies AML files from:

```text
/usr/lib/firmware/acpi/
```

into the early uncompressed CPIO at:

```text
/kernel/firmware/acpi/
```

using `add_file_early()`.

M1230 is added locally as `status=probed`; M1010/M1050 `verified` status is
not copied onto it.

## Linux / Intel display behavior

The repository does not carry a custom Xe module or custom Omarchy kernel.

Display correctness is validated on the running packaged kernel instead:

- no FIFO underrun in the current boot;
- DSC sink support present;
- `Force_DSC_Enable: yes`;
- `DSC_Enabled: yes` after the compositor modeset;
- `dither=no`.

The accepted stock-kernel depth on the target is `bpp=24` (8 bpc).

## Design rule

Omarchy behavior is derived from Omarchy/Omarchy-ISO/Omarchy-pkgs sources.
HONOR-specific behavior comes from the pinned HONOR source plus observations
that are explicitly encoded as health checks.

The repository prefers runtime verification over version-number assumptions.
