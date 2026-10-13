# Installation on Omarchy

This guide is for the exact **HONOR MagicBook Pro 14 2026 AI,
ZQC-P / M1230**.

For the easiest path, use the guided installer:

```bash
cd /var/opt/pluseight8-my-dotfiles
./setup.sh
```

It is intentionally a **two-pass** setup because the ACPI override cannot be
validated until after a reboot. The script never reboots the laptop for you.

This document also shows the manual phases in full.

## 0. If the Omarchy USB itself artifacts

Use [OMARCHY-USB-BOOT.md](OMARCHY-USB-BOOT.md). It contains the GRUB commands
used successfully on this exact laptop.

The temporary live-USB workaround is:

```text
nomodeset module_blacklist=xe
```

Do not copy those arguments into the installed system.

## 1. Install and update Omarchy normally

Install Omarchy from the official ISO, boot the installed system and run:

```bash
omarchy-update
```

If that updated the kernel, reboot before continuing:

```bash
systemctl reboot
```

Check:

```bash
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
```

The pkgbase must begin with:

```text
linux-omarchy
```

This repository deliberately stays on that stock Omarchy kernel.

## 2. Secure Boot / lockdown

The ACPI early override and local keyboard-backlight module require kernel
lockdown to be off.

```bash
cat /sys/kernel/security/lockdown 2>/dev/null || true
```

If the file exists, the selected value must be `[none]`.

The scripts refuse to continue if Secure Boot / lockdown is active.

## 3. Clone this repository

Recommended persistent checkout:

```bash
sudo git clone https://github.com/pluseight8/my-dotfiles.git \
  /var/opt/pluseight8-my-dotfiles
sudo chown -R "$USER:$(id -gn)" /var/opt/pluseight8-my-dotfiles
cd /var/opt/pluseight8-my-dotfiles
```

## 4. Recommended: guided setup

Run as your normal user:

```bash
./setup.sh
```

If packages are missing it prints them and asks for exactly:

```text
INSTALL-DEPS
```

The required set includes the dependency that previously broke the SDCP
libfprint build (`glib2-devel`) and the `jq` dependency used by the
post-login DSC helper.

The first pass:

1. validates Omarchy and exact M1230 DMI;
2. validates the stock Omarchy kernel;
3. installs missing host dependencies after confirmation;
4. runs the repository audit;
5. runs the read-only hardware preflight;
6. stages the ACPI and PSR boot fixes;
7. verifies the actual generated UKI contains the audited AML;
8. stops and tells you to reboot.

Reboot yourself:

```bash
systemctl reboot
```

After login, run the same command again:

```bash
cd /var/opt/pluseight8-my-dotfiles
./setup.sh
```

The second pass detects the already-active patched ACPI table and continues with
runtime fixes.

## 5. Manual dependency installation

Skip this section when using `setup.sh`.

Resolve the running kernel package base:

```bash
KERNEL_PKGBASE="$(cat /usr/lib/modules/"$(uname -r)"/pkgbase)"
echo "$KERNEL_PKGBASE"
```

Install:

```bash
sudo pacman -S --needed \
  git \
  base-devel \
  clang \
  bpf \
  udev-hid-bpf \
  curl \
  jq \
  usbutils \
  fprintd \
  meson \
  ninja \
  pkgconf \
  glib2 \
  glib2-devel \
  libgusb \
  nss \
  libgudev \
  gobject-introspection \
  cairo \
  pixman \
  polkit \
  "${KERNEL_PKGBASE}-headers"
```

If the transaction leaves matching headers unavailable for the kernel returned
by `uname -r`, reboot into the newly installed Omarchy kernel and retry.

## 6. Repository audit

```bash
./scripts/audit.sh
```

Expected:

```text
AUDIT RESULT: OK
```

The audit contains regression checks for the installation failures encountered
during the original M1230 bring-up.

## 7. Preflight

```bash
sudo ./preflight.sh
```

Type:

```text
CHECK
```

It verifies:

- exact HONOR / ZQC-P / M1230 identity;
- real Omarchy detection, including `ID=omarchy`;
- official Omarchy kernel pkgbase;
- matching headers;
- lockdown state;
- HID-BPF/BTF support;
- pinned HONOR source commit/tree;
- live `I2C_DEVT` against the audited stock/patched hashes.

Expected:

```text
PREFLIGHT: OK
```

## 8. Stage boot fixes

```bash
sudo ./stage-boot.sh
```

The final ACPI layout is:

```text
/usr/lib/firmware/acpi/SSDT27_TPD0.aml
/etc/initcpio/install/acpi_override
/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
```

The last-sorting mkinitcpio drop-in adds:

```bash
HOOKS+=(acpi_override)
```

The PSR setting is added through Omarchy's supported Limine drop-in:

```text
/etc/limine-entry-tool.d/90-honor-m1230.conf
```

with:

```bash
KERNEL_CMDLINE[default]+=" xe.enable_psr=1"
```

Then `limine-mkinitcpio` rebuilds the Omarchy boot images.

The stage is considered successful only after the script **extracts the early
CPIO from the real generated boot image**, including Omarchy-prefixed UKI names
such as:

```text
/boot/EFI/Linux/omarchy_linux-omarchy.efi
```

and verifies that the exact audited AML is inside it.

Expected:

```text
BOOT STAGE: OK
```

Now reboot yourself:

```bash
systemctl reboot
```

## 9. Runtime install after reboot

After login:

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./install.sh
```

Type:

```text
INSTALL
```

Before installing anything, `install.sh` verifies the **live** ACPI table hash
and `xe.enable_psr=1`. It does not rely on one exact kernel-log phrase.

It installs:

- touchscreen mic-mute HID-BPF;
- touchpad-edge brightness HID-BPF;
- EgisTec `1c7a:05aa` SDCP libfprint support;
- M1230 keyboard-backlight service;
- root DSC force service;
- post-login Hyprland DSC modeset helper;
- boot health-check timer.

It does **not** install a custom kernel or replacement `xe.ko`.

## 10. DSC behavior on stock Omarchy

The stock driver can accept:

```text
Force_DSC_Enable: yes
```

before the current compositor mode has actually switched to DSC.

The root service arms DSC. A user service waits for Omarchy/UWSM's Wayland
session and triggers one short DPMS cycle on the internal `eDP-*` output.

Hyprland may transiently return `7/NOTRUNNING` during that intentional DPMS
transition. The helper therefore verifies the **actual monitor `dpmsStatus`**
instead of treating that transient return code as proof of failure.

Healthy stock-kernel state:

```text
DSC_Enabled: yes
Force_DSC_Enable: yes
bpp=24
dither=no
```

The repository intentionally accepts 8 bpc here to preserve the official
Omarchy kernel/update path.

## 11. Fingerprint enrollment

Hardware support and Omarchy authentication policy are separate.

After the runtime install, as your normal user run:

```bash
omarchy-setup-security-fingerprint
```

Omarchy then owns the sudo/polkit/lock-screen integration.

## 12. Final verification

```bash
cat /var/lib/honor/health-last.txt
```

The final line must be:

```text
RESULT: OK
```

A healthy post-reboot display section should include:

```text
[ OK ] DSC force enabled
[ OK ] DSC active
[ OK ] display: bpp=24 (8 bpc), dither=no on stock Omarchy kernel
```

## 13. Normal updates

Use Omarchy normally:

```bash
omarchy-update
```

After a kernel update/reboot:

```bash
cat /var/lib/honor/health-last.txt
```

No custom kernel rebuild is part of this setup.

See [UPDATES.md](UPDATES.md) and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
