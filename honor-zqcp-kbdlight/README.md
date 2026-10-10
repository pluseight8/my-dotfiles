# HONOR ZQC-P M1230 keyboard backlight

Small out-of-tree LED-class driver used by this Bazzite setup. It is DMI-bound
to `HONOR / ZQC-P / M1230`, checks the firmware DSDT for `KBBL/GKBM/SKBM`, and
registers `honor::kbd_backlight` so UPower/KDE can control the physical keyboard
backlight.

The boot service rebuilds the module when `uname -r` changes and labels the new
`.ko` as `modules_object_t` before `insmod`, which is required by SELinux on the
tested Bazzite system.

There is intentionally no periodic EC polling. `Fn+Space` remains firmware-side
and may not visually move the KDE slider; the slider itself still controls the
hardware.
