# Updates and rollback

Use Omarchy's supported update path:

```bash
omarchy update
```

Do not replace it with a direct `pacman -Syu`. Omarchy's official update flow
takes a system snapshot and runs the Omarchy package/migration/configuration
steps together.

## After an update

If Omarchy asks for a reboot, reboot when ready. Then wait about one minute:

```bash
cat /var/lib/honor/health-last.txt
```

If the last line is:

```text
RESULT: OK
```

do nothing.

## What should survive

- ACPI AML + mkinitcpio hook/drop-in;
- Limine `xe.enable_psr=1` drop-in;
- HID-BPF objects and micmute re-apply service;
- private EgisTec libfprint under `/opt`;
- keyboard-backlight source + service;
- DSC service;
- health-check timer.

The keyboard module is rebuilt at boot if the running kernel release changed.

## If an update breaks it

Omarchy's official update path takes a snapshot before the update. Use the
Limine boot menu to boot the snapshot from before the bad update, then restore
that snapshot using Omarchy's snapshot tooling.

For diagnostics before rollback:

```bash
cat /var/lib/honor/health-last.txt
sudo journalctl -u honor-zqcp-kbdlight.service -b --no-pager
sudo journalctl -u honor-force-dsc.service -b --no-pager
```

## Firmware/BIOS is different

A BIOS update can change ACPI/EC behavior even when Omarchy itself is unchanged.
Follow `docs/BIOS-UPDATE.md` before flashing firmware.
