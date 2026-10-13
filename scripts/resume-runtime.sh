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

log "installing post-login DSC modeset helper"
install -m755 "$ROOT/scripts/dsc-modeset-user.sh" /usr/local/lib/honor/dsc-modeset-user.sh
install -m644 "$ROOT/systemd/honor-dsc-modeset.service" /etc/systemd/user/honor-dsc-modeset.service

USER_HOME="$(getent passwd "$HONOR_USER" | cut -d: -f6)"
USER_UID="$(id -u "$HONOR_USER")"
USER_GROUP="$(id -gn "$HONOR_USER")"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || die "cannot resolve home for $HONOR_USER"
install -d -m755 -o "$HONOR_USER" -g "$USER_GROUP" "$USER_HOME/.config/systemd/user/graphical-session.target.wants"
ln -sfn /etc/systemd/user/honor-dsc-modeset.service     "$USER_HOME/.config/systemd/user/graphical-session.target.wants/honor-dsc-modeset.service"
chown -h "$HONOR_USER:$USER_GROUP"     "$USER_HOME/.config/systemd/user/graphical-session.target.wants/honor-dsc-modeset.service"

USER_SYSTEMCTL=(runuser -u "$HONOR_USER" -- env     XDG_RUNTIME_DIR="/run/user/$USER_UID"     DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"     systemctl --user)
if [[ -S "/run/user/$USER_UID/bus" ]]; then
    "${USER_SYSTEMCTL[@]}" daemon-reload
    "${USER_SYSTEMCTL[@]}" restart honor-dsc-modeset.service || true
    sleep 2
fi

log "installing health-check timer"
install -m755 "$ROOT/scripts/health-check.sh" /usr/local/lib/honor/health-check.sh
install -m644 "$ROOT/systemd/honor-health-check.service" /etc/systemd/system/honor-health-check.service
install -m644 "$ROOT/systemd/honor-health-check.timer" /etc/systemd/system/honor-health-check.timer
systemctl daemon-reload
systemctl enable --now honor-health-check.timer >/dev/null

log "running health check"
if ! HONOR_ALLOW_PENDING_DSC="$ALLOW_PENDING_DSC" HONOR_USER="$HONOR_USER" HONOR_ACPI_PATCHED_MD5="$HONOR_ACPI_PATCHED_MD5"     /usr/local/lib/honor/health-check.sh; then
    die "health check failed outside the expected pre-reboot DSC transition; see /var/lib/honor/health-last.txt"
fi

printf 'installed=%s\nkernel=%s\nuser=%s\nomarchy=%s\n'     "$(date --iso-8601=seconds)" "$(uname -r)" "$HONOR_USER" "$(omarchy-version)"     > "$HONOR_STATE_DIR/runtime-install-complete"
chmod 600 "$HONOR_STATE_DIR/runtime-install-complete"

echo
log "RUNTIME RESUME: OK"
echo
echo "The stock Omarchy kernel is kept intact."
echo "A tiny user service now triggers one eDP modeset after graphical login so"
echo "the already-armed DSC setting is actually applied."
echo
echo "Verify any time with:"
echo
echo "  cat /var/lib/honor/health-last.txt"
