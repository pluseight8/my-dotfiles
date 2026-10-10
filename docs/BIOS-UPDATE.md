# BIOS updates

A BIOS update is treated as a firmware change, not a normal Bazzite update.
The exact `I2C_DEVT` ACPI bytes can change even when the retail model name
stays the same.

This repository deliberately has **no script** that silently stages a reboot
for a BIOS update. You perform every boot-affecting command yourself.

## Before flashing BIOS

Remove only the HONOR ACPI override files:

```bash
sudo rm -f /etc/honor-magicbook/acpi/SSDT27_TPD0.aml
sudo rm -f /etc/dracut.conf.d/90-honor-acpi.conf
```

Regenerate/stage the local initramfs deployment yourself:

```bash
sudo rpm-ostree initramfs --enable
rpm-ostree status
```

Inspect the staged deployment. If it is correct, reboot yourself:

```bash
systemctl reboot
```

Only then flash/update BIOS.

## After the BIOS update

Do **not** copy the old ACPI override back blindly.

Run the non-mutating preflight:

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./preflight.sh --yes
```

If preflight still reports exact ACPI reference matches, repeat the manual
boot-staging block from `docs/INSTALL.md`, inspect `rpm-ostree status`, and
reboot yourself. If the bytes changed, stop and re-audit the new firmware
before restoring any ACPI override.
