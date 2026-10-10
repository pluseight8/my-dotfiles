#!/usr/bin/bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run with sudo"

[[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)" == HONOR ]] || die "not HONOR"
[[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" == ZQC-P ]] || die "not ZQC-P"
[[ "$(cat /sys/class/dmi/id/board_version 2>/dev/null || true)" == M1230 ]] || die "not M1230"

KVER="$(uname -r)"
KDIR="/usr/lib/modules/$KVER/build"
[[ -f "$KDIR/Makefile" ]] || die "matching linux-omarchy-headers missing"

for cmd in gcc make insmod modinfo install grep cp; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing tool: $cmd"
done

DSDT="$(mktemp)"
trap 'rm -f "$DSDT"' EXIT
cat /sys/firmware/acpi/tables/DSDT > "$DSDT"
for symbol in KBBL GKBM SKBM; do
    grep -aq "$symbol" "$DSDT" || die "DSDT symbol $symbol missing; refusing EC writes"
done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC=/var/lib/honor/kbdlight-src
install -d -m755 "$SRC" /usr/local/lib/honor /etc/systemd/system
install -m644 "$HERE/honor_zqcp_kbdlight.c" "$SRC/honor_zqcp_kbdlight.c"
install -m644 "$HERE/Makefile" "$SRC/Makefile"

cat > /usr/local/lib/honor/kbdlight-build-load.sh <<'INNER'
#!/usr/bin/bash
set -euo pipefail

KVER="$(uname -r)"
KDIR="/usr/lib/modules/$KVER/build"
SRC=/var/lib/honor/kbdlight-src
OUT="/var/lib/honor/kbdlight/$KVER"
KO="$OUT/honor_zqcp_kbdlight.ko"
BUILD="$SRC/build-$KVER"

[[ -f "$KDIR/Makefile" ]] || {
    echo "matching kernel headers missing: $KDIR" >&2
    exit 1
}

mkdir -p "$OUT"
need_build=1

if [[ -f "$KO" ]]; then
    vm="$(modinfo -F vermagic "$KO" 2>/dev/null | awk '{print $1}' || true)"
    if [[ "$vm" == "$KVER"        && ! "$SRC/honor_zqcp_kbdlight.c" -nt "$KO"        && ! "$SRC/Makefile" -nt "$KO" ]]; then
        need_build=0
    fi
fi

if ((need_build)); then
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cp "$SRC/honor_zqcp_kbdlight.c" "$BUILD/"
    cp "$SRC/Makefile" "$BUILD/"
    make -C "$BUILD" KVER="$KVER" KDIR="$KDIR"
    install -m644 "$BUILD/honor_zqcp_kbdlight.ko" "$KO"
fi

if grep -q '^honor_zqcp_kbdlight ' /proc/modules 2>/dev/null; then
    rmmod honor_zqcp_kbdlight
fi
insmod "$KO"
[[ -d /sys/class/leds/honor::kbd_backlight ]]
INNER

chmod 755 /usr/local/lib/honor/kbdlight-build-load.sh

cat > /etc/systemd/system/honor-zqcp-kbdlight.service <<'UNIT'
[Unit]
Description=HONOR ZQC-P M1230 keyboard backlight
After=systemd-modules-load.service
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash /usr/local/lib/honor/kbdlight-build-load.sh
RemainAfterExit=yes
ExecStop=-/usr/bin/rmmod honor_zqcp_kbdlight

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable honor-zqcp-kbdlight.service >/dev/null
systemctl restart honor-zqcp-kbdlight.service

[[ -d /sys/class/leds/honor::kbd_backlight ]] || die "LED device did not appear"
echo "HONOR keyboard backlight installed for Omarchy"
echo "Omarchy integration: omarchy-brightness-keyboard cycle"
