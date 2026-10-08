# HONOR ZQC-P M1230 keyboard backlight for Bazzite

Minimal out-of-tree GPL-2.0 LED-class driver adapted from
`drphilth/honor-magicbook-pro-14-ubuntu`'s `honor-fmbp-kbdlight`.

Restricted to:

- `HONOR`
- `ZQC-P`
- board `M1230`

The ZQC-P DSDT exposes EC field `KBBL` at offset `0x41`.
The mapping independently documented in the rs0x29a HONOR Linux repo is:

- `0x04` off
- `0x02` low
- `0x03` high
- `0x01` latch

The installer also refuses to continue unless the running DSDT contains
`KBBL`, `GKBM`, and `SKBM`.

The driver registers `honor::kbd_backlight`, so UPower/KDE can control it
without colliding with a broken/future `huawei::kbd_backlight`.

It reads the current EC value at module load and does not change physical
brightness until userspace writes a new level.

On Bazzite, the module and source live under `/var/lib/honor`, not immutable
`/usr/lib/modules`. A systemd service rebuilds it for the running kernel when
necessary, using the matching Bazzite kernel-devel tree.

References:

- https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010
- https://github.com/drphilth/honor-magicbook-pro-14-ubuntu

## Bazzite updates

Keep `gcc` and `make` installed on the host. The boot service recompiles the
out-of-tree module when `uname -r` changes. Removing those build tools would
make the automatic rebuild fail after a future kernel update.

Other temporary build dependencies used for HID-BPF or libfprint are not needed
by this module at runtime.

## Verified on M1230

Direct LED-class control is confirmed to change the physical keyboard
backlight:

```bash
echo 0 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness
echo 1 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness
echo 2 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness
```

If direct sysfs control works but the KDE slider does not, restart the
userspace power stack so it can rediscover the newly-created LED:

```bash
sudo systemctl restart upower.service
systemctl --user restart plasma-powerdevil.service
```

If KDE still uses the wrong backend, inspect:

```bash
busctl tree org.freedesktop.UPower | grep -i KbdBacklight
ls -1 /sys/class/leds
```

## Fn+Space synchronization

The M1230 firmware changes EC `KBBL` directly when the physical keyboard
backlight shortcut is used. That means a normal LED-class driver can control
the light from KDE, but its cached logical level becomes stale after Fn+Space.

The driver now polls `KBBL` every 200 ms (module parameter `poll_ms`) and
enables `LED_BRIGHT_HW_CHANGED`. When the EC changes between the documented
`off / low / high` values, the driver updates its logical brightness and calls
`led_classdev_notify_brightness_hw_changed()`.

UPower watches the LED-class hardware-brightness notification and relays it to
desktop power managers. This is the standard path used to keep firmware
keyboard-backlight keys and a desktop slider synchronized.

The special EC value `0x01` means "latch current level" and does not encode
which level is active, so the driver keeps the last known logical value while
KBBL is latched.

After installing this version, verify:

```bash
ls /sys/class/leds/honor::kbd_backlight/brightness_hw_changed
cat /sys/class/leds/honor::kbd_backlight/brightness
```

Then press Fn+Space and watch:

```bash
watch -n 0.2 cat /sys/class/leds/honor::kbd_backlight/brightness
```

The value should follow the physical shortcut as `0 / 1 / 2`.

If sysfs follows Fn+Space but KDE does not refresh, restart UPower and PowerDevil:

```bash
sudo systemctl restart upower.service
systemctl --user restart plasma-powerdevil.service
```
