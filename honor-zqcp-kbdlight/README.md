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
