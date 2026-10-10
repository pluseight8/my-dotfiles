#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

require_root
assert_bazzite
assert_m1230
assert_no_pending_deployment
require_cmds rpm rpm-ostree python3

# Keep only what the installed system really needs after setup. Everything else
# is deliberately temporary because Bazzite's official docs recommend keeping
# rpm-ostree layering to a minimum.
PERSISTENT=(
    git
    udev-hid-bpf
    fprintd
    fprintd-pam
    authselect
    gcc
    make
    mokutil
)

TEMPORARY=(
    clang
    bpftool
    libbpf-devel
    curl
    meson
    ninja-build
    pkgconf-pkg-config
    glib2-devel
    libgusb-devel
    nss-devel
    libgudev-devel
    gobject-introspection-devel
    cairo-devel
    pixman-devel
    polkit-devel
    usbutils
)

ALL=("${PERSISTENT[@]}" "${TEMPORARY[@]}")
MISSING=()
for pkg in "${ALL[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done

install -d -m755 "$HONOR_STATE_DIR"
printf '%s\n' "${PERSISTENT[@]}" > "$HONOR_STATE_DIR/persistent-deps.txt"
printf '%s\n' "${TEMPORARY[@]}" > "$HONOR_STATE_DIR/temporary-deps.txt"

if ((${#MISSING[@]} == 0)); then
    : > "$HONOR_STATE_DIR/deps-added.txt"
    log "all dependencies are already present; no rpm-ostree deployment needed"
    exit 0
fi

printf '%s\n' "${MISSING[@]}" > "$HONOR_STATE_DIR/deps-added.txt"
log "layering only missing host-level dependencies: ${MISSING[*]}"

rpm-ostree install "${MISSING[@]}"

cat <<'MSG'

Dependencies are staged in a new Bazzite deployment.
The machine will reboot now. After login, clone this repository and run:

    sudo ./install.sh --yes

MSG

systemctl reboot
