# Troubleshooting

Start with the single report:

```bash
cat /var/lib/honor/health-last.txt
```

Then inspect the installer log:

```bash
sudo less /var/log/honor-m1230-install.log
```

## install.sh says the manual boot stage is not active

`install.sh` does not repair boot state and does not call `rpm-ostree`.

Check the current boot:

```bash
sudo journalctl -k -b --no-pager | \
  grep -iE 'Table Upgrade|I2C_DEVT|AE_AML_INTERNAL|locked down'

cat /sys/module/xe/parameters/enable_psr
```

If the ACPI override is not active or PSR is not `1`, go back to the manual
boot-staging block in `docs/INSTALL.md`, inspect `rpm-ostree status`, and reboot
yourself.
## ACPI override did not load

```bash
sudo journalctl -k -b --no-pager | \
  grep -iE 'Table Upgrade|I2C_DEVT|AE_AML_INTERNAL|locked down'
```

Do not force the override if the installer's live/reference ACPI hashes do not
match.

## Touchscreen or touchpad missing

```bash
ls /sys/bus/hid/devices | grep -iE '2808:5662|27c6:0f9a'
```

If they are absent, fix ACPI first. Do not debug HID-BPF until the physical HID
devices enumerate.

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

If the direct test works but KDE does not, restart UPower and PowerDevil.

## DSC

```bash
systemctl status honor-force-dsc.service --no-pager -l
sudo journalctl -u honor-force-dsc.service -b --no-pager -n 100
```

A healthy state contains:

```text
DSC_Enabled: yes
Force_DSC_Enable: yes
bpp=30
dither=no
```

Do not disable SELinux to make the service work. The shipped unit already uses
the tested per-service SELinux context.

## Fingerprint

Check the USB reader and private library:

```bash
lsusb -d 1c7a:05aa
ldconfig -p | grep /opt/honor-libfprint-sdcp
systemctl status fprintd --no-pager -l
```

If the USB device itself disappears, a complete power-off is more meaningful
than repeatedly rebuilding libfprint.