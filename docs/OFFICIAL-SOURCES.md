# Sources reviewed for the Omarchy adaptation

Reviewed on 2026-10-12.

## Omarchy

Primary source:

- https://github.com/omacom/omarchy
- reviewed revision:
  `4c1b4cb3a94447aff39af98e2fcc0490a9fb32e7`

Relevant interfaces verified there:

- `/etc/limine-entry-tool.d/*.conf` with
  `KERNEL_CMDLINE[default]+=" ..."` for hardware kernel parameters;
- `/etc/mkinitcpio.conf.d/*.conf` with `HOOKS+=(...)`;
- `limine-mkinitcpio` as Omarchy's boot-image rebuild path;
- `linux-omarchy` and `linux-omarchy-headers` in the installed package set;
- `omarchy-setup-security-fingerprint` as the owner of Omarchy PAM/polkit/lock
  integration.

## Omarchy package repository

Primary source:

- https://github.com/omacom/omarchy-pkgs
- reviewed revision:
  `4192ecffd0c5500fd67e1a2db15dafa945655a03`

The reviewed `linux-omarchy` meta package points at `linux-omarchy-bore`; the
reviewed kernel package is based on Linux `7.2.8`.

## Arch mkinitcpio

Primary source:

- https://github.com/archlinux/mkinitcpio

Current upstream includes the `acpi_override` install hook. That hook calls
`add_file_early()` for AML files under `/etc/initcpio/acpi_override`, placing
them in the early uncompressed CPIO required by Linux ACPI table override.

## HONOR hardware research / implementation

Primary project used by this repository:

- https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010
- pinned commit:
  `95631852eeda83b8a32a4913f5431475daad3ca1`
- pinned Git tree:
  `22f982f1a762dc076c00e287ef69e265cc8a69da`

This source provides the audited ZQC-P ACPI table, HID-BPF implementations and
the EgisTec SDCP libfprint recipe. M1230 is added locally at `status=probed`;
the upstream M1010/M1050 `verified` status is never copied to it.

## Linux stable source

Primary stable tree:

- https://github.com/gregkh/linux
- checked at tag `v7.2.8`

`drivers/gpu/drm/i915/display/intel_cdclk.c` at that tag already contains the
Panther Lake guard around the CD2X pipe-field sanitization
(`DISPLAY_VER(display) < 30`). This is why the Omarchy adaptation does not
install the older local `cdclk-ptl` `xe.ko` patch.

## Design rule

Claims about Omarchy behavior are based on Omarchy/Omarchy-pkgs sources.
HONOR-specific behavior is based on the pinned hardware project plus the exact
M1230 observations encoded in this repository. The two are not treated as
interchangeable sources.
