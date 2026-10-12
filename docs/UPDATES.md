# Omarchy updates and rollback

## Normal update path

Update Omarchy normally:

```bash
omarchy-update
```

If a new kernel was installed, reboot normally. About one minute after login:

```bash
cat /var/lib/honor/health-last.txt
```

If the final line is:

```text
RESULT: OK
```

there is nothing to redo.

## What survives an update

These live outside package-owned configuration and should persist:

- `/etc/initcpio/acpi_override/SSDT27_TPD0.aml`;
- `/etc/mkinitcpio.conf.d/90-honor-m1230-acpi.conf`;
- `/etc/limine-entry-tool.d/90-honor-m1230.conf`;
- HID-BPF objects under `/etc/udev-hid-bpf`;
- the private SDCP libfprint under `/opt/honor-libfprint-sdcp`;
- systemd units and helpers under `/etc/systemd/system` and `/usr/local/lib/honor`;
- keyboard-backlight source under `/var/lib/honor/kbdlight-src`.

The keyboard module itself is tied to one kernel release, but the service checks
the running kernel on every boot and rebuilds the module from the matching
headers when its vermagic changes.

## If headers and kernel temporarily disagree

Check:

```bash
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
test -e /usr/lib/modules/"$(uname -r)"/build/Makefile && echo OK
```

If the headers for the **running** kernel are missing, do not force a build.
Install the matching package or boot the kernel that matches the installed
headers.

For the default Omarchy kernel:

```bash
sudo pacman -S --needed linux-omarchy-headers
```

## Why no automatic `xe.ko` rebuild hook exists

This repository deliberately does not overlay Omarchy's Xe driver. The current
stable kernel already contains the PTL CDCLK fix, and DSC is enabled using the
existing debugfs interface.

That means a normal kernel update does not need a locally rebuilt display
module.

## Updating this repository

The HONOR hardware source dependency is pinned. Pulling a new version of
`pluseight8/my-dotfiles` does not silently move that pin unless the repository
itself was audited and changed.

Update the checkout with:

```bash
cd /var/opt/pluseight8-my-dotfiles
git pull --ff-only
```

Then read the commit diff before rerunning the installer.

## If a new kernel breaks a fix

Collect:

```bash
cat /var/lib/honor/health-last.txt
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
sudo journalctl -k -b --no-pager > /tmp/honor-kernel.log
```

For a display regression also collect:

```bash
sudo cat /sys/kernel/debug/dri/*/eDP-*/i915_dsc_fec_support
sudo grep -m1 -E 'pipe src=.*bpp=' \
  /sys/kernel/debug/dri/*/i915_display_info
```

Do not copy a kernel module from an older kernel into the new one.

## Omarchy snapshots / rollback

Use Omarchy's own snapshot/rollback workflow for system rollback. This
repository does not create its own competing rollback system.

After rolling back to another kernel, the keyboard-backlight service rebuilds
for the kernel that is actually running. Run the health check again.
