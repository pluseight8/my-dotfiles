# Troubleshooting

Start with:

```bash
cat /var/lib/honor/health-last.txt
```

Then:

```bash
sudo less /var/log/honor-m1230-install.log
```

## ACPI/touch devices

```bash
sudo journalctl -k -b --no-pager | \
  grep -iE 'Table Upgrade|I2C_DEVT|AE_AML_INTERNAL|locked down'

ls /sys/bus/hid/devices | grep -iE '2808:5662|27C6:0F9A'
```

If the HID devices are missing, fix ACPI before touching HID-BPF.

## PSR

```bash
cat /sys/module/xe/parameters/enable_psr
cat /etc/limine-entry-tool.d/90-honor-m1230.conf
```

Expected runtime value: `1`.

## HID-BPF

```bash
test -f /etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o && echo micmute-ok
test -f /etc/udev-hid-bpf/honor-tops0102-edge.bpf.o && echo edge-ok
systemctl status honor-hid-bpf-reapply.service --no-pager -l
udev-hid-bpf list-devices
```

Do not use the obsolete `list-loaded` command.

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

Omarchy test:

```bash
omarchy-brightness-keyboard cycle
```

## DSC

```bash
systemctl status honor-force-dsc.service --no-pager -l
sudo journalctl -u honor-force-dsc.service -b --no-pager -n 100
```

Then:

```bash
DSC_FILE=$(sudo find /sys/kernel/debug/dri \
  -path '*/eDP-*/i915_dsc_fec_support' -print -quit)
sudo cat "$DSC_FILE"

DISPLAY_INFO=$(sudo find /sys/kernel/debug/dri -name i915_display_info -print -quit)
sudo grep -m1 -E 'pipe src=.*bpp=' "$DISPLAY_INFO"
```

Final healthy boot: DSC enabled/forced, `bpp=30`, `dither=no`.

## Fingerprint

```bash
lsusb -d 1c7a:05aa
ldconfig -p | grep /opt/honor-libfprint-sdcp
systemctl status fprintd --no-pager -l
```

Then use Omarchy's own flow:

```bash
omarchy-setup-security-fingerprint
```
