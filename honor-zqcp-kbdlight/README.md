# HONOR ZQC-P M1230 keyboard backlight — Omarchy

Small DMI-bound LED-class driver for the keyboard backlight on this exact board.

It registers:

`/sys/class/leds/honor::kbd_backlight`

Omarchy's official `omarchy-brightness-keyboard` helper scans
`/sys/class/leds/*kbd_backlight*`, so this name integrates directly with
Omarchy's existing keyboard-brightness hotkeys.

The systemd service keeps a source copy under `/var/lib/honor/kbdlight-src` and
rebuilds the module when the running kernel release changes.

There is intentionally no periodic EC polling. Firmware-side Fn+Space can change
the physical backlight independently; that is preferable to a permanent polling
loop merely to synchronize UI state.
