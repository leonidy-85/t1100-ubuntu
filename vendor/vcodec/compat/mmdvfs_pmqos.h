/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Compatibility shim for the MediaTek 4.14 MMDVFS/PM-QoS interface.
 *
 * Mainline 6.12 does not have MTK's PM_QOS_VDEC_FREQ / memory-bandwidth
 * classes and there is no MMDVFS driver for MT6771.  The vendor driver only
 * uses them for optional DVFS hints, so make them no-ops.  The real
 * frequency-step table is left empty; the code guards against that.
 */
#ifndef __MTK_COMPAT_MMDVFS_PMQOS_H__
#define __MTK_COMPAT_MMDVFS_PMQOS_H__

#include <linux/types.h>
#include <linux/pm_qos.h>

/* Vendor PM-QoS class IDs (MTK private, not upstream). */
#define PM_QOS_MM_MEMORY_BANDWIDTH	1
#define PM_QOS_VDEC_FREQ		2
#define PM_QOS_VENC_FREQ		3

#define MAX_FREQ_STEP			10

#define MMDVFS_VOLTAGE_LOW		0
#define MMDVFS_VOLTAGE_HIGH		1

static inline int mmdvfs_qos_get_freq_steps(int id, u64 *steps, u32 *cnt)
{
	/* No MMDVFS provider on mainline: report an empty step table. */
	if (cnt)
		*cnt = 0;
	return -ENODEV;
}

static inline int mmdvfs_set_fine_step(int level)
{
	return 0;
}

static inline int mmdvfs_qos_get_status(int id)
{
	return 0;
}

#endif /* __MTK_COMPAT_MMDVFS_PMQOS_H__ */
