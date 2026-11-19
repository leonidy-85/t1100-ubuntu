/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Compatibility shim for the MediaTek 4.14 <mt-plat/sync_write.h>.
 * On mainline a normal writel() is enough; the MTK macro only added a
 * barrier around the store.
 */
#ifndef __MTK_COMPAT_MT_PLAT_SYNC_WRITE_H__
#define __MTK_COMPAT_MT_PLAT_SYNC_WRITE_H__

#include <linux/io.h>

#define mt_reg_sync_writel(v, a)	writel((v), (void __iomem *)(a))
#define mt_reg_sync_readl(a)		readl((const void __iomem *)(a))

#define mt_reg_sync_writew(v, a)	writew((v), (void __iomem *)(a))
#define mt_reg_sync_writel_relaxed(v, a)	writel_relaxed((v), (void __iomem *)(a))

#endif /* __MTK_COMPAT_MT_PLAT_SYNC_WRITE_H__ */
