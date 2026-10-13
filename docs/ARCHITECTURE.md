# Architecture

## Goal

This repository is a thin hardware-adaptation layer for one machine:

```text
HONOR MagicBook Pro 14 2026 AI
DMI product: ZQC-P
board:       M1230
OS:          Omarchy
kernel:      official linux-omarchy package
```

It is intentionally not a forked distribution and not a custom-kernel project.

## Source layering

The implementation uses four upstreams with separate responsibilities:

1. **Omarchy** defines the host integration points: Limine drop-ins,
   `limine-mkinitcpio`, UWSM/Hyprland session behavior, fingerprint security
   setup and the stock kernel packages.
2. **Omarchy ISO** defines the official live-USB kernel/initramfs paths and GRUB
   command line used by [OMARCHY-USB-BOOT.md](OMARCHY-USB-BOOT.md).
3. **Arch/mkinitcpio** supplies the early-CPIO mechanism needed for ACPI table
   replacement.
4. **rs0x29a's HONOR repository** supplies the audited ACPI payload, HID-BPF
   programs and EgisTec SDCP libfprint recipe.

The HONOR repository is pinned by full commit SHA and tree SHA before its files
are used.

## M1230 trust level

M1010/M1050 `verified` status is not copied onto M1230.

The local M1230 profile stays `probed` and only exposes the audited Tier-A
fixes:

```text
acpi-override
psr-band
micmute
touchpad-edge
fingerprint
```

No battery/fan/OLED-floor/audio/hotkey EC constants from another board revision
are inherited blindly.

The keyboard-backlight module is separate M1230-specific work guarded by exact
DMI and expected ACPI symbols.

## ACPI boot path

The patched table is stored at:

```text
/usr/lib/firmware/acpi/SSDT27_TPD0.aml
```

The pinned early-CPIO hook is installed at:

```text
/etc/initcpio/install/acpi_override
```

A last-sorting Omarchy/mkinitcpio drop-in lives at:

```text
/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
```

and appends:

```bash
HOOKS+=(acpi_override)
```

The stage script rebuilds with `limine-mkinitcpio`, then extracts the **early
CPIO from the actual generated boot image** and hashes the included AML.

This deliberately avoids two bugs discovered during bring-up:

- assuming an obsolete ACPI directory layout;
- assuming the UKI was named `linux-omarchy.efi` when Omarchy may generate a
  prefixed name such as `omarchy_linux-omarchy.efi`.

After reboot, the live ACPI table bytes are hashed again. Kernel-log wording is
only supporting evidence, not the authority.

## Kernel command line

The repository never rewrites:

```text
/etc/default/limine
```

It writes:

```text
/etc/limine-entry-tool.d/90-honor-m1230.conf
```

with:

```bash
KERNEL_CMDLINE[default]+=" xe.enable_psr=1"
```

This follows Omarchy's own drop-in model.

## Stock-kernel policy

No custom `linux-omarchy` and no replacement `xe.ko` are installed.

The target stock-kernel display state is:

```text
DSC_Enabled: yes
Force_DSC_Enable: yes
bpp=24
dither=no
```

10 bpc is not a repository invariant because achieving it currently requires a
kernel-side eDP preference patch. Keeping that patch out is what allows normal
Omarchy kernel updates to remain normal.

## Why DSC has two services

Writing the kernel debugfs DSC force flag does not necessarily change the mode
that the compositor is already using.

Therefore:

- `honor-force-dsc.service` runs system-wide and arms the kernel's existing
  DSC force control;
- `honor-dsc-modeset.service` runs in the Omarchy user session after
  UWSM/Wayland environment import and asks Hyprland to perform one internal-eDP
  DPMS cycle.

The user helper can recover `HYPRLAND_INSTANCE_SIGNATURE` from the live
runtime directory if the environment variable is not present yet.

During the DPMS transition Hyprland can transiently return
`7/NOTRUNNING`. The helper does not treat that return code as authoritative;
it verifies the monitor's actual `dpmsStatus` afterward.

## HID-BPF

The mic-mute and touchpad-edge programs are installed from the pinned HONOR
source and live under:

```text
/etc/udev-hid-bpf/
```

They are CO-RE objects and rely on the running Omarchy kernel's BTF/HID-BPF
support.

## Fingerprint

The EgisTec `1c7a:05aa` reader uses the pinned SDCP libfprint recipe and is
installed into a private prefix:

```text
/opt/honor-libfprint-sdcp
```

The build requires `glib2-devel` in addition to the normal libfprint build
stack. The repository does not replace Omarchy's security policy; enrollment
and PAM/polkit/lock integration remain owned by:

```bash
omarchy-setup-security-fingerprint
```

## Keyboard backlight

The M1230 keyboard-backlight source is copied to:

```text
/var/lib/honor/kbdlight-src
```

At boot the service checks the running kernel, rebuilds when the cached module
does not match, loads it and verifies:

```text
/sys/class/leds/honor::kbd_backlight
```

This is the only local kernel module in the adaptation.

## Health model

`/usr/local/lib/honor/health-check.sh` writes:

```text
/var/lib/honor/health-last.txt
```

The final line is deliberately simple:

```text
RESULT: OK
```

or:

```text
RESULT: FAIL
```

Important checks include the live ACPI hash, PSR, HID devices/objects,
keyboard-backlight service, DSC state/display depth and fingerprint runtime.

## Guided state machine

`setup.sh` is the preferred front end.

On a stock live ACPI state it performs audit/preflight/staging and stops at the
reboot boundary.

After reboot it recognizes the patched live ACPI hash, runs the runtime install
if needed, refreshes user/system services, then performs the final health check.

No script automatically crosses the reboot boundary.

## Persistent locations

```text
/usr/lib/firmware/acpi
/etc/initcpio/install
/etc/mkinitcpio.conf.d
/etc/limine-entry-tool.d
/etc/udev-hid-bpf
/etc/systemd/system
/etc/systemd/user
/etc/ld.so.conf.d
/opt/honor-libfprint-sdcp
/usr/local/lib/honor
/var/lib/honor
/var/lib/honor-m1230
/var/opt/honor-magicbook-linux
```
