# Omarchy updates and persistence

The primary design goal is to keep the **official Omarchy kernel and update
flow**.

## Normal update path

Use Omarchy normally:

```bash
omarchy-update
```

If a new kernel was installed, reboot normally. About one minute after login:

```bash
cat /var/lib/honor/health-last.txt
```

Healthy result:

```text
RESULT: OK
```

## What survives normal updates

The hardware adaptation lives outside Omarchy's package-owned defaults:

```text
/usr/lib/firmware/acpi/SSDT27_TPD0.aml
/etc/initcpio/install/acpi_override
/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
/etc/limine-entry-tool.d/90-honor-m1230.conf
/etc/udev-hid-bpf/
/etc/systemd/system/
/etc/systemd/user/honor-dsc-modeset.service
/etc/ld.so.conf.d/
/opt/honor-libfprint-sdcp/
/usr/local/lib/honor/
/var/lib/honor/
/var/lib/honor-m1230/
/var/opt/honor-magicbook-linux/
```

The repository never replaces `/etc/default/limine`.

## Kernel policy

There is intentionally:

- no locally patched `linux-omarchy`;
- no custom `xe.ko`;
- no kernel pin just for this laptop.

The stock Omarchy kernel currently reaches the stable display state used by
this adaptation:

```text
DSC active
bpp=24 (8 bpc)
dither=no
```

A kernel-side eDP patch can reach 10 bpc on this panel, but carrying it locally
would turn every Omarchy kernel update into a rebuild/maintenance event. This
repository deliberately does not do that.

## Keyboard backlight after a kernel update

The keyboard-backlight module is the only local kernel module. Its service keeps
the source under `/var/lib/honor/kbdlight-src` and rebuilds it for the kernel
that is actually running.

Matching headers must exist:

```bash
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
test -e /usr/lib/modules/"$(uname -r)"/build/Makefile && echo headers-ok
```

For the default kernel the package is normally:

```bash
sudo pacman -S --needed linux-omarchy-headers
```

If headers were installed for a newer kernel while you are still running the
old one, reboot first instead of forcing a mismatched build.

## ACPI after a kernel update

The AML is injected into the early CPIO by:

```text
/etc/initcpio/install/acpi_override
/etc/mkinitcpio.conf.d/zz-honor-m1230-acpi.conf
```

Omarchy's normal boot-image rebuild should carry it forward.

If the post-update health check says the live ACPI hash is stock/missing:

```bash
cd /var/opt/pluseight8-my-dotfiles
sudo ./stage-boot.sh
```

Only reboot after `stage-boot.sh` verifies the audited AML inside the actual
generated boot image.

## DSC after a kernel/desktop update

Two pieces cooperate:

1. `honor-force-dsc.service` arms DSC in the stock Intel display driver;
2. `honor-dsc-modeset.service` runs in the Omarchy user session and triggers
   one eDP DPMS cycle so Hyprland performs a new modeset.

If an update changes UWSM/Hyprland behavior and DSC stays at
`bpp=18, dither=yes`, collect:

```bash
sudo ./scripts/diagnose-dsc-session.sh
```

Then refresh the installed helpers from the current checkout:

```bash
sudo ./scripts/resume-runtime.sh
```

## HID-BPF after a kernel update

The mic-mute and touchpad-edge programs are CO-RE HID-BPF objects. They normally
do not need rebuilding for each kernel as long as the Omarchy kernel retains
the expected HID-BPF/BTF support.

The health check validates both installed objects and the mic-mute re-apply
service.

## Fingerprint after an update

The SDCP libfprint build lives in:

```text
/opt/honor-libfprint-sdcp
```

and is placed ahead of the distribution copy through the dynamic-loader config.
The health check confirms that prefix is still in the loader cache and that
`fprintd` responds.

Omarchy still owns authentication enrollment/policy through:

```bash
omarchy-setup-security-fingerprint
```

## Updating this repository

```bash
cd /var/opt/pluseight8-my-dotfiles
git pull --ff-only
./scripts/audit.sh
```

For a normal already-working machine you do **not** rerun the full installer
after every repository pull.

Use:

```bash
sudo ./scripts/resume-runtime.sh
```

only when the runtime helpers/services themselves changed or a health check says
they need repair.

## If a new Omarchy update breaks something

Collect:

```bash
cat /var/lib/honor/health-last.txt
uname -r
cat /usr/lib/modules/"$(uname -r)"/pkgbase
sudo journalctl -k -b --no-pager > /tmp/honor-kernel.log
```

For display/session regressions:

```bash
sudo ./scripts/diagnose-dsc-session.sh
```

Do not copy an old kernel module into a new kernel.

## Omarchy rollback

Use Omarchy's own snapshot/rollback workflow. This repository does not create a
second competing rollback mechanism.

After rolling back, reboot into the selected kernel and inspect:

```bash
cat /var/lib/honor/health-last.txt
```
