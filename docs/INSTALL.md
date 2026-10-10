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

## 1. BEFORE THE FIRST REBOOT — you run everything manually

There is deliberately **no dependency installer script**. The HONOR installer
does not execute `rpm-ostree install` and does not reboot the dependency
deployment for you.

Run this block yourself. It builds the package list, detects what is actually
missing on the current Bazzite image, and only then stages those packages:

```bash
PKGS=(
  git
  udev-hid-bpf
  fprintd
  fprintd-pam
  authselect
  gcc
  make
  mokutil
  clang
  bpftool
  libbpf-devel
  meson
  ninja-build
  pkgconf-pkg-config
  glib2-devel
  libgusb-devel
  nss-devel
  libgudev-devel
  gobject-introspection-devel
  cairo-devel
  pixman-devel
  polkit-devel
  usbutils
)

MISSING=()
for pkg in "${PKGS[@]}"; do
  rpm -q "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done

printf 'Missing packages: %s\n' "${MISSING[*]:-(none)}"

if ((${#MISSING[@]})); then
  sudo rpm-ostree install "${MISSING[@]}"
fi
```

Nothing in this repository runs that transaction for you.

Now inspect what rpm-ostree staged:

```bash
rpm-ostree status
```

If the new deployment looks correct, **you reboot manually**:

```bash
systemctl reboot
```

Bazzite requires a reboot for layered packages to become part of the active
deployment. The Bazzite image already carries its matching OGC `kernel-devel`;
the installer verifies `/lib/modules/$(uname -r)/build/Makefile` and refuses to
substitute a random Fedora kernel-devel package.
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

At startup the installer verifies that all required host packages are already
present. If anything is missing, it exits with a list; it never installs the
package for you. From this point it manages only the hardware setup and the
reboots required to validate it.

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

It restarts UPower and, when your user bus exists, KDE PowerDevil. The host
packages you installed manually are left untouched. Then the machine reboots
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


## 6. Package ownership

Because you explicitly install the rpm-ostree packages yourself, the repository
does not automatically uninstall them later either. Package layering stays a
manual user decision in both directions.

Inspect layered packages with:

```bash
rpm-ostree status
```

If you later want to remove particular build dependencies, do it yourself with
`rpm-ostree uninstall <package...>` and reboot. Keep `gcc` and `make` if you
want the keyboard-backlight module to rebuild itself after a future kernel
change.
