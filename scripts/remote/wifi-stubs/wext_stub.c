// SPDX-License-Identifier: GPL-2.0
/*
 * wext_stub.c -- `wireless_send_event()` for kernels built without
 * CONFIG_WEXT_CORE.
 *
 * Part of the MT6771 port, phase 5 path A: docs/wifi-port-log.md,
 * "M3: модули под -touch-rot".
 *
 * Why this exists: `wireless_send_event()` is exported by the kernel, but it
 * lives in net/wireless/wext-core.c, which is compiled into vmlinux only when
 * CONFIG_WEXT_CORE=y (a hidden bool, selected by CONFIG_CFG80211_WEXT). Our own
 * kernel selects it via configs/t1100-wifi.fragment, so there this file
 * compiles to nothing and is not linked. A foreign kernel without that option
 * has no such symbol at all, and the vendor driver would fail modpost
 * ("wireless_send_event undefined!") and insmod.
 *
 * What it costs: without CONFIG_WEXT_CORE the kernel's net/socket.c has no
 * WEXT ioctl dispatch at all (built-in stub returning -EINVAL), so no process
 * can receive these events or issue iwconfig/iwpriv ioctls anyway -- dropping
 * them is the semantically correct behaviour, not a regression. The driver
 * still works through cfg80211/nl80211 (wpa_supplicant, NetworkManager).
 *
 * Callers (vendor 249649d8): os/linux/gl_wext.c:3682,
 * os/linux/gl_p2p_kal.c:157/194/201 -- assoc/custom events for WEXT userspace.
 *
 * TODO: delete this file once the target kernel always carries
 * configs/t1100-wifi.fragment (then CONFIG_WEXT_CORE=y and the real symbol
 * from vmlinux is used).
 */
#include <linux/kernel.h>
#include <linux/netdevice.h>
#include <net/iw_handler.h>

#ifndef CONFIG_WEXT_CORE

void wireless_send_event(struct net_device *dev, unsigned int cmd,
			 union iwreq_data *wrqu, const char *extra)
{
	pr_warn_once("t1100-wifi: WEXT event 0x%x dropped: kernel built without CONFIG_WEXT_CORE\n",
		     cmd);
}

#endif /* !CONFIG_WEXT_CORE */
