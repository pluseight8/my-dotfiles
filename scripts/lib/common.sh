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
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    ((${#missing[@]} == 0)) || die "missing command(s): ${missing[*]}"
}

read_dmi() {
    local name="$1"
    tr -d '\r\n' < "/sys/class/dmi/id/$name" 2>/dev/null || true
}

assert_omarchy() {
    require_cmds pacman omarchy-version limine-mkinitcpio
    [[ -r /etc/os-release ]] || die "/etc/os-release missing"
    local id
    id="$(. /etc/os-release; printf '%s' "${ID:-}")"
    [[ "$id" == arch ]] || die "this adaptation is for Omarchy/Arch; /etc/os-release ID=$id"
    pacman -Q omarchy >/dev/null 2>&1 \
        || die "the Omarchy package is not installed"
}

assert_m1230() {
    local vendor product board board_name sku
    vendor="$(read_dmi sys_vendor)"
    product="$(read_dmi product_name)"
    board="$(read_dmi board_version)"
    board_name="$(read_dmi board_name)"
    sku="$(read_dmi product_sku)"

    [[ "$vendor" == "$HONOR_DMI_VENDOR" ]] || die "unexpected vendor: ${vendor:-empty}"
    [[ "$product" == "$HONOR_DMI_PRODUCT" ]] || die "unexpected product: ${product:-empty}"
    [[ "$board" == "$HONOR_DMI_BOARD" ]] || die "unexpected board revision: ${board:-empty}"
    [[ "$board_name" == "$HONOR_DMI_BOARD_NAME" ]] || die "unexpected board name: ${board_name:-empty}"
    [[ -z "$sku" || "$sku" == "$HONOR_DMI_SKU" ]] || die "unexpected SKU: $sku"
}

assert_lockdown_off() {
    local lockdown=""
    if [[ -r /sys/kernel/security/lockdown ]]; then
        lockdown="$(cat /sys/kernel/security/lockdown)"
        [[ "$lockdown" == *'[none]'* ]] \
            || die "kernel lockdown is active: $lockdown. The ACPI override and unsigned local keyboard module are not supported in this state."
    fi

    # The EFI variable is authoritative when readable. Byte 4 is the payload.
    local efivar=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
    if [[ -r "$efivar" ]]; then
        local sb
        sb="$(od -An -t u1 -j 4 -N 1 "$efivar" 2>/dev/null | tr -d ' ' || true)"
        [[ "$sb" != 1 ]] || die "Secure Boot is enabled. Disable it before using this hardware adaptation."
    fi
}

running_kernel_pkgbase() {
    local kver="${1:-$(uname -r)}"
    if [[ -r "/usr/lib/modules/$kver/pkgbase" ]]; then
        cat "/usr/lib/modules/$kver/pkgbase"
    elif [[ -r "/lib/modules/$kver/pkgbase" ]]; then
        cat "/lib/modules/$kver/pkgbase"
    else
        return 1
    fi
}

assert_omarchy_kernel() {
    local kver pkgbase
    kver="$(uname -r)"
    pkgbase="$(running_kernel_pkgbase "$kver" 2>/dev/null || true)"
    [[ "$pkgbase" == linux-omarchy* ]] \
        || die "running kernel '$kver' is not an Omarchy kernel (pkgbase=${pkgbase:-unknown})"
}

assert_matching_headers() {
    local kver
    kver="$(uname -r)"
    [[ -f "/usr/lib/modules/$kver/build/Makefile" || -f "/lib/modules/$kver/build/Makefile" ]] \
        || die "matching headers are missing for $kver. On the default kernel install linux-omarchy-headers, reboot if the kernel was just updated, then retry."
}

REQUIRED_HOST_PACKAGES=(
    git
    base-devel
    clang
    bpf
    udev-hid-bpf
    curl
    usbutils
    fprintd
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
)

assert_host_dependencies_present() {
    require_cmds pacman
    local missing=() pkg
    for pkg in "${REQUIRED_HOST_PACKAGES[@]}"; do
        pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        printf 'Missing host package(s):\n' >&2
        printf '  %s\n' "${missing[@]}" >&2
        die "install them manually with pacman, then run this command again. See docs/INSTALL.md"
    fi
}

find_live_i2c_devt() {
    local f oem
    for f in /sys/firmware/acpi/tables/SSDT*; do
        [[ -e "$f" ]] || continue
        oem="$(dd if="$f" bs=1 skip=16 count=8 status=none 2>/dev/null | tr -d '\0 ' || true)"
        if [[ "$oem" == I2C_DEVT ]]; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

current_i2c_hash() {
    local live
    live="$(find_live_i2c_devt)" || return 1
    md5sum "$live" | awk '{print $1}'
}

assert_acpi_known() {
    local live_hash stock patched
    live_hash="$(current_i2c_hash)" || die "live I2C_DEVT ACPI table not found"
    stock="$HONOR_UPSTREAM_DIR/dump/acpi/zqc-p/SSDT27_orig.aml"
    patched="$HONOR_UPSTREAM_DIR/patch/acpi-override/zqc-p/M1010/SSDT27_TPD0.aml"
    [[ -f "$stock" && -f "$patched" ]] || die "pinned ACPI reference files missing"

    local stock_hash patched_hash
    stock_hash="$(md5sum "$stock" | awk '{print $1}')"
    patched_hash="$(md5sum "$patched" | awk '{print $1}')"
    [[ "$stock_hash" == "$HONOR_ACPI_STOCK_MD5" ]] || die "pinned stock ACPI hash changed: $stock_hash"
    [[ "$patched_hash" == "$HONOR_ACPI_PATCHED_MD5" ]] || die "pinned patched ACPI hash changed: $patched_hash"

    if [[ "$live_hash" == "$stock_hash" ]]; then
        printf 'stock\n'
    elif [[ "$live_hash" == "$patched_hash" ]]; then
        printf 'patched\n'
    else
        die "live I2C_DEVT is unknown: $live_hash. Refusing to use an ACPI table built for different firmware."
    fi
}

assert_hid_bpf_kernel_support() {
    [[ -r /sys/kernel/btf/vmlinux ]] || die "/sys/kernel/btf/vmlinux missing; the running kernel needs BTF"
    if [[ -r /proc/config.gz ]]; then
        zgrep -q '^CONFIG_HID_BPF=y$' /proc/config.gz \
            || die "running kernel does not have CONFIG_HID_BPF=y"
    elif [[ -r "/usr/lib/modules/$(uname -r)/build/.config" ]]; then
        grep -q '^CONFIG_HID_BPF=y$' "/usr/lib/modules/$(uname -r)/build/.config" \
            || die "running kernel does not have CONFIG_HID_BPF=y"
    else
        warn "could not read the running kernel config; HID-BPF support will be checked again by the upstream installers"
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
        if (( i < attempts )); then
            warn "attempt $i/$attempts failed; retrying in ${delay}s: $*"
            sleep "$delay"
        fi
    done
    return 1
}
