/* compat: arch/arm64/include/asm/sync_write.h from MTK 4.14 trees (removed upstream).
 * One-byte/word/dword variants were thin wrappers around the raw MMIO helpers. */
#ifndef __COMPAT_SYNC_WRITE_H__
#define __COMPAT_SYNC_WRITE_H__
#include <linux/io.h>
#define mt_reg_sync_writel(v, a)	writel((v), (void __iomem *)(a))
#define mt_reg_sync_writew(v, a)	writew((v), (void __iomem *)(a))
#define mt_reg_sync_writeb(v, a)	writeb((v), (void __iomem *)(a))
#define mt_reg_sync_readl(a)		readl((void __iomem *)(a))
#define mt_reg_sync_readw(a)		readw((void __iomem *)(a))
#define mt_reg_sync_readb(a)		readb((void __iomem *)(a))
#endif
