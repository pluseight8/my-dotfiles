# Installation

This guide is for a fresh/current **Bazzite KDE** installation on
**HONOR ZQC-P / M1230** only.

The rule is simple:

> **Every command that changes the next boot is run explicitly by you.**

No repository script installs RPM packages. No repository script reboots the
machine. `install.sh` is strictly post-reboot/runtime setup.

---

## 0. Before starting

Keep Secure Boot disabled for this tested setup. Bazzite itself supports Secure
Boot, but this machine setup uses a local ACPI override and a local out-of-tree
keyboard-backlight module. The checks fail closed when kernel lockdown is
active.

If Bazzite has just updated and `rpm-ostree status` shows a staged deployment,
reboot into that deployment before starting.

Check:

```bash
rpm-ostree status
```

---

## 1. Manually install host dependencies

Run this yourself. It calculates what is missing and stages only those RPMs:

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

The repository never runs this transaction for you.

Inspect the staged deployment:

```bash
rpm-ostree status
```

If it looks correct, **you reboot manually**:

```bash
systemctl reboot
```

---

## 2. Clone the Bazzite/HONOR repository

After the dependency reboot:

```bash
sudo git clone https://github.com/pluseight8/my-dotfiles.git \
  /var/opt/pluseight8-my-dotfiles

sudo chown -R "$USER:$(id -gn)" /var/opt/pluseight8-my-dotfiles

cd /var/opt/pluseight8-my-dotfiles
```

If that directory already exists from a previous attempt, do not overwrite it
blindly. Inspect it first.

---

## 3. Run the non-mutating hardware preflight

```bash
sudo ./preflight.sh --yes
```

`preflight.sh` does **not** run `rpm-ostree`, does **not** modify initramfs,
does **not** change kernel arguments, and does **not** reboot.

It only:

- verifies Bazzite;
- verifies DMI is exactly HONOR / ZQC-P / M1230;
- verifies Secure Boot/lockdown state;
- verifies SELinux Enforcing;
- verifies every required host RPM is already installed;
- verifies the matching Bazzite OGC kernel build tree exists;
- clones the HONOR support source at the exact audited commit;
- applies the M1230/Bazzite source adaptations;
- finds the live `I2C_DEVT` ACPI table;
- compares the live table byte-for-byte with the audited stock reference;
- verifies the stock and patched ACPI MD5 values.

Expected end:

```text
PREFLIGHT: OK
```

If preflight does not say `OK`, stop. Do not stage the boot changes.

---

## 4. Manually stage the reboot-required HONOR boot changes

These commands are deliberately **not hidden in a script**.

First pin the currently working deployment:

```bash
sudo ostree admin pin 0
```

Install the already-validated ACPI override into persistent `/etc`:

```bash
sudo install -d -m755 /etc/honor-magicbook/acpi

sudo install -m644 \
  /var/opt/honor-magicbook-linux/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml \
  /etc/honor-magicbook/acpi/SSDT27_TPD0.aml

sudo install -d -m755 /etc/dracut.conf.d

sudo tee /etc/dracut.conf.d/90-honor-acpi.conf >/dev/null <<'EOF'
acpi_override="yes"
acpi_table_dir="/etc/honor-magicbook/acpi"
EOF
```

Now explicitly enable the local initramfs deployment:

```bash
sudo rpm-ostree initramfs --enable
```

Normalize PSR so the next boot has exactly `xe.enable_psr=1`:

```bash
for arg in $(rpm-ostree kargs); do
  case "$arg" in
    xe.enable_psr=*)
      if [ "$arg" != "xe.enable_psr=1" ]; then
        sudo rpm-ostree kargs --delete-if-present="$arg"
      fi
      ;;
  esac
done

sudo rpm-ostree kargs --append-if-missing="xe.enable_psr=1"
```

Inspect everything before rebooting:

```bash
rpm-ostree kargs
rpm-ostree status
```

Only if it looks correct, **you reboot manually**:

```bash
systemctl reboot
```

---

## 5. Post-reboot runtime installation

After login:

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./install.sh --yes
```

This is now a strict rule in the repository:

- `install.sh` contains no `rpm-ostree` command;
- `install.sh` contains no reboot command;
- it refuses to continue if the manually staged ACPI/PSR state is not active.

It verifies:

- ACPI `Table Upgrade` is active;
- no relevant `AE_AML_INTERNAL` returned;
- touchscreen `2808:5662` exists;
- touchpad `27c6:0f9a` exists;
- `xe.enable_psr=1` is active.

Then it installs only runtime/persistent hardware fixes:

- micmute HID-BPF;
- touchpad-edge HID-BPF;
- EgisTec SDCP fingerprint support;
- M1230 keyboard-backlight module/service;
- DSC service;
- boot health-check timer.

It finishes by running the current-boot health check. Expected:

```text
RUNTIME INSTALL: OK
RESULT: OK
```

At this point the fixes are active **without another forced reboot**.

---

## 6. Fingerprint enrollment

The driver is installed automatically, but your finger obviously must be
enrolled interactively as your normal user:

```bash
fprintd-enroll -f right-index-finger
fprintd-verify
```

---

## 7. Final persistence test — reboot only when YOU want

The final reboot is not needed to make the fixes active. It is only the clean
persistence proof that everything comes back by itself.

When you are ready:

```bash
systemctl reboot
```

After login, wait roughly 45–60 seconds and run:

```bash
cat /var/lib/honor/health-last.txt
```

Expected final line:

```text
RESULT: OK
```

If `RESULT: OK`, the setup survived a completely clean boot.

---

## 8. Keyboard backlight behavior

KDE controls the physical keyboard backlight through
`/sys/class/leds/honor::kbd_backlight`.

Firmware `Fn+Space` also changes the physical backlight. They are intentionally
not synchronized through periodic EC polling, so using `Fn+Space` can leave the
visual KDE slider temporarily out of sync. This avoids a permanent polling loop
and unnecessary wakeups.

---

## 9. Updates

After a normal Bazzite update and reboot:

```bash
cat /var/lib/honor/health-last.txt
```

If it says `RESULT: OK`, do nothing.

If a new deployment breaks the machine and the system still boots:

```bash
sudo rpm-ostree rollback
systemctl reboot
```

The package transaction, boot staging, reboots, rollback and package removal
remain explicit user actions by design.
