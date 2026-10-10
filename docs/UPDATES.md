# Updates and rollback

Bazzite Desktop images update automatically. The setup is designed to survive a
normal image deployment change.

## Expected to persist

- files under `/etc` and `/var`;
- the ACPI override configuration;
- `xe.enable_psr=1` kernel argument;
- HID-BPF objects and micmute re-apply service;
- private fingerprint library under `/opt`;
- DSC service/helper;
- keyboard-backlight source/helper;
- boot health check.

The keyboard-backlight `.ko` is kernel-release-specific. Its service compares
`vermagic` with the running kernel and recompiles when needed using Bazzite's
matching kernel-devel tree.

## After an update

Wait roughly one minute after boot, then:

```bash
cat /var/lib/honor/health-last.txt
```

If it says `RESULT: OK`, do nothing.

## If an update breaks the machine

Bazzite documents rollback through the boot menu or rpm-ostree. If the current
system still boots:

```bash
sudo rpm-ostree rollback
systemctl reboot
```

The installer also attempts to pin the deployment that existed before hardware
changes so it remains available as an additional recovery point.

## BIOS updates

Treat BIOS updates separately from Bazzite updates. This setup intentionally
checks exact ACPI bytes because firmware can change tables and EC behavior. Do
not assume a new BIOS is compatible with the old ACPI override merely because
the model name is unchanged.
