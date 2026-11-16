/* SPDX-License-Identifier: GPL-2.0 */
/*
 * T1100: WMT exports the FM driver needs.
 *
 * The vendor wmt_exp.h pulls in wmt_plat.h / mtk_wcn_cmb_stub.h from the
 * in-tree connectivity package.  The FM driver only uses the enums below and
 * a handful of exported calls, so the port declares exactly those; names and
 * values must stay identical to wmt_drv's own wmt_exp.h.
 */
#ifndef _WMT_EXP_H
#define _WMT_EXP_H

#include "osal_typedef.h"

typedef enum _ENUM_WMTDRV_TYPE_T {
	WMTDRV_TYPE_BT = 0,
	WMTDRV_TYPE_FM = 1,
	WMTDRV_TYPE_GPS = 2,
	WMTDRV_TYPE_WIFI = 3,
	WMTDRV_TYPE_WMT = 4,
	WMTDRV_TYPE_ANT = 5,
	WMTDRV_TYPE_STP = 6,
	WMTDRV_TYPE_SDIO1 = 7,
	WMTDRV_TYPE_SDIO2 = 8,
	WMTDRV_TYPE_LPBK = 9,
	WMTDRV_TYPE_COREDUMP = 10,
	WMTDRV_TYPE_MAX
} ENUM_WMTDRV_TYPE_T, *P_ENUM_WMTDRV_TYPE_T;

typedef enum _ENUM_WMTHWVER_TYPE_T {
	WMTHWVER_E1 = 0x0,
	WMTHWVER_E2 = 0x1,
	WMTHWVER_E3 = 0x2,
	WMTHWVER_E4 = 0x3,
	WMTHWVER_E5 = 0x4,
	WMTHWVER_E6 = 0x5,
	WMTHWVER_E7 = 0x6,
	WMTHWVER_MAX,
	WMTHWVER_INVALID = 0xff
} ENUM_WMTHWVER_TYPE_T, *P_ENUM_WMTHWVER_TYPE_T;

typedef enum _ENUM_WMTMSG_TYPE_T {
	WMTMSG_TYPE_POWER_ON = 0,
	WMTMSG_TYPE_POWER_OFF = 1,
	WMTMSG_TYPE_RESET = 2,
	WMTMSG_TYPE_STP_RDY = 3,
	WMTMSG_TYPE_HW_FUNC_ON = 4,
	WMTMSG_TYPE_MAX
} ENUM_WMTMSG_TYPE_T, *P_ENUM_WMTMSG_TYPE_T;

typedef enum _ENUM_WMTRSTMSG_TYPE_T {
	WMTRSTMSG_RESET_START = 0x0,
	WMTRSTMSG_RESET_END = 0x1,
	WMTRSTMSG_RESET_END_FAIL = 0x2,
	WMTRSTMSG_RESET_MAX,
	WMTRSTMSG_RESET_INVALID = 0xff
} ENUM_WMTRSTMSG_TYPE_T, *P_ENUM_WMTRSTMSG_TYPE_T;

typedef enum _ENUM_WMTCHIN_TYPE_T {
	WMTCHIN_CHIPID = 0x0,
	WMTCHIN_HWVER = WMTCHIN_CHIPID + 1,
	WMTCHIN_MAPPINGHWVER = WMTCHIN_HWVER + 1,
	WMTCHIN_FWVER = WMTCHIN_MAPPINGHWVER + 1,
	WMTCHIN_IPVER = WMTCHIN_FWVER + 1,
	WMTCHIN_MAX,
} ENUM_WMT_CHIPINFO_TYPE_T, *P_ENUM_WMT_CHIPINFO_TYPE_T;

typedef VOID (*PF_WMT_CB)(ENUM_WMTDRV_TYPE_T src, ENUM_WMTDRV_TYPE_T dst,
			  ENUM_WMTMSG_TYPE_T type, PVOID buf, UINT32 sz);

extern MTK_WCN_BOOL mtk_wcn_wmt_func_on(ENUM_WMTDRV_TYPE_T type);
extern MTK_WCN_BOOL mtk_wcn_wmt_func_off(ENUM_WMTDRV_TYPE_T type);
extern UINT32 mtk_wcn_wmt_ic_info_get(ENUM_WMT_CHIPINFO_TYPE_T type);
extern UINT32 mtk_wcn_wmt_chipid_query(VOID);
extern INT32 mtk_wcn_wmt_msgcb_reg(ENUM_WMTDRV_TYPE_T type, PF_WMT_CB cb);
extern INT32 mtk_wcn_wmt_msgcb_unreg(ENUM_WMTDRV_TYPE_T type);
extern MTK_WCN_BOOL mtk_wcn_wmt_assert(ENUM_WMTDRV_TYPE_T type, UINT32 reason);

#endif /* _WMT_EXP_H */
