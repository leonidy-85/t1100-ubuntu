/* SPDX-License-Identifier: GPL-2.0 */
/*
 * T1100: minimal OS abstraction types for the vendor MTK FM driver.
 *
 * The vendor driver was written for the in-tree MTK connectivity tree and
 * pulled a large "osal" header set.  Only the base types, the boolean wrapper
 * and the two print helpers are actually used by the FM sources, so the port
 * provides just those and keeps the vendor code untouched.
 */
#ifndef _OSAL_TYPEDEF_H
#define _OSAL_TYPEDEF_H

#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/printk.h>

typedef unsigned char UINT8;
typedef unsigned short UINT16;
typedef unsigned int UINT32;
typedef unsigned long long UINT64;

typedef signed char INT8;
typedef signed short INT16;
typedef signed int INT32;
typedef signed long long INT64;

typedef UINT8 *PUINT8;
typedef UINT16 *PUINT16;
typedef UINT32 *PUINT32;
typedef UINT64 *PUINT64;

typedef INT8 *PINT8;
typedef INT16 *PINT16;
typedef INT32 *PINT32;
typedef INT64 *PINT64;

typedef void VOID;
typedef void *PVOID;
typedef VOID *P_VOID;

typedef int MTK_WCN_BOOL;

#ifndef MTK_WCN_BOOL_FALSE
#define MTK_WCN_BOOL_FALSE	((MTK_WCN_BOOL)0)
#endif
#ifndef MTK_WCN_BOOL_TRUE
#define MTK_WCN_BOOL_TRUE	((MTK_WCN_BOOL)1)
#endif

#ifndef TRUE
#define TRUE	1
#endif
#ifndef FALSE
#define FALSE	0
#endif

#ifndef osal_warn_print
#define osal_warn_print(fmt, arg...)	pr_info(fmt, ##arg)
#endif
#ifndef osal_err_print
#define osal_err_print(fmt, arg...)	pr_err(fmt, ##arg)
#endif

#endif /* _OSAL_TYPEDEF_H */
