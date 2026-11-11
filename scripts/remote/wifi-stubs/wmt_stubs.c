// SPDX-License-Identifier: GPL-2.0
/*
 * wmt_stubs.c -- stubs for the MTK-only pieces of the WMT (connectivity
 * common) stack that mainline 6.12 cannot provide.
 *
 * Part of the MT6771 port, phase 5 path A: docs/wifi-port-log.md.
 *
 * Two kinds of stubs live here:
 *
 *  1. Android platform hooks with no mainline counterpart
 *     (AEE/AED kernel debugger). The vendor code calls them on the error path
 *     only; printing a warning keeps the failure visible in dmesg.
 *
 *  2. Symbols of the objects that are deliberately NOT built
 *     (common_main/linux/{stp_sdio,hif_sdio}.c, common_detect/sdio_detect.c,
 *     common_main/linux/stp_uart.c, common_main/linux/wmt_step.c):
 *     - SDIO: MT6631 on MT6771 uses AHB/WFDMA, not SDIO;
 *     - STP-over-UART: only needed for BT over UART;
 *     - WMT STEP: MTK factory step mode.
 *     They exist so that wmt_drv.ko links; calling them prints a warning and
 *     fails, which is exactly what should happen if a wrong transport is
 *     selected at run time.
 *
 * Based on MediaTek/Motorola GPL-2.0 connectivity sources
 * (connectivity-common @ 3ff67212).
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/device.h>
#include <linux/sched/debug.h>	/* show_stack() */

#include "aee.h"
#include "hif_sdio.h"
#include "stp_sdio.h"
#include "wmt_dev.h"
#include "wmt_step.h"
#include "sdio_detect.h"
#include "connectivity_build_in_adapter.h"

#define WMT_STUB_WARN(_what)						\
	pr_warn_once("wmt_stub: %s() is a stub -- not supported on mainline\n", _what)

/* ------------------------------------------- MTK adapter hooks (WMT side) ---
 * Implemented by MediaTek in drivers/misc/mediatek/connectivity/wmt_plat
 * (files that are not part of the published sources); declared by the
 * adapter headers in compat/.
 */
void connectivity_export_show_stack(struct task_struct *tsk, unsigned long *sp)
{
	/* show_stack() is not exported to modules; dump the current stack (the
	 * only caller is a watchdog path that wants to know "who is stuck"). */
	if (tsk)
		sched_show_task(tsk);
	else
		dump_stack();
}
EXPORT_SYMBOL(connectivity_export_show_stack);

void connectivity_export_dump_thread_state(const char *name)
{
	pr_info("wmt_stub: dump_thread_state(%s) -- only a marker, no task dump\n",
		name ? name : "?");
}
EXPORT_SYMBOL(connectivity_export_dump_thread_state);

/* -------------------------------------------- built-in platform bridge -----
 * In the vendor tree these are in wmt_build_in_adapter.c (drivers/misc/
 * mediatek/connectivity): the always-built-in half of WMT that bridges
 * platform callbacks and the MMC/SDIO layer into wmt_drv.ko. We have no such
 * built-in driver, and no SDIO transport, so the registration is a no-op.
 */
static struct wmt_platform_bridge *g_pbridge;

void wmt_export_platform_bridge_register(struct wmt_platform_bridge *cb)
{
	g_pbridge = cb;
	pr_info("wmt_stub: platform bridge %s\n", cb ? "registered" : "cleared");
}
EXPORT_SYMBOL(wmt_export_platform_bridge_register);

void wmt_export_platform_bridge_unregister(void)
{
	g_pbridge = NULL;
}

void wmt_export_mtk_wcn_cmb_sdio_disable_eirq(void)
{
	WMT_STUB_WARN("wmt_export_mtk_wcn_cmb_sdio_disable_eirq");
}

/* Globals that the vendor keeps in its built-in SDIO/PMIC glue. */
unsigned int wifi_irq = 0xffffffff;
void *mtk_wcn_cmb_sdio_pm_cb;
void *mtk_wcn_cmb_sdio_pm_data;

/* ---------------------------------------------------------------- 1. AEE --- */
void aee_kernel_dal_show(char *str)
{
	WMT_STUB_WARN("aee_kernel_dal_show");
}

int aee_kernel_warning_api(char *file, int line, int option, char *module,
			   char *detail, const char *fmt, ...)
{
	pr_warn_once("wmt_stub: aee_kernel_warning_api(%s:%d, %s): %s\n",
		     file ? file : "?", line, module ? module : "?",
		     detail ? detail : "");
	return 0;
}

int aed_combo_exception(const int *excp_type, int len, const int *data,
			int data_len, const char *info)
{
	pr_warn_once("wmt_stub: aed_combo_exception(%s)\n", info ? info : "");
	return 0;
}

int aed_combo_exception_api(const int *excp_type, int len, const int *data,
			    int data_len, const char *info, int option)
{
	pr_warn_once("wmt_stub: aed_combo_exception_api(%s)\n", info ? info : "");
	return 0;
}

/* ------------------------------------------------- 2a. SDIO transport ------- */
/* MT6771 + MT6631 uses AHB (os/linux/hif/ahb_sdioLike), the SDIO transport
 * objects are not built. The struct is still referenced by the WMT core
 * (wmt_dev.c/stp_exp.c query it when HIF == SDIO). */
MTK_WCN_STP_SDIO_HIF_INFO g_stp_sdio_host_info;

