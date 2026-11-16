/* SPDX-License-Identifier: GPL-2.0 */
/*
 * T1100: STP exports the FM driver needs.  The full vendor header drags in the
 * whole connectivity OS layer; this carries only the task index, the event
 * callback type and the three entry points used by plat/legacy_wmt.c.
 */
#ifndef _STP_EXP_H
#define _STP_EXP_H

#include "osal_typedef.h"

#define FM_TASK_INDX	(1)
#define GPS_TASK_INDX	(2)

#define MTKSTP_BUFFER_SIZE	(16384)

typedef VOID (*MTK_WCN_STP_EVENT_CB)(VOID);

extern INT32 mtk_wcn_stp_receive_data(PUINT8 buffer, UINT32 length, UINT8 type);
extern INT32 mtk_wcn_stp_send_data(const PUINT8 buffer, const UINT32 length, const UINT8 type);
extern INT32 mtk_wcn_stp_register_event_cb(INT32 type, MTK_WCN_STP_EVENT_CB func);
extern MTK_WCN_BOOL mtk_wcn_stp_is_ready(VOID);

#endif /* _STP_EXP_H */
