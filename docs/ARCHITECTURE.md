# Architecture — Omarchy / HONOR M1230

## Why the Bazzite design was not copied

Omarchy is Arch-based and uses ordinary pacman packages, mkinitcpio and Limine.
There is no rpm-ostree deployment model and no Fedora SELinux policy requirement
to work around. The Bazzite-specific dracut, rpm-ostree and SELinux code has
therefore been removed rather than translated mechanically.

## Explicit boot boundary

Boot-affecting operations remain visible to the user.

`preflight.sh` validates the machine, kernel, ACPI bytes and pinned source. It
does not alter Limine or initramfs.

The guide then shows the exact manual commands that:

1. copy the audited AML;
2. install the mkinitcpio early-CPIO hook;
3. add `HOOKS+=(honor_acpi_override)`;
4. create the Omarchy Limine cmdline drop-in containing `xe.enable_psr=1`;
5. run `limine-mkinitcpio`;
6. reboot.

Only after that boot does `install.sh` run.

## ACPI

The stock firmware's `I2C_DEVT` table is byte-checked before installation.
Known M1230 stock MD5:

`27bb4879b5af49ac2b613a73cf1ffa0b`

Known patched AML MD5:

`0ed8b48df42f797b55714fab5aadaf42`

The mkinitcpio hook uses `add_file_early` and puts the AML at
`/kernel/firmware/acpi/SSDT27_TPD0.aml` in the early CPIO.

## PSR

Omarchy's own source uses `/etc/limine-entry-tool.d/*.conf` for persistent
kernel command-line additions, so the HONOR drop-in uses:

`KERNEL_CMDLINE[default]+=" xe.enable_psr=1"`

No direct editing of generated Limine entries.

## HID-BPF

The matching `linux-omarchy-headers` tree supplies the exact HID-BPF helper
headers under `/usr/lib/modules/$(uname -r)/build`. The port does not download
Linux header snippets from a mirror.

The micmute and touchpad-edge objects are CO-RE and installed through
`udev-hid-bpf`. The micmute fix retains its boot re-apply service because of the
touchscreen hid-generic/hid-multitouch handoff race.

## Fingerprint

Omarchy's current `libfprint-git` does not provide evidence of the exact EgisTec
ET171 `1c7a:05aa` SDCP support already needed on this M1230. The proven SDCP
branch is therefore built into a private prefix:

`/opt/honor-libfprint-sdcp`

A loader config puts it ahead of the system libfprint. The distribution package
stays installed, so Omarchy's own `omarchy-setup-security-fingerprint` remains
the authority for enrollment, sudo/polkit PAM configuration and lock-screen
integration.

## Keyboard backlight

The M1230 DMI-bound module creates:

`/sys/class/leds/honor::kbd_backlight`

This intentionally matches Omarchy's official
`/sys/class/leds/*kbd_backlight*` discovery rule, so
`omarchy-brightness-keyboard` and the stock Omarchy keyboard-brightness hotkeys
work without modifying `/usr/share/omarchy` or user Hyprland config.

There is no periodic Fn+Space EC polling.

## DSC

The current kernel is probed rather than assumed. Preflight requires the internal
eDP connector to expose `i915_dsc_fec_support` and report DSC sink support.

The boot service runs before the display manager, writes the force flag once and
exits. There is no Fedora SELinux context hack on Omarchy.

The final post-boot health check requires:

- `DSC_Enabled: yes`
- `Force_DSC_Enable: yes`
- `bpp=30`
- `dither=no`

## Update behavior

Omarchy kernel updates provide matching `linux-omarchy-headers`. The keyboard
service checks module vermagic and rebuilds for the running kernel when needed.

ACPI lives in the mkinitcpio hook and PSR in an Omarchy Limine drop-in, so normal
`limine-mkinitcpio` rebuilds preserve them.

A boot health-check timer is the final guard after an `omarchy update` reboot.
