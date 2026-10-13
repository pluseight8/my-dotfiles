# Troubleshooting

Start with the machine-wide health result:

```bash
cat /var/lib/honor/health-last.txt
```

Then inspect the install log when the failure happened during setup:

```bash
sudo less /var/log/honor-m1230-install.log
```

The guided installer is safe to rerun:

```bash
cd /var/opt/pluseight8-my-dotfiles
./setup.sh
```

It detects whether the live ACPI table is still stock or already patched and
continues from the appropriate phase.

## Omarchy ISO artifacts before the installer

Use [OMARCHY-USB-BOOT.md](OMARCHY-USB-BOOT.md).

The proven live-USB-only workaround is:

```text
nomodeset module_blacklist=xe
```

Do not add those parameters to the installed Omarchy system.

## `preflight.sh` says this is not Omarchy

Current Omarchy reports its own OS ID. The repository explicitly accepts
`ID=omarchy` as well as Arch-compatible `ID_LIKE` values.

Check:

```bash
cat /etc/os-release
omarchy-version
pacman -Q omarchy
```

If this fails on an otherwise normal Omarchy install, update this repository
before changing the detection logic by hand.

## Wrong machine / DMI refusal

Print:

```bash
for f in sys_vendor product_name board_version board_name product_sku; do
  printf '%-16s ' "$f"
  cat "/sys/class/dmi/id/$f"
done
```

This repository intentionally targets only the audited
`HONOR / ZQC-P / M1230 / ZQC-P-PCB` state.

## Secure Boot / lockdown refusal

```bash
cat /sys/kernel/security/lockdown 2>/dev/null || true
```

The selected state must be `[none]`.

Do not patch the guard out. The ACPI table override and unsigned local
keyboard-backlight module are exactly the operations kernel lockdown is meant
to restrict.

## Missing dependencies

Use the guided installer:

```bash
./setup.sh
```

It installs missing packages only after explicit confirmation.

Two dependencies that are easy to miss manually are:

```text
glib2-devel
jq
```

`glib2-devel` is required by the SDCP libfprint Meson build; `jq` is used
by the post-login Hyprland DSC helper.

## Kernel headers do not match the running kernel

Check:

```bash
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
test -e /usr/lib/modules/"$(uname -r)"/build/Makefile && echo headers-ok
```

If an update installed a new kernel/headers but you are still running the old
kernel, reboot once and rerun `./setup.sh`.

Do not build a module against headers for a different running kernel.

## ACPI hash mismatch

The live table must equal either the audited stock hash or the exact patched
hash.

Do not use a force flag and do not copy a random M1010 AML by hand. A different
hash can mean different firmware and requires a fresh audit.

## ACPI override did not load after reboot

The persistent files are:

```text
/usr/lib/firmware/acpi/SSDT27_TPD0.aml
/etc/initcpio/install/acpi_override
/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
```

Check:

```bash
sudo md5sum /usr/lib/firmware/acpi/SSDT27_TPD0.aml
cat /etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
```

Re-run:

```bash
sudo ./stage-boot.sh
```

Do not trust only a kernel-log phrase. The installer and health check use the
**live ACPI table hash** as the authoritative test.

### If `stage-boot.sh` says the rebuilt image does not contain the AML

Do not reboot.

The script verifies the real generated UKI by extracting its early CPIO. It
also discovers Omarchy-prefixed UKIs such as:

```text
/boot/EFI/Linux/omarchy_linux-omarchy.efi
```

If verification fails, collect:

```bash
ls -l /boot/EFI/Linux/
cat /etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
ls -l /usr/lib/firmware/acpi/SSDT27_TPD0.aml
```

and inspect the full `stage-boot.sh` output before rebooting.

## `xe.enable_psr` is not 1

```bash
cat /sys/module/xe/parameters/enable_psr
grep -R "enable_psr" /etc/default/limine /etc/limine-entry-tool.d 2>/dev/null
```

The repository owns:

```text
/etc/limine-entry-tool.d/90-honor-m1230.conf
```

There must not be a conflicting second `xe.enable_psr=` or
`i915.enable_psr=` setting.

