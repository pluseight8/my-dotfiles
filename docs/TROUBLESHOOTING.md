# Troubleshooting

Start with:

```bash
cat /var/lib/honor/health-last.txt
```

Then inspect:

```bash
sudo less /var/log/honor-m1230-install.log
```

## `preflight.sh` refuses the machine

Print the identity:

```bash
for f in sys_vendor product_name board_version board_name product_sku; do
  printf '%-16s ' "$f"
  cat "/sys/class/dmi/id/$f"
done
```

This repository is intentionally restricted to `HONOR / ZQC-P / M1230`.

## Lockdown / Secure Boot refusal

Check:

```bash
cat /sys/kernel/security/lockdown 2>/dev/null || true
```

The selected state must be `[none]`. Do not patch the scripts to bypass this:
the ACPI override and local keyboard module are exactly the kinds of operations
lockdown is intended to restrict.

## ACPI hash mismatch

Do not use `FORCE_ACPI=1` and do not copy the M1010 table by hand.

The preflight accepts only the audited stock M1230-equivalent `I2C_DEVT` bytes
or the exact patched bytes. A different hash means the firmware changed or this
is not the same hardware state the patch was derived from.

## ACPI override did not load

Check:

```bash
sudo journalctl -k -b --no-pager | \
  grep -iE 'Table Upgrade|I2C_DEVT|AE_AML_INTERNAL|locked down'
```

Check the staged files:

```bash
md5sum /etc/initcpio/acpi_override/SSDT27_TPD0.aml
cat /etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf
```

Rebuild explicitly:

```bash
sudo limine-mkinitcpio
```

Then reboot yourself.

## `xe.enable_psr` is not `1`

Check:

```bash
cat /etc/limine-entry-tool.d/90-honor-m1230.conf
grep -R "enable_psr" /etc/default/limine /etc/limine-entry-tool.d 2>/dev/null
cat /sys/module/xe/parameters/enable_psr
```

There must not be a second conflicting `xe.enable_psr=` or
`i915.enable_psr=` setting.

After correcting the conflict:

```bash
sudo limine-mkinitcpio
systemctl reboot
```

## Touchscreen or touchpad missing

```bash
ls /sys/bus/hid/devices | grep -iE '2808:5662|27c6:0f9a'
```

If the devices are absent, fix ACPI first. HID-BPF cannot attach to a device
that never enumerated.

## Phantom KEY_MICMUTE came back

```bash
systemctl status honor-hid-bpf-reapply.service --no-pager -l
grep -l UNKNOWN /sys/class/input/input*/name | xargs -r grep -H 2808
```

The second command should print nothing.

## Touchpad left-edge brightness gesture does not work

```bash
sudo udev-hid-bpf list-loaded
ls -l /etc/udev-hid-bpf/
```

Re-run only that upstream installer:

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

If a kernel update caused the service to fail, check matching headers:

```bash
uname -r
test -e /usr/lib/modules/"$(uname -r)"/build/Makefile && echo headers-ok
```

Then:

```bash
sudo systemctl restart honor-zqcp-kbdlight.service
```

## DSC

```bash
systemctl status honor-force-dsc.service --no-pager -l
sudo journalctl -u honor-force-dsc.service -b --no-pager -n 100
sudo cat /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support
```

Healthy output contains:

```text
DSC_Enabled: yes
Force_DSC_Enable: yes
```

Display depth:

```bash
sudo grep -m1 -E 'pipe src=.*bpp=' \
  /sys/kernel/debug/dri/*/i915_display_info
```

The intended state is `bpp=30` and `dither=no`.

## Boot-time graphical artifacts

First check whether the installed system is fully updated:

```bash
uname -r
pacman -Q linux-omarchy linux-omarchy-bore 2>/dev/null || true
```

The reviewed current Omarchy kernel is based on Linux 7.2.8, which already
contains the stable Panther Lake CDCLK sanitization fix that the older HONOR
repository carried as a custom `xe.ko` patch.

Also check the current boot log:

```bash
sudo journalctl -k -b --no-pager | \
  grep -iE 'FIFO underrun|cdclk|xe.*ERROR|drm.*ERROR'
```

Do not install a vanilla-built `xe.ko` on top of the Omarchy kernel just to
chase an artifact.

## Fingerprint

Check the USB reader:

```bash
lsusb -d 1c7a:05aa
```

Check the private library:

```bash
ldconfig -p | grep /opt/honor-libfprint-sdcp
systemctl status fprintd --no-pager -l
```

Test:

```bash
fprintd-list "$USER"
fprintd-verify
```

If the driver works but Omarchy authentication is not configured:

```bash
omarchy-setup-security-fingerprint
```
