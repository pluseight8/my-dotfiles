# Audit notes

## Scope

The repository targets **Omarchy on HONOR ZQC-P / M1230 only**.

The goal is to keep the official Omarchy kernel/update path intact while adding
the minimum machine-specific hardware enablement required by the tested M1230.

## Fail-closed host gates

Before boot changes are staged:

- Omarchy command/package presence must be verified;
- `/etc/os-release` may legitimately report `ID=omarchy`;
- the running kernel pkgbase must begin with `linux-omarchy`;
- DMI must match `HONOR / ZQC-P / M1230 / ZQC-P-PCB`;
- Secure Boot / kernel lockdown must not be active;
- matching running-kernel headers must exist;
- required host packages must exist;
- `/sys/kernel/btf/vmlinux` must exist;
- the pinned HONOR commit must resolve to the pinned tree SHA;
- live `I2C_DEVT` must equal either the audited stock or exact patched bytes.

Unknown firmware is not given a force flag.

## Guided installer

`setup.sh` is the recommended front end.

It is deliberately two-pass:

1. stock ACPI -> dependencies/audit/preflight/stage -> explicit reboot boundary;
2. patched live ACPI -> runtime install/refresh -> health check.

It never reboots the machine automatically.

The low-level `preflight.sh`, `stage-boot.sh`, and `install.sh` phases do
not install packages themselves. Only the explicit user-facing `setup.sh`
offers to install missing dependencies, after confirmation.

## Upstream trust boundary

M1230 stays `status=probed`, not `verified`.

The local profile only exposes:

```text
acpi-override psr-band micmute touchpad-edge fingerprint
```

No M1010/M1050 Tier-B board constants are inherited blindly.

## ACPI staging

The audited AML is staged from:

```text
/usr/lib/firmware/acpi/SSDT27_TPD0.aml
```

through the pinned hook:

```text
/etc/initcpio/install/acpi_override
```

and the last-sorting drop-in:

```text
/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
```

The stage is not considered successful just because `limine-mkinitcpio`
returned. The script extracts the **early CPIO** from the actual generated boot
image and hashes the AML inside it.

This regression test exists because earlier bring-up attempts falsely reported
success while the rebuilt image either used a different layout or the verifier
looked at the wrong UKI name.

## UKI discovery

The verifier does not assume a single file name.

It checks standard candidates and discovers prefixed images matching the running
kernel pkgbase, covering names such as:

```text
/boot/EFI/Linux/omarchy_linux-omarchy.efi
```

## ACPI verification after reboot

The **live table hash** is authoritative.

Kernel logs are only supplementary because wording around ACPI table upgrade
messages can change between kernel revisions.

This avoids the false-negative behavior encountered when the override was
loaded correctly but the expected journal phrase was absent.

## Fingerprint build dependency

`glib2-devel` is a required host dependency.

It is kept as an explicit audit invariant because missing `glib-mkenums`
previously caused the SDCP libfprint Meson setup to fail after the rest of the
runtime install had already progressed.

## Display / DSC policy

No custom kernel and no local `xe.ko` are allowed.

The system root service arms DSC. A user service waits for Omarchy/UWSM's
Wayland environment and triggers one internal-eDP DPMS cycle through Hyprland.

The helper:

- can recover `HYPRLAND_INSTANCE_SIGNATURE` from the live runtime directory;
- does not treat Hyprland's transient `7/NOTRUNNING` during the DPMS cycle as
  final truth;
- verifies the actual monitor `dpmsStatus` after the transition.

Healthy stock-kernel state is accepted as:

```text
DSC active
bpp=24 (8 bpc)
dither=no
```

The repository does not chase 10 bpc with a locally patched Omarchy kernel.

## Installer-USB recovery

[OMARCHY-USB-BOOT.md](OMARCHY-USB-BOOT.md) mirrors the reviewed official
Omarchy ISO GRUB entry and appends only the tested M1230 live-USB workaround:

```text
nomodeset module_blacklist=xe
```

The guide probes the current ISO filesystem UUID at boot and must never embed an
old ISO UUID.

## Static CI regression gates

`.github/workflows/audit.yml` runs `scripts/audit.sh`.

The audit checks, among other things:

- Bash/Python syntax;
- executable bits on all user-facing scripts;
- no Bazzite/`rpm-ostree` executable path;
- no lockdown bypass;
- no pipe-to-shell installer;
- no custom Xe or local `linux-omarchy` build/install path;
- no automatic reboot;
- no writes to `/etc/default/limine`;
- exact upstream/ACPI pins;
- M1230 trust level/fix allow-list;
- `ID=omarchy` detection;
- `glib2-devel` and `jq` dependencies;
- final ACPI early-CPIO paths;
- actual early-CPIO extraction in the boot verifier;
- Omarchy-prefixed UKI discovery;
- ACPI hash passed into the first runtime health check;
- initialized pending-DSC state;
- UWSM-aware user service ordering;
- Hyprland signature recovery and real DPMS-state verification;
- acceptance of the stock-kernel `bpp=24, dither=no` state;
- dynamic ISO UUID probing in the GRUB recovery guide;
- absence of the historical hard-coded ISO UUID.
