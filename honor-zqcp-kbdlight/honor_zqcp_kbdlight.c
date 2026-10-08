// SPDX-License-Identifier: GPL-2.0
/*
 * honor_zqcp_kbdlight - keyboard backlight LED driver for
 * HONOR MagicBook Pro 14 2026 AI, ZQC-P board M1230.
 *
 * Adapted from drphilth/honor-magicbook-pro-14-ubuntu:
 * honor-fmbp-kbdlight (GPL-2.0).
 *
 * ZQC-P firmware exposes EC RAM field KBBL at offset 0x41.
 * Verified mapping:
 *   0x04 = off
 *   0x02 = low
 *   0x03 = high
 *   0x01 = latch current level
 *
 * The EC also changes KBBL when the firmware keyboard-backlight shortcut is
 * used (Fn+Space on this M1230).  We poll KBBL and report firmware-initiated
 * changes through LED_BRIGHT_HW_CHANGED, which lets UPower/PowerDevil keep the
 * desktop slider in sync with the physical shortcut.
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/platform_device.h>
#include <linux/leds.h>
#include <linux/acpi.h>
#include <linux/dmi.h>
#include <linux/mutex.h>
#include <linux/workqueue.h>

#define KBBL_OFFSET     0x41
#define KBBL_OFF        0x04
#define KBBL_LOW        0x02
#define KBBL_HIGH       0x03
#define KBBL_LATCH      0x01
#define LATCH_DELAY_MS  1500
#define DEFAULT_POLL_MS 200

static bool steady = true;
module_param(steady, bool, 0644);
MODULE_PARM_DESC(steady, "Keep OS-selected keyboard backlight latched instead of timing out");

static unsigned int poll_ms = DEFAULT_POLL_MS;
module_param(poll_ms, uint, 0644);
MODULE_PARM_DESC(poll_ms, "EC polling interval used to detect Fn+Space brightness changes");

static DEFINE_MUTEX(state_lock);
static enum led_brightness cur_bright = 1;
static struct delayed_work latch_work;
static struct delayed_work sync_work;
static struct platform_device *pdev;
static struct led_classdev kbd_led;

static bool kbbl_to_level(u8 raw, enum led_brightness *b)
{
	switch (raw) {
	case KBBL_OFF:
		*b = 0;
		return true;
	case KBBL_LOW:
		*b = 1;
		return true;
	case KBBL_HIGH:
		*b = 2;
		return true;
	default:
		/*
		 * KBBL_LATCH (0x01) deliberately hides the previous physical
		 * level.  Keep the last known logical value in that state.
		 */
		return false;
	}
}

static u8 level_to_kbbl(enum led_brightness b)
{
	switch (b) {
	case 0:
		return KBBL_OFF;
	case 1:
		return KBBL_LOW;
	default:
		return KBBL_HIGH;
	}
}

static void latch_fn(struct work_struct *work)
{
	int ret;

	mutex_lock(&state_lock);
	ret = ec_write(KBBL_OFFSET, KBBL_LATCH);
	mutex_unlock(&state_lock);

	if (ret)
		pr_warn("honor_zqcp_kbdlight: EC latch write failed: %d\n", ret);
}

static int apply_level(enum led_brightness b)
{
	int ret;

	cancel_delayed_work_sync(&latch_work);

	mutex_lock(&state_lock);
	ret = ec_write(KBBL_OFFSET, level_to_kbbl(b));
	mutex_unlock(&state_lock);

	if (!ret && steady && b > 0)
		queue_delayed_work(system_freezable_wq, &latch_work,
				   msecs_to_jiffies(LATCH_DELAY_MS));

	return ret;
}

static int kbd_set(struct led_classdev *cdev, enum led_brightness b)
{
	if (b > 2)
		b = 2;

	mutex_lock(&state_lock);
	cur_bright = b;
	cdev->brightness = b;
	mutex_unlock(&state_lock);

	return apply_level(b);
}

static enum led_brightness kbd_get(struct led_classdev *cdev)
{
	enum led_brightness level;
	u8 raw;

