// SPDX-License-Identifier: GPL-2.0
/*
 * Keyboard backlight LED driver for HONOR ZQC-P / M1230.
 *
 * KBBL EC mapping verified on the target machine:
 *   0x04 = off
 *   0x02 = low
 *   0x03 = high
 *   0x01 = latch current level
 *
 * Deliberately no periodic EC polling. Firmware Fn+Space remains independent;
 * KDE/UPower controls this LED class device directly.
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/platform_device.h>
#include <linux/leds.h>
#include <linux/acpi.h>
#include <linux/dmi.h>
#include <linux/workqueue.h>

#define KBBL_OFFSET     0x41
#define KBBL_OFF        0x04
#define KBBL_LOW        0x02
#define KBBL_HIGH       0x03
#define KBBL_LATCH      0x01
#define LATCH_DELAY_MS  1500

static bool steady = true;
module_param(steady, bool, 0644);
MODULE_PARM_DESC(steady, "Keep keyboard backlight latched instead of timing out");

static enum led_brightness cur_bright = 1;
static struct delayed_work latch_work;
static struct platform_device *pdev;

static u8 level_to_kbbl(enum led_brightness b)
{
    switch (b) {
    case 0: return KBBL_OFF;
    case 1: return KBBL_LOW;
    default: return KBBL_HIGH;
    }
}

static void latch_fn(struct work_struct *work)
{
    int ret = ec_write(KBBL_OFFSET, KBBL_LATCH);
    if (ret)
        pr_warn("honor_zqcp_kbdlight: EC latch write failed: %d\n", ret);
}

static int apply_level(enum led_brightness b)
{
    int ret;
    cancel_delayed_work_sync(&latch_work);
    ret = ec_write(KBBL_OFFSET, level_to_kbbl(b));
    if (!ret && steady && b > 0)
        schedule_delayed_work(&latch_work, msecs_to_jiffies(LATCH_DELAY_MS));
    return ret;
}

static int kbd_set(struct led_classdev *cdev, enum led_brightness b)
{
    if (b > 2)
        b = 2;
    cur_bright = b;
    return apply_level(b);
}

static enum led_brightness kbd_get(struct led_classdev *cdev)
{
    return cur_bright;
}

static ssize_t mode_show(struct device *dev, struct device_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%s\n", steady ? "steady" : "reactive");
}

static ssize_t mode_store(struct device *dev, struct device_attribute *attr,
                          const char *buf, size_t count)
{
    if (sysfs_streq(buf, "steady"))
        steady = true;
    else if (sysfs_streq(buf, "reactive"))
        steady = false;
    else
        return -EINVAL;

    if (cur_bright > 0)
        apply_level(cur_bright);
    return count;
}
static DEVICE_ATTR_RW(mode);

static struct attribute *kbd_attrs[] = {
    &dev_attr_mode.attr,
    NULL,
};
ATTRIBUTE_GROUPS(kbd);

static struct led_classdev kbd_led = {
    .name = "honor::kbd_backlight",
    .max_brightness = 2,
    .brightness_set_blocking = kbd_set,
    .brightness_get = kbd_get,
    .groups = kbd_groups,
    .flags = LED_CORE_SUSPENDRESUME,
};

static const struct dmi_system_id honor_zqcp_m1230[] = {
    {
        .ident = "HONOR ZQC-P M1230",
        .matches = {
            DMI_MATCH(DMI_SYS_VENDOR, "HONOR"),
            DMI_MATCH(DMI_PRODUCT_NAME, "ZQC-P"),
            DMI_MATCH(DMI_BOARD_VERSION, "M1230"),
        },
    },
    { }
};
MODULE_DEVICE_TABLE(dmi, honor_zqcp_m1230);

static int __init kbdlight_init(void)
{
    u8 raw = 0;
    int ret;

    if (!dmi_check_system(honor_zqcp_m1230))
        return -ENODEV;

    ret = ec_read(KBBL_OFFSET, &raw);
    if (ret)
        return ret;

    switch (raw) {
    case KBBL_OFF:  cur_bright = 0; break;
    case KBBL_LOW:  cur_bright = 1; break;
    case KBBL_HIGH: cur_bright = 2; break;
    default:        cur_bright = 1; break;
    }

    INIT_DELAYED_WORK(&latch_work, latch_fn);
    pdev = platform_device_register_simple("honor-zqcp-kbdlight", -1, NULL, 0);
    if (IS_ERR(pdev))
        return PTR_ERR(pdev);

    ret = led_classdev_register(&pdev->dev, &kbd_led);
    if (ret) {
        platform_device_unregister(pdev);
        return ret;
    }

    pr_info("honor_zqcp_kbdlight: registered %s, raw KBBL=0x%02x, logical=%u\n",
            kbd_led.name, raw, cur_bright);
    return 0;
}

static void __exit kbdlight_exit(void)
{
    cancel_delayed_work_sync(&latch_work);
    led_classdev_unregister(&kbd_led);
    platform_device_unregister(pdev);
}

module_init(kbdlight_init);
module_exit(kbdlight_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Keyboard backlight LED driver for HONOR ZQC-P M1230");
MODULE_AUTHOR("pluseight8 M1230 Bazzite setup");
