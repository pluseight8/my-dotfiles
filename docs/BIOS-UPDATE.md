# BIOS updates

A BIOS update can change ACPI tables even when the retail model name stays the
same. The M1230 setup therefore treats BIOS changes separately from ordinary
Omarchy updates.

## Before flashing BIOS

Remove the ACPI override from the next boot:

```bash
sudo rm -f /etc/initcpio/acpi_override/SSDT27_TPD0.aml
sudo rm -f /etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf
sudo limine-mkinitcpio
```

Reboot yourself:

```bash
systemctl reboot
```

Confirm the old override is no longer loaded:

```bash
sudo journalctl -k -b --no-pager | grep -i 'Table Upgrade'
```

Only then flash/update the BIOS.

The PSR Limine drop-in does not need to be removed merely to flash firmware; it
is a kernel parameter, not firmware data.

## After the BIOS update

Do **not** restore the old AML blindly.

Update the local checkout if desired, then run the read-only preflight:

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./preflight.sh --yes
```

If the new live `I2C_DEVT` bytes still match the audited stock reference,
`preflight.sh` will say `PREFLIGHT: OK`. Then stage the override again:

```bash
sudo ./stage-boot.sh
systemctl reboot
```

After the reboot:

```bash
sudo ./install.sh --yes
```

If the ACPI hash changed, stop. The new firmware needs a fresh audit before the
old corrected table is trusted again.
