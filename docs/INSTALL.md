# Installation on Omarchy

This guide is for the exact **HONOR MagicBook Pro 14 2026 AI, ZQC-P / M1230**.

The setup is split into three explicit phases. None of the scripts reboots the
machine for you.

## 1. Update Omarchy first

From your normal session:

```bash
omarchy-update
```

If the update installed a new kernel, reboot and log back in before continuing:

```bash
systemctl reboot
```

Confirm that the running kernel is an Omarchy kernel and that matching headers
can be installed for it:

```bash
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
```

The pkgbase must start with `linux-omarchy`.

## 2. Keep Secure Boot / kernel lockdown off

This adaptation uses an early ACPI table override and one local out-of-tree
keyboard-backlight module. The installer therefore refuses to continue while
kernel lockdown is active.

Check:

```bash
cat /sys/kernel/security/lockdown 2>/dev/null || true
```

If the file exists, the selected state must be `[none]`.

## 3. Install host dependencies manually

The repository does **not** install packages on your behalf.

Resolve the running kernel package base:

```bash
KERNEL_PKGBASE="$(cat /usr/lib/modules/"$(uname -r)"/pkgbase)"
echo "$KERNEL_PKGBASE"
```

Then install the dependencies:

```bash
sudo pacman -S --needed \
  git \
  base-devel \
  clang \
  bpf \
  udev-hid-bpf \
  curl \
  usbutils \
  fprintd \
  meson \
  ninja \
  pkgconf \
  glib2 \
  libgusb \
  nss \
  libgudev \
  gobject-introspection \
  cairo \
  pixman \
  polkit \
  "${KERNEL_PKGBASE}-headers"
```

If that transaction updates the kernel, reboot once and repeat the pkgbase /
header check before continuing.

## 4. Clone the Omarchy adaptation

Recommended persistent checkout:

```bash
sudo git clone https://github.com/pluseight8/my-dotfiles.git \
  /var/opt/pluseight8-my-dotfiles

sudo chown -R "$USER:$(id -gn)" /var/opt/pluseight8-my-dotfiles
cd /var/opt/pluseight8-my-dotfiles
```

Run the repository audit before touching the machine:

```bash
./scripts/audit.sh
```

The final line must be:

```text
AUDIT RESULT: OK
```

## 5. Preflight

Run:

```bash
sudo ./preflight.sh
```

Read the summary and type `CHECK`.

The preflight:

- verifies exact DMI identity for ZQC-P / M1230;
- verifies the running Omarchy kernel and matching headers;
- refuses Secure-Boot / lockdown states incompatible with this setup;
- checks the live `I2C_DEVT` table against the audited hashes;
- clones the HONOR hardware repository at the pinned commit;
- adds a local **probed** M1230 profile containing only the audited Tier-A fixes.

It does **not** modify the boot configuration.

Expected ending:

```text
PREFLIGHT: OK
```

## 6. Stage the boot fixes

Run:

```bash
sudo ./stage-boot.sh
```

This installs the audited ACPI AML into:

```text
/etc/initcpio/acpi_override/SSDT27_TPD0.aml
```

and adds the official mkinitcpio `acpi_override` hook via:

```text
/etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf
```

It also adds:

```text
xe.enable_psr=1
```

through Omarchy's Limine drop-in interface:

```text
/etc/limine-entry-tool.d/90-honor-m1230.conf
```

Finally it rebuilds the boot entries with:

```bash
limine-mkinitcpio
```

Expected ending:

```text
BOOT STAGE: OK
```

The script deliberately does not reboot.

## 7. Reboot yourself

```bash
systemctl reboot
```

After logging back in:

```bash
cd /var/opt/pluseight8-my-dotfiles
```

## 8. Install runtime fixes

Run:

```bash
sudo ./install.sh
```

Read the summary and type `INSTALL`.

Before installing anything, the script proves that the rebooted system is
actually using the corrected ACPI table and `xe.enable_psr=1`.

It then installs:

- touchscreen mic-mute HID-BPF fix;
- touchpad left-edge brightness HID-BPF fix;
- EgisTec `1c7a:05aa` SDCP libfprint support;
- M1230 keyboard-backlight LED module/service;
- DSC force service for the internal OLED;
- boot health-check timer.

It does **not** install a replacement `xe.ko`.

Expected ending:

```text
RUNTIME INSTALL: OK
```

## 9. Let Omarchy configure fingerprint authentication

Return to your normal user shell and run:

```bash
omarchy-setup-security-fingerprint
```

That is intentionally left to Omarchy because Omarchy owns its own sudo,
polkit and lock-screen fingerprint integration.

## 10. Final verification

Check:

```bash
cat /var/lib/honor/health-last.txt
```

Healthy output ends with:

```text
RESULT: OK
```

Useful direct checks:

```bash
cat /sys/module/xe/parameters/enable_psr
ls -ld /sys/class/leds/honor::kbd_backlight
sudo cat /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support
sudo grep -m1 -E 'pipe src=.*bpp=' /sys/kernel/debug/dri/*/i915_display_info
fprintd-list "$USER"
```

For this panel the intended display state is DSC active, `bpp=30`, and
`dither=no`.

## Updates

Normal Omarchy updates remain normal:

```bash
omarchy-update
```

After a kernel update and reboot, wait about one minute and inspect:

```bash
cat /var/lib/honor/health-last.txt
```

The HID-BPF objects are CO-RE. The keyboard-backlight service rebuilds its
small module against the headers for the kernel that is actually running.

See [UPDATES.md](UPDATES.md), [TROUBLESHOOTING.md](TROUBLESHOOTING.md), and
[BIOS-UPDATE.md](BIOS-UPDATE.md) for the recovery paths.
