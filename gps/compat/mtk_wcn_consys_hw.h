#ifndef _MTK_WCN_CONSYS_HW_SHIM_H
#define _MTK_WCN_CONSYS_HW_SHIM_H
#include "osal_typedef.h"

/*
 * T1100: the vendor GPS driver asks WMT for the GPS LNA pin from this
 * ioctl path.  The pin is not described in our DT and the wmt_drv we
 * build does not export the helper, so keep the caller harmless.
 */
static inline signed int mtk_wmt_get_gps_lna_pin_num(void)
{
	return -1;
}

#endif