After resolving a conflict:

```bash
sudo limine-mkinitcpio
systemctl reboot
```

## Touchscreen or touchpad missing

```bash
ls /sys/bus/hid/devices | grep -iE '2808:5662|27c6:0f9a'
```

If the devices are absent, fix the ACPI stage first. HID-BPF cannot attach to a
device that did not enumerate.

## Phantom KEY_MICMUTE returned

```bash
systemctl status honor-hid-bpf-reapply.service --no-pager -l
grep -l UNKNOWN /sys/class/input/input*/name | xargs -r grep -H 2808
```

The second command should print nothing.

## Touchpad left-edge brightness gesture

```bash
sudo udev-hid-bpf list-loaded
ls -l /etc/udev-hid-bpf/
```

If only this component needs repair:

```bash
sudo env ALLOW_UNVERIFIED=1 \
  bash /var/opt/honor-magicbook-linux/patch/touchpad-edge/install.sh
```

## Keyboard backlight

```bash
systemctl status honor-zqcp-kbdlight.service --no-pager -l
ls -ld /sys/class/leds/honor::kbd_backlight
```

Direct test:

```bash
echo 0 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness
sleep 1
echo 2 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness
```

After a kernel update, if the service fails, verify matching headers and restart:

```bash
test -e /usr/lib/modules/"$(uname -r)"/build/Makefile && echo headers-ok
sudo systemctl restart honor-zqcp-kbdlight.service
```

## DSC is armed but not active

Check root-side state:

```bash
sudo cat /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support
```

Healthy state contains:

```text
DSC_Enabled: yes
Force_DSC_Enable: yes
```

The root service only **arms** DSC. The post-login user service performs one
Hyprland-owned DPMS cycle so a new modeset actually uses DSC.

Check it as your normal desktop user:

```bash
systemctl --user status honor-dsc-modeset.service --no-pager -l
journalctl --user -u honor-dsc-modeset.service -b --no-pager -n 100
```

Or use the sudo-safe one-command diagnostic:

```bash
sudo ./scripts/diagnose-dsc-session.sh
```

The helper waits for Omarchy/UWSM's Wayland environment and can recover
`HYPRLAND_INSTANCE_SIGNATURE` from the live runtime directory.

Hyprland may briefly return:

```text
status=7/NOTRUNNING
```

during the intentional DPMS transition. That return code alone is **not** a
failure. The helper validates the actual monitor `dpmsStatus` afterward.

## Display is `bpp=24, dither=no`

That is accepted and expected on the **stock Omarchy kernel** for this setup:

```text
DSC active
bpp=24 (8 bpc)
dither=no
```

Do not install a custom kernel just to make the health check say 10 bpc. The
repository intentionally prioritizes normal Omarchy kernel updates.

## Display is still `bpp=18, dither=yes`

That usually means DSC was armed but no new compositor modeset happened yet.

Check:

```bash
systemctl --user status honor-dsc-modeset.service --no-pager -l
sudo ./scripts/diagnose-dsc-session.sh
```

Then refresh the installed helper:

```bash
sudo ./scripts/resume-runtime.sh
```

A brief one-second display blank during the DPMS cycle is expected.

## Fingerprint build fails at Meson setup

First ensure:

```bash
pacman -Q glib2-devel
command -v glib-mkenums
```

Then rerun:

```bash
./setup.sh
```

The runtime installer is designed to be rerunnable.

## Fingerprint driver is installed but authentication is not configured

Check:

```bash
lsusb -d 1c7a:05aa
ldconfig -p | grep /opt/honor-libfprint-sdcp
fprintd-list "$USER"
```

Then let Omarchy own the authentication policy:

```bash
omarchy-setup-security-fingerprint
```

## Diagnostic scripts

DSC root/debugfs state:

```bash
sudo ./scripts/diagnose-dsc.sh
```

DSC user-session/UWSM/Hyprland state:

```bash
sudo ./scripts/diagnose-dsc-session.sh
```

Both scripts are committed executable; if Git reports otherwise, update the
checkout before troubleshooting permissions manually.
