#!/usr/bin/bash
set -euo pipefail

COMMON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$COMMON_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/config/m1230.env"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "run this command with sudo"
}

require_cmds() {
    local missing=() cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    ((${#missing[@]} == 0)) || die "missing command(s): ${missing[*]}"
}

assert_omarchy() {
    command -v omarchy >/dev/null 2>&1 || die "Omarchy CLI not found"
    [[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] || die "/usr/share/omarchy is missing; use a supported Omarchy ISO installation"
    command -v pacman >/dev/null 2>&1 || die "pacman missing; this is not the expected Omarchy/Arch host"
    command -v limine-mkinitcpio >/dev/null 2>&1 || die "limine-mkinitcpio missing; update Omarchy before continuing"
}

read_dmi() {
    local name="$1"
    tr -d '\r\n' < "/sys/class/dmi/id/$name" 2>/dev/null || true
}

assert_m1230() {
    local vendor product board board_name sku
    vendor="$(read_dmi sys_vendor)"
    product="$(read_dmi product_name)"
    board="$(read_dmi board_version)"
    board_name="$(read_dmi board_name)"
    sku="$(read_dmi product_sku)"

    [[ "$vendor" == "$HONOR_DMI_VENDOR" ]] || die "unexpected vendor: $vendor"
    [[ "$product" == "$HONOR_DMI_PRODUCT" ]] || die "unexpected product: $product"
    [[ "$board" == "$HONOR_DMI_BOARD" ]] || die "unexpected board version: $board"
    [[ "$board_name" == "$HONOR_DMI_BOARD_NAME" ]] || die "unexpected board name: $board_name"
    [[ -z "$sku" || "$sku" == "$HONOR_DMI_SKU" ]] || die "unexpected SKU: $sku"
}

assert_lockdown_off() {
    local lockdown
    lockdown="$(cat /sys/kernel/security/lockdown 2>/dev/null || true)"
    [[ -z "$lockdown" || "$lockdown" == *'[none]'* ]] || die "kernel lockdown is active: $lockdown"
}

assert_kernel_build_tree() {
    local kver
    kver="$(uname -r)"
    [[ -f "/usr/lib/modules/$kver/build/Makefile" ]] || die "matching kernel headers missing: /usr/lib/modules/$kver/build"
    pacman -Q linux-omarchy-headers >/dev/null 2>&1 || die "linux-omarchy-headers package missing"
}

REQUIRED_PACKAGES=(
    base-devel
    git
    clang
    bpf
    udev-hid-bpf
    meson
    ninja
    pkgconf
    glib2
    libgusb
    nss
    libgudev
    gobject-introspection
    cairo
    pixman
    polkit
    fprintd
    libfprint-git
    usbutils
    linux-omarchy-headers
)

assert_dependencies_present() {
    local missing=() pkg
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        printf 'Missing package(s):\n' >&2
        printf '  %s\n' "${missing[@]}" >&2
        die "install dependencies manually as documented in docs/INSTALL.md"
    fi
}

retry() {
    local attempts="$1" delay="$2"
    shift 2
    local i
    for ((i=1; i<=attempts; i++)); do
        if "$@"; then
            return 0
        fi
        if ((i < attempts)); then
            warn "attempt $i/$attempts failed; retrying in ${delay}s: $*"
            sleep "$delay"
        fi
    done
    return 1
}

safe_rm_tree() {
    local path="$1"
    [[ "$path" == /var/opt/* ]] || die "refusing unsafe rm -rf: $path"
    [[ "$path" != /var/opt ]] || die "refusing unsafe rm -rf: $path"
    rm -rf --one-file-system "$path"
}

restart_user_shell() {
    local user="$1" uid
    uid="$(id -u "$user")"
    if [[ -S "/run/user/$uid/bus" ]] && command -v omarchy-restart-shell >/dev/null 2>&1; then
        runuser -u "$user" -- env \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            omarchy-restart-shell >/dev/null 2>&1 || true
    fi
}
