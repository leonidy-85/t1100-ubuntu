/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Small stubs for MediaTek-4.14-only helpers that the vendor Vcodec driver
 * references.  None of them are essential for the char-device/ioctl ABI.
 */
#ifndef __VCODEC_COMPAT_H__
#define __VCODEC_COMPAT_H__

#include <linux/types.h>
#include <linux/kernel.h>

/* From MTK aee/detect (printk detect count).  No-op on mainline. */
static inline unsigned int get_detect_count(void)
{
	return 0;
}

static inline void set_detect_count(unsigned int count)
{
}

#endif /* __VCODEC_COMPAT_H__ */
