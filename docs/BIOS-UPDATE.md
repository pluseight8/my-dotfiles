# BIOS updates

A BIOS update can change ACPI tables even if the retail laptop model name stays
the same. The M1230 setup therefore treats BIOS changes separately from normal
Omarchy updates.

## Before flashing BIOS

Remove the staged ACPI override from the next boot:

```bash
sudo rm -f /usr/lib/firmware/acpi/SSDT27_TPD0.aml
sudo rm -f /etc/initcpio/install/acpi_override
sudo rm -f /etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
sudo limine-mkinitcpio
```

Reboot yourself:

```bash
systemctl reboot
```

Confirm the live ACPI state is no longer the patched hash before flashing.

The PSR Limine drop-in does not need to be removed merely for a BIOS update; it
is a kernel argument, not firmware data.

## After the BIOS update

Do **not** restore the old AML blindly.

Update this checkout and rerun the read-only preflight:

```bash
cd /var/opt/pluseight8-my-dotfiles
git pull --ff-only
sudo ./preflight.sh --yes
```

If the live `I2C_DEVT` still matches the audited stock table, preflight ends
with:

```text
PREFLIGHT: OK
```

Then use the normal guided flow:

```bash
./setup.sh
```

It will stage the override and stop for the required reboot.

If the new BIOS changes the live ACPI hash, stop. The firmware needs a fresh
audit before the old patched AML is trusted again.
