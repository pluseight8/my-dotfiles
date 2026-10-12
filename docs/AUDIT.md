# Audit notes

## Scope

The current repository targets **Omarchy on HONOR ZQC-P/M1230** only. The
previous Bazzite integration was replaced rather than mixed into the same
installer path.

## Fail-closed gates

Before boot changes are staged:

- Omarchy package and tools must exist;
- the running kernel pkgbase must begin with `linux-omarchy`;
- DMI must match `HONOR / ZQC-P / M1230 / ZQC-P-PCB`;
- kernel lockdown/Secure Boot must not be active;
- matching kernel headers must exist;
- required host packages must already be installed;
- `/sys/kernel/btf/vmlinux` must exist;
- the pinned HONOR git commit must resolve to the pinned tree SHA;
- live `I2C_DEVT` must equal the audited stock or exact patched bytes.

Unknown firmware is not given a force flag.

## Upstream trust boundary

The local M1230 profile is `probed`, not `verified`, and only lists upstream
Tier-A fixes. That prevents the generic HONOR code from silently inheriting
M1010/M1050 board constants.

The locally written keyboard-backlight module is separately guarded by exact
DMI plus ACPI symbol checks.

## Boot configuration

No repository script rewrites `/etc/default/limine`.

The two persistent boot inputs are:

```text
/etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf
/etc/limine-entry-tool.d/90-honor-m1230.conf
```

`stage-boot.sh` calls `limine-mkinitcpio`, but never reboots.

## Display driver policy

No local `xe.ko` is installed.

The PTL CDCLK bug fix is already present in the reviewed stable 7.2.8 base.
The 10-bpc/DSC issue is handled through the packaged kernel's debugfs force
control and validated after it is written.

This avoids combining a vanilla-built Xe module with Omarchy's patched kernel.

## Package ownership

The repository does not invoke `pacman -S`. Host packages are installed by the
user before preflight.

The EgisTec SDCP path builds into a private `/opt` prefix rather than replacing
Omarchy's package database entry. Omarchy remains responsible for its own
fingerprint PAM/polkit/lock policy.

## Reboot policy

No script contains an automatic `systemctl reboot`, `reboot`, `shutdown -r` or
equivalent. The user crosses the reboot boundary explicitly after inspecting
the staged boot configuration.

## Static CI

`.github/workflows/audit.yml` runs `scripts/audit.sh`. The audit checks syntax
and repository invariants, including:

- no Bazzite/rpm-ostree integration in executable scripts;
- no package installation inside the three main installer phases;
- no direct `/etc/default/limine` write;
- no custom Xe-module installer path;
- no automatic reboot;
- full upstream SHA pin;
- exact ACPI hashes;
- M1230 DMI guard in the keyboard module;
- Omarchy Limine/mkinitcpio drop-in usage.
