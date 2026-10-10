# BIOS / firmware updates

Do not carry the ACPI override across a BIOS update blindly.

## Before flashing

Remove the HONOR ACPI hook from the next boot manually:

```bash
sudo rm -f /usr/lib/firmware/acpi/SSDT27_TPD0.aml
sudo rm -f /etc/mkinitcpio.conf.d/90-honor-m1230.conf
sudo rm -f /etc/initcpio/install/honor_acpi_override
sudo limine-mkinitcpio
```

Inspect, then reboot manually.

## After the BIOS update

Do not restore the old AML yet.

Run:

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./preflight.sh
```

Only if preflight again reports the exact audited stock ACPI bytes should you
repeat the manual ACPI + Limine steps from `docs/INSTALL.md`.

If the bytes changed, stop and re-audit the new firmware.
