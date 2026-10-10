# Repository and installer audit

Audit target: the Bazzite/HONOR repository after the 2026-10-10 overhaul.

## Result

**Static repository audit: PASS (GitHub Actions)**, subject to the residual hardware/update risks
listed below.

Run it locally at any time:

```bash
bash scripts/audit.sh
```

A GitHub Actions workflow runs the same self-contained audit on every push and
pull request.

## Scope cleanup

The old repository mixed CachyOS/DriftWM dotfiles, scratch files, office data
and several obsolete installation transcripts. The Bazzite overhaul removes
those from `main`. They remain recoverable in:

`backup/pre-bazzite-honor-overhaul-2026-10-10`

The new `main` has one purpose: this exact HONOR M1230 on Bazzite.

## Bazzite integration audit

### Package management — PASS

Bazzite's official documentation says package layering is a last resort and can
block future updates. This setup layers only tools that must operate on the host
kernel/udev/PAM stack. The ownership-aware dependency helper records which
packages it added. Build-only packages are kept by default so future repairs do
not need to reconstruct the host build environment; an optional cleanup helper
can remove only the temporary packages this repo owns. Persistent packages are
limited to runtime components plus `gcc/make` for automatic keyboard-module
rebuilds.

### Kernel-devel — PASS

The installer does not layer an arbitrary Fedora kernel-devel. The official
Bazzite build installs and version-locks its kernel and matching kernel-devel.
The setup only proceeds when the running `/lib/modules/<release>/build/Makefile`
exists.

### Initramfs — NECESSARY EXCEPTION

Bazzite documentation warns that local initramfs customization slows image
updates and recommends kernel arguments where possible. PSR therefore uses
`rpm-ostree kargs`; only the ACPI table uses local initramfs because an ACPI
override cannot be expressed as a kernel argument.

### Update/rollback model — PASS

The installer pins the pre-change deployment when possible. Bazzite's normal
rollback mechanism remains intact; no `rpm-ostree reset` is used.

## Hardware safety audit

### DMI gate — PASS

Every destructive host path is gated to `HONOR / ZQC-P / M1230`. The keyboard
module has an independent in-kernel DMI table and the HONOR upstream adapter adds
an M1230-specific device profile.

### ACPI gate — PASS

The installer does not trust DMI alone. It:

1. finds the live SSDT by OEM id `I2C_DEVT`;
2. verifies the pinned stock file's known MD5;
3. verifies the pinned patched file's known MD5;
4. compares the live firmware table to the stock reference;
5. stops on any mismatch.

No `FORCE_ACPI=1` escape is used.

### BIOS update behavior — PASS WITH PROCEDURE

A firmware update can invalidate the ACPI assumption before Linux has a chance
to run the normal health check. `scripts/prepare-bios-update.sh` removes the
override from the next deployment before flashing. After the BIOS update,
`install.sh --repair` must revalidate the new live ACPI bytes.

### HID-BPF — PASS

Installed objects are tied to the observed touchscreen/touchpad IDs. The
obsolete `udev-hid-bpf list-loaded` verification is removed from the pinned
upstream adapter because current Bazzite/Fedora tooling does not expose it.

### Fingerprint — PASS WITH EXTERNAL CODE RISK

The Bazzite immutable `/usr` failure is fixed by staging Meson installation with
`DESTDIR`, then copying only the private `/opt` prefix and generated udev rule to
writable persistent paths. The SDCP source is already pinned by the hardware
support recipe.

Residual risk: the SDCP implementation is not part of a released system
libfprint. A future fprintd/libfprint ABI change can require rebuilding or
rebasing the private library. The health check detects disappearance from the
loader cache but cannot prove every future ABI behavior in advance.

### Keyboard backlight — PASS

The driver is DMI-bound, checks expected DSDT symbols, does not modify brightness
on module load, and carries no periodic EC polling. The build service applies
SELinux `modules_object_t` before `insmod` and rebuilds on kernel-release change.

### DSC — PASS WITH ISOLATED PRIVILEGE

No custom `xe.ko` is installed. The current OGC kernel's debugfs switch is used.
The tested SELinux policy blocks `init_t` from writing `debugfs_t`; the service
therefore runs only this root-owned oneshot in Fedora's existing
`unconfined_service_t`. SELinux remains globally Enforcing.

Security trade-off: that one process is unconfined while it runs. The helper is
root-owned, short-lived, has no network access, accepts no input, writes only the
located eDP DSC control, and exits immediately.

## Script audit

### Error handling — PASS

Mutation scripts use `set -euo pipefail`, explicit gates, a single-install lock,
root checks and fail-closed validation. Network-dependent hardware builds retry
three times before stopping.

### Reboot/resume — PASS

A persistent systemd unit resumes only after network and display-manager
ordering. The installer state is root-owned under `/var/lib/honor-m1230` and the
final stage disables the resume unit only after a clean-boot health check passes.

### Destructive path handling — PASS

There is no global `rpm-ostree reset`, no global SELinux disable and no raw
absolute `sudo rm -rf`. Managed tree deletion goes through a path guard limited
to dedicated `/var/opt` or installer-state paths.

### Source pinning — PASS

The HONOR support source is pinned to a full commit SHA. The adaptation script
also refuses to operate when HEAD differs from the audited commit or when exact
installer snippets have drifted.

## Static checks performed

- `bash -n` over every shell script;
- Python bytecode compilation for the adapter;
- forbidden-pattern scan;
- pin/hash presence checks;
- systemd DSC context/entrypoint checks;
- keyboard-module DMI/no-poll checks;
- official-source document host allowlist;
- optional ShellCheck when installed;
- `git diff --check` in a real checkout.

## Residual risks that cannot be scripted away

1. A future Bazzite kernel can change an internal API used by the tiny keyboard
   module. Rebuild will then fail rather than load an incompatible module.
2. A future OGC kernel can remove or rename `i915_dsc_fec_support`. The DSC
   service and health check will fail visibly rather than patching a module.
3. A future libfprint/fprintd change can invalidate the private SDCP build.
4. A BIOS update can change ACPI/EC. Use the BIOS-update procedure first.
5. Hardware vendors can silently change components under the same retail model.
   The device IDs and ACPI-byte checks are there specifically to stop on that
   case.

## CI supply-chain note

The GitHub Actions checkout action is pinned to an exact commit SHA rather than
a mutable version tag. The audit job has passed on the rebuilt Bazzite-only
`main` branch, including Bash parsing, Python compilation, warning/error-level
ShellCheck, policy scans and whitespace checks.
