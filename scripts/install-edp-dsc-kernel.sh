#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/common.sh"

[[ ${EUID:-$(id -u)} -ne 0 ]] || die "run this script as your normal user, not with sudo"

assert_omarchy
assert_m1230
assert_omarchy_kernel
assert_lockdown_off
require_cmds git pacman makepkg patch sed awk df nproc

INSTALLED="$(pacman -Q linux-omarchy 2>/dev/null | awk '{print $2}')"
[[ "$INSTALLED" == "7.2.5-3" ]] || die "this audited kernel recipe is pinned to linux-omarchy 7.2.5-3; installed: ${INSTALLED:-missing}"

OMARCHY_PKGS_COMMIT="b9a3863787f53c84954ed7b3154d68b35cb2094b"
OMARCHY_PKGS_URL="https://github.com/omacom/omarchy-pkgs.git"
PATCH="$ROOT/patches/0990-honor-m1230-edp-dsc.patch"
WORK="${XDG_CACHE_HOME:-$HOME/.cache}/honor-m1230/linux-omarchy-7.2.5-3-edp-dsc"
PKGDIR="$WORK/pkg"
GNUPGHOME="$WORK/gnupg"

[[ -f "$PATCH" ]] || die "HONOR eDP DSC patch missing: $PATCH"

FREE_KB="$(df -Pk "${XDG_CACHE_HOME:-$HOME/.cache}" 2>/dev/null | awk 'NR==2 {print $4}')"
if [[ -n "$FREE_KB" && "$FREE_KB" -lt 31457280 ]]; then
    die "at least 30 GiB free space is required for a full Omarchy kernel build"
fi

DEPS=(
    base-devel
    bc
    binutils
    cpio
    gettext
    glibc
    libelf
    libgcc
    openssl
    pahole
    perl
    python
    rust
    rust-bindgen
    rust-src
    tar
    xxhash
    xz
    zlib
    zstd
    gnupg
)

MISSING=()
for pkg in "${DEPS[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done

cat <<EOF
This will build a local linux-omarchy 7.2.5-3.1 kernel using the exact
Omarchy 7.2.5-3 package recipe plus the audited HONOR eDP DSC preference
patch. It is a full kernel build and can take a while.

It does NOT reboot automatically.
EOF

if (("${#MISSING[@]}" > 0)); then
    echo
    echo "Missing build packages:"
    printf '  %s\n' "${MISSING[@]}"
    echo
    read -r -p "Install these packages with pacman now? Type INSTALL-DEPS: " answer
    [[ "$answer" == "INSTALL-DEPS" ]] || die "cancelled before dependency installation"
    sudo pacman -S --needed "${MISSING[@]}"
fi

read -r -p "Build and install the patched kernel? Type BUILD-KERNEL: " answer
[[ "$answer" == "BUILD-KERNEL" ]] || die "cancelled"

rm -rf "$WORK"
mkdir -p "$WORK"

log "cloning the pinned Omarchy package source"
git clone --filter=blob:none --no-checkout "$OMARCHY_PKGS_URL" "$WORK/omarchy-pkgs"
git -C "$WORK/omarchy-pkgs" checkout --detach "$OMARCHY_PKGS_COMMIT"
[[ "$(git -C "$WORK/omarchy-pkgs" rev-parse HEAD)" == "$OMARCHY_PKGS_COMMIT" ]] \
    || die "Omarchy package source pin mismatch"

cp -a "$WORK/omarchy-pkgs/pkgbuilds/linux-omarchy" "$PKGDIR"
cp "$PATCH" "$PKGDIR/0990-honor-m1230-edp-dsc.patch"

cd "$PKGDIR"

grep -q '^pkgver=7\.2\.5$' PKGBUILD || die "unexpected Omarchy PKGBUILD version"
grep -q '^pkgrel=3$' PKGBUILD || die "unexpected Omarchy PKGBUILD release"
sed -i 's/^pkgrel=3$/pkgrel=3.1/' PKGBUILD

cat >> PKGBUILD <<'PKGEOF'

# HONOR ZQC-P/M1230 local eDP quality fix.
source+=(0990-honor-m1230-edp-dsc.patch)
b2sums+=(SKIP)
sha256sums+=(SKIP)
PKGEOF

log "preparing a private PGP keyring from Omarchy's packaged maintainer keys"
install -d -m700 "$GNUPGHOME"
for key in keys/pgp/*.asc; do
    GNUPGHOME="$GNUPGHOME" gpg --batch --import "$key" >/dev/null 2>&1
done

log "verifying sources and signatures"
GNUPGHOME="$GNUPGHOME" makepkg --verifysource

log "building linux-omarchy 7.2.5-3.1 with HONOR eDP DSC preference"
GNUPGHOME="$GNUPGHOME" makepkg --cleanbuild --clean --noconfirm

KERNEL_PKG="$(find "$PKGDIR" -maxdepth 1 -type f -name 'linux-omarchy-7.2.5-3.1-x86_64.pkg.tar.*' -print -quit)"
HEADERS_PKG="$(find "$PKGDIR" -maxdepth 1 -type f -name 'linux-omarchy-headers-7.2.5-3.1-x86_64.pkg.tar.*' -print -quit)"
[[ -n "$KERNEL_PKG" && -n "$HEADERS_PKG" ]] || die "kernel packages were not produced"

log "installing patched Omarchy kernel and matching headers"
sudo pacman -U --noconfirm "$KERNEL_PKG" "$HEADERS_PKG"

log "rebuilding Omarchy Limine boot images"
sudo limine-mkinitcpio

echo
log "PATCHED KERNEL INSTALL: OK"
echo
echo "Installed package:"
pacman -Q linux-omarchy linux-omarchy-headers
echo
echo "Current running kernel is still: $(uname -r)"
echo "Reboot yourself when ready:"
echo
echo "  systemctl reboot"
echo
echo "After login verify:"
echo
echo "  cat /var/lib/honor/health-last.txt"
