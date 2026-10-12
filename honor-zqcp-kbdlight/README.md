# HONOR ZQC-P M1230 keyboard backlight

Small out-of-tree LED-class driver used by the Omarchy adaptation.

It is intentionally restricted to:

```text
DMI_SYS_VENDOR    HONOR
DMI_PRODUCT_NAME  ZQC-P
DMI_BOARD_VERSION M1230
```

The installer also checks that the running DSDT contains the expected `KBBL`,
`GKBM` and `SKBM` symbols before permitting EC writes.

Install through the main flow:

```bash
sudo ./install.sh --yes
```

or directly:

```bash
sudo ./honor-zqcp-kbdlight/install-omarchy.sh
```

When loaded it exposes:

```text
/sys/class/leds/honor::kbd_backlight
```

with brightness values `0`, `1`, `2`.

The systemd service rebuilds the module for the running kernel when its cached
vermagic no longer matches. Matching Omarchy kernel headers must remain
installed.