VOID stp_sdio_retry_flag_ctrl(INT32 flag)
{
	WMT_STUB_WARN("stp_sdio_retry_flag_ctrl");
}

VOID stp_sdio_dump_register(VOID)
{
	WMT_STUB_WARN("stp_sdio_dump_register");
}

int sdio_detect_exit(void)
{
	WMT_STUB_WARN("sdio_detect_exit");
	return 0;
}

int sdio_detect_init(void)
{
	WMT_STUB_WARN("sdio_detect_init");
	return -ENOSYS;
}

int sdio_detect_do_autok(int chipId)
{
	WMT_STUB_WARN("sdio_detect_do_autok");
	return -ENOSYS;
}

/* The MTK SDIO client (hif_sdio.c) and its STP side (stp_sdio.c) are not
 * built, but the WMT core still holds pointers to their entry points. */
int mtk_wcn_hif_sdio_drv_init(VOID)
{
	WMT_STUB_WARN("mtk_wcn_hif_sdio_drv_init");
	return -ENOSYS;
}

int mtk_wcn_hif_sdio_driver_exit(VOID)
{
	WMT_STUB_WARN("mtk_wcn_hif_sdio_driver_exit");
	return -ENOSYS;
}

int mtk_wcn_stp_sdio_drv_init(VOID)
{
	WMT_STUB_WARN("mtk_wcn_stp_sdio_drv_init");
	return -ENOSYS;
}

int mtk_wcn_stp_sdio_drv_exit(VOID)
{
	WMT_STUB_WARN("mtk_wcn_stp_sdio_drv_exit");
	return -ENOSYS;
}

INT32 mtk_wcn_hif_sdio_wmt_control(WMT_SDIO_FUNC_TYPE func_type, MTK_WCN_BOOL is_on)
{
	WMT_STUB_WARN("mtk_wcn_hif_sdio_wmt_control");
	return -ENOSYS;
}

INT32 mtk_wcn_hif_sdio_update_cb_reg(INT32 (*ts_update)(VOID))
{
	WMT_STUB_WARN("mtk_wcn_hif_sdio_update_cb_reg");
	return -ENOSYS;
}

INT32 mtk_wcn_hif_sdio_f0_readb(MTK_WCN_HIF_SDIO_CLTCTX ctx, UINT32 offset,
				PUINT8 pvb)
{
	WMT_STUB_WARN("mtk_wcn_hif_sdio_f0_readb");
	return -ENOSYS;
}

INT32 stp_sdio_rw_retry(ENUM_STP_SDIO_HIF_TYPE_T type, UINT32 retry_limit,
			MTK_WCN_HIF_SDIO_CLTCTX clt_ctx, UINT32 offset,
			PUINT32 pData, UINT32 len)
{
	WMT_STUB_WARN("stp_sdio_rw_retry");
	return -ENOSYS;
}

INT32 stp_sdio_retry_flag_get(VOID)
{
	WMT_STUB_WARN("stp_sdio_retry_flag_get");
	return 0;
}

INT32 stp_sdio_wake_up_ctrl(MTK_WCN_HIF_SDIO_CLTCTX ctx)
{
	WMT_STUB_WARN("stp_sdio_wake_up_ctrl");
	return -ENOSYS;
}

VOID stp_sdio_txdbg_dump(VOID)
{
	WMT_STUB_WARN("stp_sdio_txdbg_dump");
}

/* ------------------------------------------------- 2b. STP over UART -------- */
/* Only used when WMT drives BT through a UART; the SiP has none. */
int mtk_wcn_stp_uart_drv_init(VOID)
{
	WMT_STUB_WARN("mtk_wcn_stp_uart_drv_init");
	return -ENOSYS;
}

int mtk_wcn_stp_uart_drv_exit(VOID)
{
	WMT_STUB_WARN("mtk_wcn_stp_uart_drv_exit");
	return -ENOSYS;
}

/* ------------------------------------------------- 2c. WMT STEP (factory) --- */
void wmt_step_init(void)
{
	WMT_STUB_WARN("wmt_step_init");
}

void wmt_step_deinit(void)
{
	WMT_STUB_WARN("wmt_step_deinit");
}

void wmt_step_print_version(void)
{
	WMT_STUB_WARN("wmt_step_print_version");
}

/* ------------------------------------------- 2d. CONNSYS EMI base address ---
 * The vendor kernel defines this in
 * drivers/misc/mediatek/connectivity/wmt_plat/*; it is the physical base of
 * the 2 MiB CONNSYS reserved memory (stock DTB: consys-reserve-memory
 * @0xbfc00000, docs/wifi-plan.md §1.1).
 *
 * TODO(power-on): fill it from DT (reserved-memory node) instead of leaving 0.
 * With 0 the EMI remap / coredump / EMI-MPU paths are skipped, which is the
 * safe default for a bring-up build (CFG_ENABLE_EMI_MPU=0 as well).
 */
phys_addr_t gConEmiPhyBase;
EXPORT_SYMBOL(gConEmiPhyBase);
phys_addr_t gConEmiSize;		/* 2 MiB in the stock DTB */
EXPORT_SYMBOL(gConEmiSize);

/* No MODULE_LICENSE()/MODULE_DESCRIPTION() here on purpose: the module-level
 * ones live in the vendor files (wmt_dev.c / gl_init.c). modpost uses every
 * definition it finds, so a second one would only duplicate the strings.
 */
