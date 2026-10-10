# Complete installation guide — Omarchy + HONOR ZQC-P / M1230

This is the clean path from a fresh Omarchy install to the fully working HONOR
setup.

## 1. Install Omarchy itself

Use the **official Omarchy ISO**. Omarchy's official manual documents ISO
installation as the supported route, with full-disk and free-space/dual-boot
modes. Full-disk installation wipes the selected disk; encryption is enabled by
default.

Official pages:

- https://omarchy.org/
- https://omarchy.org/manual/getting-started/

At the time this port was written, the official site offered **Omarchy 4.0.4**.

Before installing, disable Secure Boot and TPM as required by Omarchy's official
getting-started guide.

For this laptop, use a clean ISO installation rather than trying to convert an
existing Bazzite filesystem into Arch/Omarchy.

Finish Omarchy's first-boot owner setup and reach the desktop.

## 2. Update Omarchy first

Use Omarchy's own updater:

```bash
omarchy update
```

Do not substitute a direct `pacman -Syu`. Omarchy's official update flow handles
packages, migrations, configuration updates and the pre-update snapshot
together.

If Omarchy asks for a reboot because its kernel or desktop changed, finish that
update and boot the new state before continuing.

Verify:

```bash
omarchy-version
uname -r
pacman -Q linux-omarchy linux-omarchy-headers
```

## 3. Install extra host dependencies manually

Run this yourself:

```bash
sudo pacman -S --needed --ask 4 \
  base-devel git clang linux-omarchy-headers \
  bpf udev-hid-bpf \
  meson ninja pkgconf \
  glib2 libgusb nss libgudev gobject-introspection cairo pixman polkit \
  libfprint-git fprintd usbutils
```

Omarchy's own fingerprint setup uses `--ask 4` when installing
`libfprint-git` because it can replace stock `libfprint`.

No script in this repository runs that package transaction.

## 4. Clone this repository

```bash
sudo git clone https://github.com/pluseight8/my-dotfiles.git \
  /var/opt/pluseight8-my-dotfiles

sudo chown -R "$USER:$(id -gn)" /var/opt/pluseight8-my-dotfiles

cd /var/opt/pluseight8-my-dotfiles
```

## 5. Run the preflight

```bash
sudo ./preflight.sh
```

Type `CHECK`.

Preflight does not change Limine, initramfs, kernel command line or reboot. It
verifies the exact M1230 DMI, lockdown state, dependencies, matching Omarchy
kernel headers/BTF, pinned HONOR source, exact live ACPI bytes, keyboard EC
symbols and DSC debugfs support.

Expected end:

```text
PREFLIGHT: OK
```

If it does not say `OK`, stop.

## 6. Manually stage ACPI + PSR for the next boot

### 6.1 Install the validated AML

```bash
sudo install -Dm644 \
  /var/opt/honor-magicbook-linux/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml \
  /usr/lib/firmware/acpi/SSDT27_TPD0.aml
```

### 6.2 Install the mkinitcpio early-CPIO hook

```bash
sudo install -Dm644 \
  /var/opt/pluseight8-my-dotfiles/mkinitcpio/honor_acpi_override.install \
  /etc/initcpio/install/honor_acpi_override

sudo tee /etc/mkinitcpio.conf.d/90-honor-m1230.conf >/dev/null <<'EOF'
HOOKS+=(honor_acpi_override)
EOF
```

The hook uses mkinitcpio's `add_file_early` so the AML is placed at
`/kernel/firmware/acpi/SSDT27_TPD0.aml` in the early CPIO.

### 6.3 Add PSR1 through Omarchy's Limine drop-in mechanism

```bash
sudo tee /etc/limine-entry-tool.d/90-honor-m1230.conf >/dev/null <<'EOF'
# HONOR ZQC-P M1230
KERNEL_CMDLINE[default]+=" xe.enable_psr=1"
EOF
```

### 6.4 Rebuild through Omarchy's own wrapper

```bash
sudo limine-mkinitcpio
```

Inspect before reboot:

```bash
cat /etc/mkinitcpio.conf.d/90-honor-m1230.conf
cat /etc/limine-entry-tool.d/90-honor-m1230.conf
ls -l /usr/lib/firmware/acpi/SSDT27_TPD0.aml
```

Then **you** reboot:

```bash
systemctl reboot
```

## 7. Verify the boot

```bash
sudo journalctl -k -b --no-pager | \
  grep -iE 'Table Upgrade|I2C_DEVT|AE_AML_INTERNAL|locked down'

ls /sys/bus/hid/devices | grep -iE '2808:5662|27C6:0F9A'

cat /sys/module/xe/parameters/enable_psr
```

Good state: ACPI table upgrade is logged, no relevant `AE_AML_INTERNAL`, both
HID IDs exist, and PSR prints `1`.

## 8. Run the post-reboot runtime installer

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./install.sh
```

Type `INSTALL`.

`install.sh` does not call `pacman`, `mkinitcpio`, `limine-mkinitcpio` or
`systemctl reboot`. It only verifies the active boot state and installs the
runtime/persistent fixes:

1. micmute HID-BPF;
2. touchpad left-edge brightness HID-BPF;
3. private EgisTec SDCP libfprint under `/opt/honor-libfprint-sdcp`;
4. M1230 keyboard-backlight module/service;
5. DSC force service;
6. boot health-check timer.

Expected end:

```text
RUNTIME INSTALL: OK
RESULT: OK
```

The pre-reboot health pass permits DSC to be forced but not yet active; the
final clean boot is the strict DSC/10-bit proof.

## 9. Keyboard backlight — native Omarchy integration

The driver creates:

```text
/sys/class/leds/honor::kbd_backlight
```

Omarchy's official `omarchy-brightness-keyboard` searches
`/sys/class/leds/*kbd_backlight*`, so no Hyprland or Quickshell patch is
required.

Test:

```bash
omarchy-brightness-keyboard cycle
omarchy-brightness-keyboard cycle
```

The normal Omarchy keyboard-backlight hotkeys use the same helper.

Firmware `Fn+Space` may still change the physical level independently. We do
not poll EC just to visually synchronize state.

## 10. Fingerprint — use Omarchy's official security setup

Our installer supplies the missing EgisTec ET171/SDCP driver. Enrollment and
PAM/lock policy should remain Omarchy-native:

```bash
omarchy-setup-security-fingerprint
```

Omarchy enrolls and verifies first, then configures sudo, polkit and its lock
screen.

## 11. Final persistence test

When you are ready:

```bash
systemctl reboot
```

Do not run an HONOR helper manually after this reboot. Wait ~60 seconds:

```bash
cat /var/lib/honor/health-last.txt
```

Target:

```text
RESULT: OK
```

The detailed report must include ACPI override active, touchscreen/touchpad,
PSR1, both HID-BPF objects, keyboard-backlight service/LED, DSC force + active,
`bpp=30`, `dither=no`, fingerprint USB and private SDCP libfprint.

Only after this result is the Omarchy port live-validated on the laptop.

## 12. Updates

Use:

```bash
omarchy update
```

Omarchy's official updater creates its update snapshot and runs migrations and
configuration updates. After a kernel update and reboot, wait ~60 seconds and
check:

```bash
cat /var/lib/honor/health-last.txt
```

If it is `RESULT: OK`, do nothing. See `docs/UPDATES.md` if not.
