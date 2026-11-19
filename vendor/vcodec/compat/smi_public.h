/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Compatibility shim for MediaTek 4.14 SMI (Smart Multimedia Interface).
 *
 * The vendor Vcodec driver only uses the SMI bus clock helpers to make sure
 * the VDEC/VENC larb clock is on.  On mainline the larb1/larb4 drivers own
 * those clocks and the VDEC/VENC power domains are managed through genpd, so
 * there is nothing to do here yet.
 */
#ifndef __MTK_COMPAT_SMI_PUBLIC_H__
#define __MTK_COMPAT_SMI_PUBLIC_H__

#include <linux/types.h>

/* Keep the same numeric values as the vendor mt6771 smi_public.h. */
enum mtk_smi_larb_id {
	SMI_LARB0 = 0,
	SMI_LARB1,
	SMI_LARB2,
	SMI_LARB3,
	SMI_LARB4,
	SMI_LARB5,
	SMI_LARB6,
	SMI_LARB7,
	SMI_LARB8,
	SMI_LARB_NUM,
};

static inline int smi_bus_prepare_enable(int larb, const char *name)
{
	return 0;
}

static inline int smi_bus_enable(int larb, const char *name)
{
	return 0;
}

static inline int smi_bus_disable_unprepare(int larb, const char *name)
{
	return 0;
}

static inline int smi_bus_disable(int larb, const char *name)
{
	return 0;
}

#endif /* __MTK_COMPAT_SMI_PUBLIC_H__ */
