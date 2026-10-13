#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

require_root
assert_omarchy
assert_m1230
assert_omarchy_kernel
assert_lockdown_off

[[ -r /etc/honor-m1230.conf ]] || die "/etc/honor-m1230.conf missing; run the main install flow first"
# shellcheck source=/dev/null
source /etc/honor-m1230.conf

[[ -n "${HONOR_USER:-}" ]] || die "HONOR_USER missing from /etc/honor-m1230.conf"
[[ -n "${HONOR_ACPI_PATCHED_MD5:-}" ]] || die "HONOR_ACPI_PATCHED_MD5 missing from /etc/honor-m1230.conf"

[[ -d /opt/honor-libfprint-sdcp ]] || die "fingerprint runtime is not installed yet"
systemctl is-enabled --quiet honor-zqcp-kbdlight.service     || die "keyboard-backlight service is not installed/enabled yet"

log "installing corrected DSC service"
install -d -m755 /usr/local/lib/honor
install -m755 "$ROOT/scripts/force-dsc.sh" /usr/local/lib/honor/force-dsc.sh
install -m644 "$ROOT/systemd/honor-force-dsc.service" /etc/systemd/system/honor-force-dsc.service
systemctl daemon-reload
systemctl enable honor-force-dsc.service >/dev/null
systemctl restart honor-force-dsc.service
systemctl is-active --quiet honor-force-dsc.service     || die "honor-force-dsc.service did not become active"

log "installing health-check timer"
install -m755 "$ROOT/scripts/health-check.sh" /usr/local/lib/honor/health-check.sh
install -m644 "$ROOT/systemd/honor-health-check.service" /etc/systemd/system/honor-health-check.service
install -m644 "$ROOT/systemd/honor-health-check.timer" /etc/systemd/system/honor-health-check.timer
systemctl daemon-reload
systemctl enable --now honor-health-check.timer >/dev/null

log "running health check"
if ! HONOR_ALLOW_PENDING_DSC=1 HONOR_USER="$HONOR_USER" HONOR_ACPI_PATCHED_MD5="$HONOR_ACPI_PATCHED_MD5"     /usr/local/lib/honor/health-check.sh; then
    die "health check failed outside the expected pre-reboot DSC transition; see /var/lib/honor/health-last.txt"
fi

printf 'installed=%s\nkernel=%s\nuser=%s\nomarchy=%s\n'     "$(date --iso-8601=seconds)" "$(uname -r)" "$HONOR_USER" "$(omarchy-version)"     > "$HONOR_STATE_DIR/runtime-install-complete"
chmod 600 "$HONOR_STATE_DIR/runtime-install-complete"

echo
log "RUNTIME RESUME: OK"
echo
echo "DSC force is armed. Reboot once so it is armed before the next Omarchy display modeset:"
echo
echo "  systemctl reboot"
echo
echo "After login, verify:"
echo
echo "  cat /var/lib/honor/health-last.txt"
