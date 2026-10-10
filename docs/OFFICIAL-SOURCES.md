# Official sources used for the Omarchy port

All claims about Omarchy itself were checked against official Omarchy material.
No Reddit, forums, blogs, random setup guides, mirrors or third-party Omarchy
tutorials were used.

Reviewed: 2026-10-10.

## Official Omarchy website/manual

- https://omarchy.org/
- https://omarchy.org/manual/
- https://omarchy.org/manual/getting-started/
- https://omarchy.org/manual/updates/
- https://omarchy.org/manual/system-snapshots/
- https://omarchy.org/manual/security/
- https://omarchy.org/manual/dotfiles/
- https://omarchy.org/manual/omarchy-cli/

The official site offered Omarchy 4.0.4 when this port was prepared.

The official manual establishes the points this repository relies on:

- ISO installation is the normal supported path;
- Secure Boot/TPM are disabled for installation;
- Omarchy is Arch + Hyprland + Quickshell;
- system updates go through `omarchy update` rather than direct `pacman -Syu`;
- updates take a snapshot and run Omarchy migrations/config updates;
- Limine snapshots are the supported rollback path;
- user customizations belong outside `/usr/share/omarchy`.

## Official Omarchy repositories

Main repository:

- https://github.com/omacom/omarchy
- reviewed revision:
  `077ac1da939de00d061c1035e1a1d00587a119b8`

Relevant official source paths reviewed:

- `install/omarchy-base.packages`
- `install/omarchy-other.packages`
- `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`
- `etc/limine-entry-tool.d/omarchy-defaults.conf`
- `bin/omarchy-update`
- `bin/omarchy-brightness-keyboard`
- `bin/omarchy-setup-security-fingerprint`
- `default/hypr/bindings/media.lua`
- `docs/file-layout.md`
- `agents/skills/install-scripts.md`

Official package repository:

- https://github.com/omacom/omarchy-pkgs
- reviewed revision:
  `0a906801f1a876a739a6de902c9a366d295f43c9`

Relevant package source reviewed:

- `pkgbuilds/linux-omarchy/PKGBUILD`
- `pkgbuilds/linux-omarchy-bore/PKGBUILD`
- `pkgbuilds/libfprint-git/PKGBUILD`

The official Omarchy package list currently installs `linux-omarchy`,
`linux-omarchy-headers`, Limine and the Limine mkinitcpio integration. The
current `linux-omarchy` package line reviewed was based on Linux 7.2.8.

## Official Arch package information

Only official Arch package/manual pages were used to verify the current
HID-BPF package/tool naming:

- https://archlinux.org/packages/extra/x86_64/udev-hid-bpf/
- https://man.archlinux.org/man/udev-hid-bpf.1.en
- https://archlinux.org/packages/extra/x86_64/linux-tools/

The current Arch `udev-hid-bpf` CLI exposes `add`/`remove` and does not document
the obsolete `list-loaded` command used by older hardware scripts. This port
therefore treats a successful `udev-hid-bpf add` as the live-attach result and
lets udev handle persistence.

## HONOR-specific payload

Omarchy does not ship a hardware profile for this exact HONOR M1230. The
model-specific ACPI/HID-BPF/EgisTec payload in this repository is based on the
already-tested M1230 bring-up from the previous setup and is pinned by exact
commit/tree/hash checks.

It is deliberately **not** used as a source of truth about Omarchy. Omarchy
integration decisions come only from the official sources above.
