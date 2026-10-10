# Audit — Omarchy / HONOR M1230

Audit target: this repository after the Omarchy port.

## Scope

The repository is intentionally specific to:

- HONOR ZQC-P / board M1230;
- supported Omarchy ISO installation;
- Omarchy's default x86_64 `linux-omarchy` kernel family;
- the exact hardware IDs recorded in `config/m1230.env`.

The previous Bazzite implementation is preserved in
`backup/pre-omarchy-overhaul-2026-10-10` and is not mixed into this main branch.

## Omarchy integration

### Official-source usage — PASS

Omarchy behavior was derived only from the official site/manual and official
`omacom` repositories. Current Arch package details came only from official
Arch package/manual pages.

### Package boundary — PASS

No repository script runs `pacman -S`. The user installs the explicitly listed
dependencies manually.

`install.sh` only queries/uses already installed packages.

### Boot boundary — PASS

No repository script runs `systemctl reboot`.

`preflight.sh` does not modify Limine or mkinitcpio configuration.

The ACPI hook, Limine cmdline drop-in, `limine-mkinitcpio` invocation and both
validation reboots are explicit commands in `docs/INSTALL.md`.

`install.sh` contains no Limine/mkinitcpio mutation and runs only after the ACPI
override and PSR setting are already active.

### Omarchy kernel integration — PASS

The port uses the matching `linux-omarchy-headers` tree. HID-BPF helper headers
are read from `/usr/lib/modules/$(uname -r)/build` instead of fetched from a
Linux mirror.

The keyboard module rebuild service also targets the running kernel's matching
build tree.

### Omarchy keyboard integration — PASS

Official `omarchy-brightness-keyboard` discovers
`/sys/class/leds/*kbd_backlight*`. The local DMI-bound module exposes
`honor::kbd_backlight`, so no edit to `/usr/share/omarchy` or user Hyprland
config is required.

### Omarchy fingerprint integration — PASS WITH EXTERNAL DRIVER RISK

Omarchy's official `omarchy-setup-security-fingerprint` remains responsible for
enrollment, sudo/polkit PAM and lock-screen integration.

The exact EgisTec ET171 `1c7a:05aa` still uses the already-tested private SDCP
libfprint build under `/opt`. This is the largest compatibility risk after a
future libfprint/fprintd update.

## Hardware safety

### DMI gate — PASS

Preflight and the keyboard module independently require HONOR / ZQC-P / M1230.

### ACPI gate — PASS

Before the guide tells the user to copy an AML, preflight:

1. finds the live SSDT by OEM table ID `I2C_DEVT`;
2. verifies the known stock reference MD5;
3. verifies the known patched AML MD5;
4. requires live bytes to match the stock reference exactly.

No force switch bypasses this.

### HID-BPF — PASS

The M1230 profile pins the exact touchscreen/touchpad IDs. The adapter removes
the obsolete `list-loaded` verification and builds against local Omarchy kernel
headers.

### Keyboard EC driver — PASS

The module:

- is DMI-bound to M1230;
- requires the expected DSDT symbols before installation;
- uses the already-validated KBBL mapping;
- performs no periodic Fn+Space polling.

### DSC — FAIL-CLOSED

Preflight requires `i915_dsc_fec_support` and DSC sink support on the currently
running Omarchy kernel before any boot changes are staged.

The installed oneshot runs before the display manager. The final boot health
check requires DSC active, force enabled, `bpp=30` and `dither=no`.

Unlike the former Bazzite setup, there is no Fedora SELinux-specific context.

## Static CI checks

`scripts/audit.sh` verifies:

- Bash syntax for every shell script;
- Python syntax;
- no Bazzite/rpm-ostree/dracut/Fedora package logic in scripts;
- no automatic reboot command;
- no package-install command in `install.sh` or `preflight.sh`;
- no Limine/mkinitcpio mutation in `install.sh`;
- source commit/tree and ACPI hashes are pinned;
- DMI guard and no-poll keyboard driver;
- DSC unit ordering;
- official-source URL allowlist;
- ShellCheck warning/error level;
- Git whitespace.

## Residual risks

1. A future `linux-omarchy` kernel can change an internal kernel API used by the
   tiny keyboard module. The service should fail to build rather than load a
   mismatched module.
2. A future kernel can remove/rename the DSC debugfs control. Preflight/health
   check then fail visibly.
3. A future libfprint/fprintd update can become ABI-incompatible with the private
   SDCP build.
4. A BIOS update can change ACPI/EC. Follow `docs/BIOS-UPDATE.md` first.
5. This Omarchy port is statically audited against current official sources but
   must still be live-validated on the actual M1230. The definitive acceptance
   criterion is the first clean-boot `RESULT: OK`.