	mutex_lock(&state_lock);
	if (!ec_read(KBBL_OFFSET, &raw) && kbbl_to_level(raw, &level))
		cur_bright = level;
	level = cur_bright;
	mutex_unlock(&state_lock);

	return level;
}

static void sync_fn(struct work_struct *work)
{
	enum led_brightness level = 0;
	bool changed = false;
	u8 raw;
	int ret;

	mutex_lock(&state_lock);
	ret = ec_read(KBBL_OFFSET, &raw);
	if (!ret && kbbl_to_level(raw, &level) && level != cur_bright) {
		cur_bright = level;
		kbd_led.brightness = level;
		changed = true;
	}
	mutex_unlock(&state_lock);

	if (changed) {
		/*
		 * UPower watches brightness_hw_changed with POLLPRI and relays
		 * firmware-initiated changes to desktops such as KDE PowerDevil.
		 */
		led_classdev_notify_brightness_hw_changed(&kbd_led, level);
		pr_debug("honor_zqcp_kbdlight: firmware brightness change -> %u\n",
			 level);
	}

	queue_delayed_work(system_freezable_wq, &sync_work,
			   msecs_to_jiffies(max_t(unsigned int, poll_ms, 50)));
}

static ssize_t mode_show(struct device *dev,
			 struct device_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%s\n", steady ? "steady" : "reactive");
}

static ssize_t mode_store(struct device *dev,
			  struct device_attribute *attr,
			  const char *buf, size_t count)
{
	enum led_brightness level;

	if (sysfs_streq(buf, "steady"))
		steady = true;
	else if (sysfs_streq(buf, "reactive"))
		steady = false;
	else
		return -EINVAL;

	mutex_lock(&state_lock);
	level = cur_bright;
	mutex_unlock(&state_lock);

	if (level > 0)
		apply_level(level);

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
	.flags = LED_CORE_SUSPENDRESUME | LED_BRIGHT_HW_CHANGED,
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
	enum led_brightness level;
	u8 raw = 0;
	int ret;

	if (!dmi_check_system(honor_zqcp_m1230)) {
		pr_info("honor_zqcp_kbdlight: not HONOR ZQC-P M1230, refusing to load\n");
		return -ENODEV;
	}

	ret = ec_read(KBBL_OFFSET, &raw);
	if (ret) {
		pr_err("honor_zqcp_kbdlight: cannot read EC KBBL 0x41: %d\n", ret);
		return ret;
	}

	if (kbbl_to_level(raw, &level))
		cur_bright = level;
	else
		cur_bright = 1;

	INIT_DELAYED_WORK(&latch_work, latch_fn);
	INIT_DELAYED_WORK(&sync_work, sync_fn);

	pdev = platform_device_register_simple("honor-zqcp-kbdlight",
					       -1, NULL, 0);
	if (IS_ERR(pdev))
		return PTR_ERR(pdev);

	ret = led_classdev_register(&pdev->dev, &kbd_led);
	if (ret) {
		platform_device_unregister(pdev);
		return ret;
	}

	queue_delayed_work(system_freezable_wq, &sync_work,
			   msecs_to_jiffies(max_t(unsigned int, poll_ms, 50)));

	pr_info("honor_zqcp_kbdlight: registered %s, raw KBBL=0x%02x, logical=%u, sync=%ums\n",
		kbd_led.name, raw, cur_bright, max_t(unsigned int, poll_ms, 50));
	return 0;
}

static void __exit kbdlight_exit(void)
{
	cancel_delayed_work_sync(&sync_work);
	cancel_delayed_work_sync(&latch_work);
	led_classdev_unregister(&kbd_led);
	platform_device_unregister(pdev);
}

module_init(kbdlight_init);
module_exit(kbdlight_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Keyboard backlight LED driver for HONOR ZQC-P M1230 with Fn+Space sync");
MODULE_AUTHOR("Adapted for pluseight8 from drphilth honor-fmbp-kbdlight");