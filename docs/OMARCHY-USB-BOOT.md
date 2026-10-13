# Booting the Omarchy installer on HONOR ZQC-P / M1230

This page covers the **installer USB boot problem that was reproduced on the
HONOR MagicBook Pro 14 2026 AI (ZQC-P / M1230)**: the normal Omarchy ISO boot
can switch into severe graphical artifacts before the installer becomes usable.

The workaround below affects **only this one live-USB boot**. It does not write
these kernel arguments into the installed Omarchy system.

## Why these paths are used

The reviewed official Omarchy x86_64 ISO boots:

```text
/arch/boot/x86_64/vmlinuz-linux-t2
/arch/boot/x86_64/initramfs-linux-t2.img
```

and its normal GRUB entry uses:

```text
archisobasedir=arch
archisosearchuuid=<ISO filesystem UUID>
quiet splash
xe.enable_panel_replay=0
initramfs_async=0
```

For this HONOR laptop we append the temporary installer-only workaround:

```text
nomodeset module_blacklist=xe
```

Do **not** carry those two arguments into the installed system.

## Fast path: you are already at a `grub>` prompt

First see whether the USB is `(cd0)`:

```grub
ls
```

On the tested Omarchy USB it was `(cd0)`. Verify the kernel is there:

```grub
ls (cd0)/arch/boot/x86_64/
```

You should see at least:

```text
vmlinuz-linux-t2
initramfs-linux-t2.img
```

Now let GRUB read the **current ISO's UUID** instead of hard-coding an old one:

```grub
set root=(cd0)
probe --set=iso_uuid --fs-uuid (cd0)
echo $iso_uuid
```

Then boot the installer:

```grub
linux /arch/boot/x86_64/vmlinuz-linux-t2 archisobasedir=arch archisosearchuuid=$iso_uuid quiet splash xe.enable_panel_replay=0 initramfs_async=0 nomodeset module_blacklist=xe
initrd /arch/boot/x86_64/initramfs-linux-t2.img
boot
```

This is the sequence that successfully reached the Omarchy installer on the
target M1230.

## If the USB is not `(cd0)`

Do not guess the device name. Ask GRUB to find the kernel:

```grub
search --file --set=root /arch/boot/x86_64/vmlinuz-linux-t2
echo $root
ls ($root)/arch/boot/x86_64/
probe --set=iso_uuid --fs-uuid ($root)
echo $iso_uuid
```

Then run the same boot commands:

```grub
linux /arch/boot/x86_64/vmlinuz-linux-t2 archisobasedir=arch archisosearchuuid=$iso_uuid quiet splash xe.enable_panel_replay=0 initramfs_async=0 nomodeset module_blacklist=xe
initrd /arch/boot/x86_64/initramfs-linux-t2.img
boot
```

## If you do not see a GRUB menu

The current Omarchy ISO has a hidden zero-second GRUB timeout, so on some
machines the normal menu is effectively invisible. If you need the command
line, press `c` immediately as the USB's GRUB starts. If you miss the tiny
window, reboot and try again.

If you do get a visible Omarchy menu instead, editing the normal entry and
appending:

```text
nomodeset module_blacklist=xe
```

to its kernel command line is equivalent.

## What to expect after `boot`

A brief Arch live-environment console/login message may flash before the
Omarchy logo/configurator. That is not the installed system asking you to set a
root password.

Once the graphical Omarchy installer appears, install normally.

After installation, boot the installed Omarchy normally. The post-install
hardware setup in this repository keeps the **stock Omarchy kernel** and does
not use `nomodeset` or blacklist `xe`.

## Important safety notes

- Do not hard-code an ISO UUID copied from an older USB. Use `probe` every
  time; the ISO filesystem UUID changes between builds.
- The graphical artifacts from one failed live-USB boot do not rewrite the ISO
  or make the USB permanently "artifacted".
- Do not install a custom `xe.ko` or locally rebuilt kernel for this setup.
- Secure Boot / kernel lockdown must be off before using the post-install ACPI
  override and local keyboard-backlight module.

## Official source references

The commands above mirror the official Omarchy ISO x86_64 GRUB entry, with only
the two M1230 installer-workaround arguments appended.

Reviewed Omarchy ISO revision:

```text
53b80d406cdcb56cd757562e0f31d2c13cb57f47
```

Relevant upstream files:

- `omacom/omarchy-iso/configs/grub/grub.cfg`
- `omacom/omarchy-iso/configs/efiboot/loader/entries/01-archiso-x86_64-linux.conf`
