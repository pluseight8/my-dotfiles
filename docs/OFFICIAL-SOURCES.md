# Official sources used for the Bazzite integration

The Bazzite design and audit intentionally used official project sources only.
No blogs, forum posts, Reddit threads, package-guide sites or generated how-to
pages were used to decide how Bazzite itself should be modified.

Reviewed on 2026-10-10:

## Bazzite documentation

- https://docs.bazzite.gg/
- https://docs.bazzite.gg/Installing_and_Managing_Software/rpm-ostree/
- https://docs.bazzite.gg/Installing_and_Managing_Software/Homebrew/
- https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/
- https://docs.bazzite.gg/General/Installation_Guide/install-guide/
- https://docs.bazzite.gg/Advanced/dracut-and-initramfs/

Documentation repository revision reviewed:

`ublue-os/docs.bazzite.gg` @ `adb77da474d8da9f5bdd6b3fc6de4b7243cb9291`

## Bazzite source repository

- https://github.com/ublue-os/bazzite
- `build_files/install-kernel-akmods` — confirms Bazzite's image carries its
  matching kernel-devel and version-locks the kernel/kernel-devel set.
- `Containerfile` — confirms Bazzite enables its update/rollback health services
  and SELinux-oriented image configuration.
- Bazzite `ujust` source — confirms Bazzite itself uses `rpm-ostree kargs` for
  persistent kernel-argument changes.

Repository revision reviewed:

`ublue-os/bazzite` @ `7f903b94e31461c92b93110a2cb3a33f9539942a`

## Fedora SELinux policy source

The DSC service uses Fedora's existing `unconfined_service_t` domain rather than
disabling SELinux or adding a broad `init_t -> debugfs_t` allow rule. The domain
was verified in the official Fedora SELinux policy source:

- https://github.com/fedora-selinux/selinux-policy/blob/rawhide/policy/modules/system/unconfined.te

## HONOR-specific code dependency

Bazzite does not provide model-specific support for this laptop. The HONOR
hardware patch implementation is therefore a separate, pinned code dependency
that had already been validated on this exact M1230 during bring-up. It is not
used as a source for claims about Bazzite behavior.

The installer pins that dependency by commit SHA and applies fail-closed DMI and
ACPI-byte checks before it can affect the host.

## HID-BPF build headers

The installer does not fetch Linux HID-BPF headers from a public mirror. It
uses the exact source/header tree shipped with Bazzite's matching OGC
`kernel-devel` at `/lib/modules/$(uname -r)/build`. This keeps the BPF build
aligned with the running Bazzite kernel and removes a previously unnecessary
external header source.
