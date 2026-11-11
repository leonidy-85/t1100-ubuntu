/* SPDX-License-Identifier: GPL-2.0 */
/*
 * sdio_ops.h -- compat stub for MediaTek's out-of-tree SDIO glue
 * (drivers/misc/mediatek/sdio/sdio_ops.h in MTK 4.14 trees).
 *
 * Included unconditionally by
 *   common_main/linux/include/hif_sdio.h
 * which in turn is pulled in by WMT core files (wmt_dev.c, wmt_ctrl.c,
 * wmt_exp.c, stp_exp.c) even when the SDIO transport is not built.
 *
 * On MT6771/MT6631 the Wi-Fi HIF is AHB/WFDMA (os/linux/hif/ahb_sdioLike),
 * not SDIO, and common_main/linux/{hif_sdio,stp_sdio}.c are not part of the
 * build (see scripts/remote/wifi-kbuild/common.Kbuild). Only the declarations
 * needed to *parse* hif_sdio.h live here.
 *
 * TODO(port): delete this file together with the SDIO objects once the BTIF/
 * AHB path is confirmed on hardware.
 */
#ifndef __COMPAT_SDIO_OPS_H__
#define __COMPAT_SDIO_OPS_H__

#include <linux/types.h>

struct sdio_func;
struct msdc_host;

/* MTK SDIO glue entry points (drivers/misc/mediatek/sdio). Not implemented:
 * no SDIO transport in this build. */
static inline int mtk_sdio_request_eirq(void *func, void *eirq_handler,
					void *data)
{
	return -ENOSYS;
}

static inline int mtk_sdio_register_irq(void *func, void *irq_handler,
					void *data)
{
	return -ENOSYS;
}

static inline void mtk_sdio_free_eirq(void *func)
{
}

#endif /* __COMPAT_SDIO_OPS_H__ */
