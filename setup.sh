#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

YES=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) YES=1 ;;
        --help|-h)
            cat <<'HELP'
Usage: ./setup.sh [--yes]

Guided two-pass setup for HONOR ZQC-P/M1230 on Omarchy.

Pass 1:
  - checks the exact machine and stock Omarchy kernel;
  - installs missing host dependencies after one explicit confirmation;
  - runs the repository audit and preflight;
  - stages ACPI/PSR boot fixes;
  - stops and tells you to reboot.

Pass 2, after reboot:
  - detects the active patched ACPI table;
  - installs runtime HID-BPF, fingerprint, keyboard-backlight and DSC fixes;
  - refreshes the post-login DSC helper and health checks.

This script never reboots the laptop automatically.
HELP
            exit 0
            ;;
        *) die "unknown argument: $arg" ;;
    esac
done

[[ ${EUID:-$(id -u)} -ne 0 ]] || die "run ./setup.sh as your normal Omarchy user, not with sudo"

require_cmds sudo pacman git
assert_omarchy
assert_m1230
assert_omarchy_kernel
assert_lockdown_off

KERNEL_PKGBASE="$(running_kernel_pkgbase)"
[[ -n "$KERNEL_PKGBASE" ]] || die "could not determine running kernel pkgbase"

deps=("${REQUIRED_HOST_PACKAGES[@]}" "${KERNEL_PKGBASE}-headers")
missing=()
for pkg in "${deps[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done

if (("${#missing[@]}" > 0)); then
    echo "Missing required packages:"
    printf '  %s\n' "${missing[@]}"
    echo
    if (( YES )); then
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    else
        read -r -p "Install these packages now? Type INSTALL-DEPS: " answer
        [[ "$answer" == INSTALL-DEPS ]] || die "cancelled before dependency installation"
        sudo pacman -S --needed "${missing[@]}"
    fi
fi

if [[ ! -f "/usr/lib/modules/$(uname -r)/build/Makefile" && ! -f "/lib/modules/$(uname -r)/build/Makefile" ]]; then
    cat >&2 <<EOF
ERROR: matching headers are still not available for the running kernel:
  $(uname -r)

An Omarchy/kernel update may have installed a newer kernel and matching headers
without booting it yet. Reboot once, then run:

  cd "$ROOT"
  ./setup.sh
EOF
    exit 2
fi

log "running repository regression audit"
"$ROOT/scripts/audit.sh"

log "running hardware/firmware preflight"
sudo "$ROOT/preflight.sh" --yes

COMMON_Q="$(printf '%q' "$ROOT/scripts/lib/common.sh")"
live_hash="$(sudo bash -c "source $COMMON_Q; current_i2c_hash")"

if [[ "$live_hash" == "$HONOR_ACPI_STOCK_MD5" ]]; then
    log "stock ACPI is active; staging boot fixes"
    sudo "$ROOT/stage-boot.sh"

    echo
    echo "============================================================"
    echo "BOOT FIXES STAGED SUCCESSFULLY"
    echo "============================================================"
    echo
    echo "Reboot yourself now:"
    echo
    echo "  systemctl reboot"
    echo
    echo "After logging back into Omarchy, run the SAME command again:"
    echo
    echo "  cd $ROOT"
    echo "  ./setup.sh"
    echo
    echo "The script will detect the patched boot automatically."
    exit 0
fi

[[ "$live_hash" == "$HONOR_ACPI_PATCHED_MD5" ]]     || die "unexpected live I2C_DEVT hash: $live_hash"

log "patched ACPI is active; continuing with runtime setup"

if ! sudo test -f "$HONOR_STATE_DIR/runtime-install-complete"; then
    sudo "$ROOT/install.sh" --yes
else
    log "runtime install marker already exists; refreshing services and checks"
fi

sudo "$ROOT/scripts/resume-runtime.sh"

echo
echo "============================================================"
echo "HONOR M1230 / OMARCHY SETUP COMPLETE"
echo "============================================================"
echo
cat /var/lib/honor/health-last.txt 2>/dev/null || sudo cat /var/lib/honor/health-last.txt

echo
if fprintd-list "$USER" 2>&1 | grep -qi 'No fingers enrolled'; then
    echo "Fingerprint hardware works, but no finger is enrolled yet."
    echo "Run Omarchy's own security setup as your NORMAL user:"
    echo
    echo "  omarchy-setup-security-fingerprint"
    echo
fi

echo "Normal future updates stay stock Omarchy:"
echo
echo "  omarchy-update"
echo
echo "After a kernel update/reboot, verify with:"
echo
echo "  cat /var/lib/honor/health-last.txt"
