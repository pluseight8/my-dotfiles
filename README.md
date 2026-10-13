# HONOR MagicBook Pro 14 2026 AI (ZQC-P / M1230) — Omarchy

Hardware enablement for the exact **HONOR MagicBook Pro 14 2026 AI,
ZQC-P / M1230** on **Omarchy**, while keeping Omarchy's own kernel and update
path intact.

This repository adapts the audited work from
`rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010` to the M1230
board without blindly applying M1010/M1050 board-specific fixes.

## Target hardware

The installer fails closed unless the live machine matches the expected DMI and
device IDs:

- vendor: `HONOR`
- product: `ZQC-P`
- board revision: `M1230`
- board name: `ZQC-P-PCB`
- touchscreen: `2808:5662`
- touchpad: `27c6:0f9a`
- fingerprint: `1c7a:05aa`

## What it enables

- audited `I2C_DEVT` ACPI override for touchscreen/touchpad enumeration;
- `xe.enable_psr=1` through Omarchy's Limine drop-in interface;
- touchscreen mic-mute HID-BPF fix;
- touchpad left-edge brightness HID-BPF fix;
- private SDCP-capable libfprint for EgisTec `1c7a:05aa`;
- M1230 keyboard-backlight LED support as `honor::kbd_backlight`;
- DSC on the internal OLED through the **stock Omarchy kernel**;
- a post-login Hyprland modeset helper so DSC actually becomes active;
- automatic health checks with a final `RESULT: OK/FAIL`.

## What it deliberately does not do

- no custom `linux-omarchy` build;
- no replacement `xe.ko`;
- no Bazzite / `rpm-ostree` path;
- no direct rewrite of `/etc/default/limine`;
- no automatic reboot;
- no Secure-Boot or kernel-lockdown bypass;
- no blind M1010/M1050 EC offsets or other Tier-B board constants.

The observed healthy stock-kernel display state on this M1230 is:

```text
DSC active
bpp=24 (8 bpc)
dither=no
```

A kernel-side patch can push this panel to 10 bpc, but this repository
intentionally does **not** carry it because the priority is normal
`omarchy-update` behavior with the official kernel.

## If the Omarchy USB artifacts before the installer

See:

**[docs/OMARCHY-USB-BOOT.md](docs/OMARCHY-USB-BOOT.md)**

It contains the exact GRUB commands that successfully booted the Omarchy ISO on
this laptop using a temporary:

```text
nomodeset module_blacklist=xe
```

workaround. Those arguments are live-USB-only and are not installed into the
final system.

## Recommended post-install path

After Omarchy is installed and you are at the desktop:

```bash
sudo git clone https://github.com/pluseight8/my-dotfiles.git \
  /var/opt/pluseight8-my-dotfiles
sudo chown -R "$USER:$(id -gn)" /var/opt/pluseight8-my-dotfiles
cd /var/opt/pluseight8-my-dotfiles
./setup.sh
```

`setup.sh` is the preferred path. It incorporates the failure cases that were
found while bringing this exact machine up:

- accepts Omarchy's real `ID=omarchy`;
- installs the full host dependency set, including `glib2-devel` and `jq`;
- verifies the actual early-CPIO ACPI payload inside Omarchy's generated UKI;
- discovers Omarchy-prefixed UKIs instead of assuming a filename;
- verifies ACPI by the live table hash instead of fragile kernel-log wording;
- keeps the stock Omarchy kernel;
- handles DSC as a two-stage arm + compositor modeset operation;
- tolerates Hyprland's transient DPMS `NOTRUNNING` status and verifies actual
  monitor state instead;
- gives one final health result.

The first run stops after staging boot fixes and tells you to reboot. After
logging back in, run the **same command again**:

```bash
cd /var/opt/pluseight8-my-dotfiles
./setup.sh
```

No repository script reboots the machine automatically.

## Manual path

If you prefer to inspect each phase separately, use
[docs/INSTALL.md](docs/INSTALL.md).

## Updating later

Update Omarchy normally:

```bash
omarchy-update
```

After a kernel update and reboot:

```bash
cat /var/lib/honor/health-last.txt
```

A healthy machine ends with:

```text
RESULT: OK
```

See [docs/UPDATES.md](docs/UPDATES.md) for the persistence model and recovery
steps.
