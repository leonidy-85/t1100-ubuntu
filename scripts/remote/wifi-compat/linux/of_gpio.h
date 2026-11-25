/* SPDX-License-Identifier: GPL-2.0 */
/* 7.3 compat: <linux/of_gpio.h> was removed upstream.  The vendor WMT code
 * still asks for the legacy integer GPIO number, so wrap the descriptor API. */
#ifndef __LINUX_OF_GPIO_COMPAT_H
#define __LINUX_OF_GPIO_COMPAT_H

#include <linux/err.h>
#include <linux/gpio.h>
#include <linux/gpio/consumer.h>
#include <linux/of.h>

static inline int of_get_named_gpio(const struct device_node *np,
				    const char *list_name, int index)
{
	struct gpio_desc *desc;
	int gpio;

	desc = fwnode_gpiod_get_index(of_fwnode_handle(np), list_name, index,
				      GPIOD_ASIS, "wmt-compat");
	if (IS_ERR(desc))
		return PTR_ERR(desc);

	gpio = desc_to_gpio(desc);
	gpiod_put(desc);
	return gpio;
}

#endif /* __LINUX_OF_GPIO_COMPAT_H */
