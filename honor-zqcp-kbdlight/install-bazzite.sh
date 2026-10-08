#!/usr/bin/bash
set -euo pipefail

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run with sudo"

VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
BOARD="$(cat /sys/class/dmi/id/board_version 2>/dev/null || true)"

[[ "$VENDOR" == "HONOR" ]] || die "unexpected vendor: $VENDOR"
[[ "$PRODUCT" == "ZQC-P" ]] || die "unexpected product: $PRODUCT"
[[ "$BOARD" == "M1230" ]] || die "unexpected board version: $BOARD"

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"

[[ -e "$KDIR/Makefile" ]] || die "matching kernel-devel tree missing: $KDIR"

for cmd in gcc make insmod modinfo grep cp install; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing tool: $cmd"
done

DSDT="$(mktemp)"
trap 'rm -f "$DSDT"' EXIT
cat /sys/firmware/acpi/tables/DSDT > "$DSDT"

for symbol in KBBL GKBM SKBM; do
    grep -aq "$symbol" "$DSDT" || die "DSDT symbol $symbol not found; refusing EC writes"
done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="/var/lib/honor/kbdlight-src"
OUT="/var/lib/honor/kbdlight/$KVER"

install -d -m755 "$SRC" "$OUT" /usr/local/lib/honor /etc/systemd/system
install -m644 "$HERE/honor_zqcp_kbdlight.c" "$SRC/honor_zqcp_kbdlight.c"
install -m644 "$HERE/Makefile" "$SRC/Makefile"

cat > /usr/local/lib/honor/kbdlight-build-load.sh <<'EOF'
#!/usr/bin/bash
set -euo pipefail

KVER="$(uname -r)"
KDIR="/lib/modules/$KVER/build"
SRC="/var/lib/honor/kbdlight-src"
OUT="/var/lib/honor/kbdlight/$KVER"
KO="$OUT/honor_zqcp_kbdlight.ko"
BUILD="$SRC/build-$KVER"

[[ -e "$KDIR/Makefile" ]] || {
    echo "HONOR kbdlight: missing $KDIR" >&2
    exit 1
}

mkdir -p "$OUT"

NEED_BUILD=1
if [[ -f "$KO" ]]; then
    VM="$(modinfo -F vermagic "$KO" 2>/dev/null | awk '{print $1}' || true)"
    [[ "$VM" == "$KVER" ]] && NEED_BUILD=0
fi

if (( NEED_BUILD )); then
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cp "$SRC/honor_zqcp_kbdlight.c" "$BUILD/"
    cp "$SRC/Makefile" "$BUILD/"
    make -C "$BUILD" KVER="$KVER" KDIR="$KDIR"
    install -m644 "$BUILD/honor_zqcp_kbdlight.ko" "$KO"
fi

# Fedora/Bazzite SELinux: systemd_t may only load kernel modules carrying
# modules_object_t. Files created under /var/lib would otherwise inherit
# var_lib_t and insmod from the systemd service is denied with AVC module_load.
if command -v chcon >/dev/null 2>&1; then
    chcon -t modules_object_t "$KO" || {
        echo "HONOR kbdlight: failed to set SELinux module label on $KO" >&2
        exit 1
    }
fi

if ! grep -q '^honor_zqcp_kbdlight ' /proc/modules 2>/dev/null; then
    insmod "$KO"
fi

[[ -d /sys/class/leds/honor::kbd_backlight ]] || {
    echo "HONOR kbdlight: module loaded but LED device did not appear" >&2
    exit 1
}
EOF

chmod 755 /usr/local/lib/honor/kbdlight-build-load.sh

cat > /etc/systemd/system/honor-zqcp-kbdlight.service <<'EOF'
[Unit]
Description=HONOR ZQC-P M1230 keyboard backlight
After=systemd-modules-load.service
Before=upower.service display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/honor/kbdlight-build-load.sh
RemainAfterExit=yes
ExecStop=-/usr/sbin/rmmod honor_zqcp_kbdlight

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now honor-zqcp-kbdlight.service

systemctl try-restart upower.service >/dev/null 2>&1 || true

echo
echo "Installed."
echo
echo "LED device:"
ls -ld /sys/class/leds/honor::kbd_backlight
echo
echo "Current / max:"
cat /sys/class/leds/honor::kbd_backlight/brightness
cat /sys/class/leds/honor::kbd_backlight/max_brightness
echo
echo "Direct test:"
echo "  echo 0 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness"
echo "  echo 1 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness"
echo "  echo 2 | sudo tee /sys/class/leds/honor::kbd_backlight/brightness"
echo
echo "If KDE does not refresh immediately, log out and log back in once."
echo "The boot service rebuilds for a new kernel when matching kernel-devel is available."