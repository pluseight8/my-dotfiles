# Architecture

## Goal

This repository is not a forked Linux distribution. It is a thin hardware
adaptation layer for one laptop:

```text
HONOR MagicBook Pro 14 2026 AI
DMI product: ZQC-P
board:       M1230
OS:          Omarchy
```

The hardware research stays in the upstream HONOR project; the integration with
the operating system stays here.

## Source layering

There are three relevant upstreams:

1. **Omarchy** defines the boot/configuration interfaces used on the host:
   Limine drop-ins, mkinitcpio drop-ins, `limine-mkinitcpio`, the Omarchy kernel
   packages and fingerprint security integration.
2. **Arch/mkinitcpio** supplies the `acpi_override` hook and
   `add_file_early()` mechanism.
3. **rs0x29a's HONOR repository** supplies the audited ACPI payload, HID-BPF
   programs and the EgisTec SDCP libfprint recipe.

The HONOR repository is pinned by full commit SHA and tree SHA before it is
used.

## Why M1230 is not called `verified`

The upstream project verifies trust per board revision. Its ZQC-P M1010 and
M1050 data cannot automatically be promoted to M1230.

The local profile therefore declares M1230 as `probed` and lists only Tier-A
fixes:

```text
acpi-override
psr-band
micmute
touchpad-edge
fingerprint
```

Those fixes either verify the actual device/table before touching it or derive
their input from the running machine. No M1010 battery EC offsets, fan offsets,
OLED floor, audio constants or hotkey maps are copied over.

The keyboard-backlight module is separate local M1230 work. It is guarded by
DMI and by the expected `KBBL`, `GKBM` and `SKBM` ACPI symbols before it is
installed.

## Omarchy-native boot configuration

### ACPI

The corrected table is stored at:

```text
/etc/initcpio/acpi_override/SSDT27_TPD0.aml
```

The only mkinitcpio customization is:

```text
/etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf
```

containing:

```bash
HOOKS+=(acpi_override)
```

The `acpi_override` install hook is supplied by mkinitcpio. It calls
`add_file_early()`, producing the early uncompressed CPIO required by the
kernel's ACPI table-upgrade mechanism.

The live `I2C_DEVT` table is hashed before staging. Unknown firmware fails
closed.

### Kernel arguments

This repository does not rewrite `/etc/default/limine`.

It writes:

```text
/etc/limine-entry-tool.d/90-honor-m1230.conf
```

using the same `KERNEL_CMDLINE[default]+=` interface current Omarchy uses for
its own hardware features:

```bash
KERNEL_CMDLINE[default]+=" xe.enable_psr=1"
```

The resulting entries are rebuilt with `limine-mkinitcpio`.

## Why there is no replacement `xe.ko`

Two upstream HONOR fixes affect the Xe display module:

- Panther Lake CDCLK sanitization;
- preferring DSC over a 6-bpc uncompressed eDP link.

For Omarchy these are handled differently.

The CDCLK change was backported to stable Linux 7.2.8, the base used by the
reviewed current Omarchy kernel, so another module is unnecessary.

The DSC preference has not been carried as a foreign module. Omarchy's kernel
contains its own large patch stack, so compiling `xe.ko` against a vanilla
kernel tree would be an unsafe approximation. Instead, the service uses the
kernel's existing debugfs DSC force control and verifies that DSC actually
becomes active.

This keeps the packaged Omarchy `xe.ko` intact.

## HID-BPF

The mic-mute and touchpad-edge programs are installed by the pinned upstream
HONOR scripts. Their device IDs are selected from the local M1230 profile and
then checked against the live HID bus.

They are CO-RE BPF objects stored under `/etc/udev-hid-bpf`. They do not need a
per-kernel rebuild as long as the running kernel preserves the required HID-BPF
ABI/BTF support.

## Fingerprint

The M1230 unit carries EgisTec `1c7a:05aa`, the same SDCP-speaking reader recipe
used by the upstream ZQC-P M1050 path.

That support is not a simple released libfprint ID addition. The upstream HONOR
recipe pins the SDCP development branch and its patches, builds it into:

```text
/opt/honor-libfprint-sdcp
```

and places that private prefix ahead of the distribution library through
`/etc/ld.so.conf.d`.

PAM and lock-screen configuration is intentionally left to:

```bash
omarchy-setup-security-fingerprint
```

so the hardware layer does not duplicate Omarchy's security policy.

## Keyboard backlight

`honor_zqcp_kbdlight.ko` is not installed into the packaged kernel tree. The
source is copied to `/var/lib/honor/kbdlight-src`; on every boot the service:

1. reads the running kernel version;
2. verifies matching headers exist;
3. rebuilds only when the cached module's vermagic/source no longer match;
4. loads the module with `insmod`;
5. checks for `/sys/class/leds/honor::kbd_backlight`.

This naturally handles a normal Omarchy kernel update after the next reboot.

## Persistence

Persistent machine-local state is limited to normal mutable locations:

```text
/etc/initcpio/acpi_override
/etc/mkinitcpio.conf.d
/etc/limine-entry-tool.d
/etc/udev-hid-bpf
/etc/systemd/system
/etc/ld.so.conf.d
/opt/honor-libfprint-sdcp
/usr/local/lib/honor
/var/lib/honor
/var/lib/honor-m1230
/var/opt/honor-magicbook-linux
```

No script automatically reboots the host.
