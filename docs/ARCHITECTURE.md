# Architecture

## Manual host package boundary

Bazzite recommends Homebrew and containers for ordinary user software and
package layering only for software that truly has to live on the host. This
setup changes initramfs contents, kernel arguments, udev HID-BPF loading,
PAM/fprintd integration, a kernel module, systemd units and debugfs, so a small
set of host packages is required.

The boundary is explicit: **the repository never executes `rpm-ostree install`**.
The user performs the dependency transaction and its reboot manually before
launching the HONOR installer. The installer only validates that all required
packages are present.

That means the user owns package layering; the installer owns only the
HONOR-specific hardware configuration.
## Writable locations

No installed file is written into immutable `/usr` except files already shipped
by the Bazzite image. Persistent custom state lives in locations intended for
machine-local state:

- `/etc/honor-magicbook/acpi`
- `/etc/dracut.conf.d`
- `/etc/udev-hid-bpf`
- `/etc/systemd/system`
- `/etc/ld.so.conf.d`
- `/opt/honor-libfprint-sdcp`
- `/usr/local/lib/honor`
- `/var/lib/honor`
- `/var/lib/honor-m1230`
- `/var/opt/honor-magicbook-linux`
- `/var/opt/pluseight8-my-dotfiles`

## Three-stage installer

The ACPI override cannot be validated until a reboot, because it is consumed by
the kernel during boot. HID-BPF installers then need the now-visible touchscreen
and touchpad. A systemd resume unit turns that unavoidable reboot boundary into
a single user-initiated installation.

The final reboot is not cosmetic: it proves every service, SELinux label,
HID-BPF attachment path, DSC write and keyboard module survives a clean boot.

## ACPI

The installer does not trust the board name alone. It locates the live SSDT by
OEM table id `I2C_DEVT` and compares its bytes against the pinned reference.
Installation stops on any mismatch.

## HID-BPF

The micmute and touchpad-edge programs are CO-RE objects. Their installed
objects live in `/etc/udev-hid-bpf`; they are not rebuilt on every kernel update.
The touchscreen descriptor fix has a boot re-apply service because descriptor
reprobe timing matters. The touchpad event hook attaches through udev.

## Fingerprint

The EgisTec reader uses a private patched libfprint under `/opt`, placed ahead
of the distribution lib through `/etc/ld.so.conf.d`. The Meson install is staged
through `DESTDIR` because Bazzite's `/usr` is image-owned/read-only; only the
private prefix and generated udev rule are copied to persistent writable paths.

## Keyboard backlight

A tiny DMI-bound out-of-tree module registers `honor::kbd_backlight`. It reads
and writes the verified M1230 EC KBBL field. The module is rebuilt when the
kernel release changes. New `.ko` files receive SELinux type
`modules_object_t` before systemd loads them.

`gcc` and `make` therefore remain installed after setup.

## DSC

The tested OGC kernel already exposes a writable `i915_dsc_fec_support` debugfs
control; no custom `xe.ko` is installed. SELinux blocks ordinary `init_t`
system services from writing `debugfs_t`, so only the root-owned DSC oneshot is
run in Fedora's existing `unconfined_service_t` domain. The service still runs
under SELinux Enforcing globally.