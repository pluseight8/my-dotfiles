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

is_bazzite() {
    [[ -r /etc/os-release ]] || return 1
    grep -qiE '(^ID=bazzite$|^NAME=.*Bazzite)' /etc/os-release
}

assert_bazzite() {
    is_bazzite || die "this installer is only for Bazzite"
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
    [[ "$board" == "$HONOR_DMI_BOARD" ]] || die "unexpected board: $board"
    [[ "$board_name" == "$HONOR_DMI_BOARD_NAME" ]] || die "unexpected board name: $board_name"
    [[ -z "$sku" || "$sku" == "$HONOR_DMI_SKU" ]] || die "unexpected SKU: $sku"
}

assert_secure_boot_off() {
    require_cmds mokutil
    local sb lockdown
    sb="$(mokutil --sb-state 2>/dev/null || true)"
    lockdown="$(cat /sys/kernel/security/lockdown 2>/dev/null || true)"

    grep -qi 'disabled' <<<"$sb" || die "Secure Boot must be disabled for this tested setup. Current state: ${sb:-unknown}"
    [[ -z "$lockdown" || "$lockdown" == *'[none]'* ]] || die "kernel lockdown is active: $lockdown"
}

assert_selinux_enforcing() {
    local mode
    mode="$(getenforce 2>/dev/null || true)"
    [[ "$mode" == "Enforcing" ]] || die "tested Bazzite path expects SELinux Enforcing; current: ${mode:-unknown}"
}

assert_kernel_build_tree() {
    local kver
    kver="$(uname -r)"
    [[ -f "/lib/modules/$kver/build/Makefile" ]] || die "matching kernel-devel tree missing: /lib/modules/$kver/build"
}

pending_deployment_exists() {
    python3 - <<'PY'
import json, subprocess, sys
try:
    data = json.loads(subprocess.check_output(["rpm-ostree", "status", "--json"], text=True))
except Exception:
    sys.exit(2)
for d in data.get("deployments", []):
    if d.get("staged"):
        sys.exit(0)
sys.exit(1)
PY
}

assert_no_pending_deployment() {
    local rc=0
    pending_deployment_exists || rc=$?
    case "$rc" in
        0) die "rpm-ostree already has a staged deployment. Reboot into it before running this installer." ;;
        1) return 0 ;;
        *) die "could not inspect rpm-ostree deployment state" ;;
    esac
}

state_file="$HONOR_STATE_DIR/install.env"

state_init() {
    install -d -m755 "$HONOR_STATE_DIR"
    touch "$state_file"
    chmod 600 "$state_file"
}

state_set() {
    local key="$1" value="$2" tmp
    state_init
    tmp="$(mktemp "$HONOR_STATE_DIR/.state.XXXXXX")"
    awk -F= -v k="$key" '$1 != k { print }' "$state_file" > "$tmp"
    printf '%s=%q\n' "$key" "$value" >> "$tmp"
    mv -f "$tmp" "$state_file"
    chmod 600 "$state_file"
}

state_get() {
    local key="$1"
    [[ -r "$state_file" ]] || return 1
    # shellcheck source=/dev/null
    source "$state_file"
    printf '%s' "${!key:-}"
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

safe_rm_tree() {
    local path="$1"
    [[ "$path" == /var/opt/* || "$path" == /var/lib/honor-m1230/* ]] || die "refusing unsafe rm -rf: $path"
    [[ "$path" != /var/opt && "$path" != /var/lib/honor-m1230 ]] || die "refusing unsafe rm -rf: $path"
    rm -rf --one-file-system "$path"
}

user_uid() {
    local user="$1"
    id -u "$user"
}

restart_powerdevil_for_user() {
    local user="$1" uid
    uid="$(user_uid "$user")"
    if [[ -S "/run/user/$uid/bus" ]]; then
        runuser -u "$user" -- env \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            systemctl --user restart plasma-powerdevil.service >/dev/null 2>&1 || true
    fi
}

notify_user() {
    local user="$1" message="$2" uid
    uid="$(user_uid "$user")"
    if [[ -S "/run/user/$uid/bus" ]] && command -v notify-send >/dev/null 2>&1; then
        runuser -u "$user" -- env \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            notify-send "HONOR M1230" "$message" >/dev/null 2>&1 || true
    fi
}