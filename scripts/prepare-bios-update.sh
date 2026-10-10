#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"
require_root
assert_bazzite
assert_m1230

cat <<'MSG'
This disables ONLY the HONOR ACPI override before a BIOS update.
After the BIOS update, do not restore the old override blindly. Run:

    sudo ./install.sh --repair --yes

The installer will compare the new firmware I2C_DEVT table against the audited
reference and will refuse to reinstall the override if the BIOS changed it.
MSG

rm -f /etc/honor-magicbook/acpi/SSDT27_TPD0.aml
rm -f /etc/dracut.conf.d/90-honor-acpi.conf
rpm-ostree initramfs --enable

echo 'ACPI override removed from the next deployment. Reboot before flashing BIOS.'
