# Installation

This guide is for a fresh/current Bazzite KDE installation on HONOR ZQC-P board
M1230. It is intentionally not portable to another HONOR model.

## 0. Before starting

Keep Secure Boot disabled for this setup. Bazzite itself supports Secure Boot,
but this repository deliberately uses a local ACPI override plus a local
out-of-tree kernel module. The installer checks `mokutil` and kernel lockdown
and stops rather than silently installing a partially working setup.

Make sure there is no pending rpm-ostree deployment. If Bazzite has just updated,
reboot into the newest deployment first.

## 1. Dependencies — one host transaction

Bazzite's documentation recommends minimizing package layering, but these tools
must run against the host kernel / udev / PAM stack. For this personal machine
we keep the build tools by default so a future `--repair` or kernel-module
rebuild does not first require reconstructing the build environment. They do not
run in the background. If you later want the smallest possible layered set, use
`scripts/cleanup-dependencies.sh`; it removes only temporary packages that the
repo can prove it added.

If this repository is already cloned, use the ownership-aware helper:

```bash
sudo ./prepare-dependencies.sh
```

It installs missing dependencies and reboots automatically.

For a brand-new machine where the repo is not cloned yet, the equivalent raw
host transaction is:

```bash
sudo rpm-ostree install \
  git udev-hid-bpf fprintd fprintd-pam authselect gcc make mokutil \
  clang bpftool libbpf-devel curl meson ninja-build pkgconf-pkg-config \
  glib2-devel libgusb-devel nss-devel libgudev-devel \
  gobject-introspection-devel cairo-devel pixman-devel polkit-devel usbutils \
&& systemctl reboot
```

The Bazzite image already carries its matching OGC `kernel-devel`; the installer
verifies `/lib/modules/$(uname -r)/build` and refuses to substitute a random
Fedora kernel-devel package.

## 2. Clone this repository

After the dependency reboot:

```bash
sudo git clone https://github.com/pluseight8/my-dotfiles.git \
  /var/opt/pluseight8-my-dotfiles
sudo chown -R "$USER:$(id -gn)" /var/opt/pluseight8-my-dotfiles
cd /var/opt/pluseight8-my-dotfiles
```

## 3. One command

```bash
sudo ./install.sh --yes
```

From this point the installer manages the required reboots itself.

### Stage 1

The script:

1. verifies Bazzite, DMI, Secure Boot/lockdown, SELinux and matching kernel build
   tree;
2. pins the current deployment as an emergency rollback point;
3. clones the HONOR hardware-support source at an exact audited commit;
4. applies only the M1230/Bazzite adaptations used on the tested machine;
5. compares the live `I2C_DEVT` ACPI table byte-for-byte against the pinned stock
   reference;
6. verifies both known ACPI MD5s;
7. installs the patched ACPI table into `/etc/honor-magicbook/acpi`;
8. enables rpm-ostree local initramfs generation;
9. sets only `xe.enable_psr=1` for PSR;
10. installs a temporary resume service and reboots.

### Stage 2

After reboot, systemd resumes automatically after the display manager and
network are available. It first proves the ACPI override really loaded and both
HID devices exist. Only then it installs:

- touchscreen micmute HID-BPF;
- touchpad left-edge brightness HID-BPF;
- EgisTec SDCP fingerprint support;
- M1230 keyboard-backlight kernel module;
- DSC service;
- boot health-check timer.

It restarts UPower and, when your user bus exists, KDE PowerDevil. Build
dependencies are deliberately kept for future repairs. Then the machine reboots
once more.

### Stage 3

After the final reboot the resume service runs the full health check. It only
marks installation complete when every required check passes. The expected end
is:

```text
RESULT: OK
```

The result is always saved at:

```bash
cat /var/lib/honor/health-last.txt
```

## 4. Fingerprint enrollment

The driver installation is automatic. Enrolling a finger cannot be automated
because the hardware physically needs multiple touches. Run once as your normal
user:

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
```

`authselect enable-feature with-fingerprint` is attempted automatically during
installation.

## 5. Keyboard backlight behavior

KDE's keyboard-backlight slider controls `honor::kbd_backlight` and changes the
physical backlight. Firmware `Fn+Space` also changes the physical backlight.
They are intentionally not kept visually synchronized by periodic EC polling;
that avoids a permanent wakeup loop just to move a UI slider.


## 6. Optional dependency cleanup

If you prefer minimal `rpm-ostree` layering after everything has been stable for
a while:

```bash
sudo ./scripts/cleanup-dependencies.sh
```

This removes only build-only packages that `prepare-dependencies.sh` recorded as
being added by this repo. `git`, `udev-hid-bpf`, fingerprint/PAM support, `gcc`
and `make` are retained. If you later run a full `--repair`, rerun
`prepare-dependencies.sh` first if a required build tool is missing.
