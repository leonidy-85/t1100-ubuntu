// SPDX-License-Identifier: GPL-2.0
/*
 * wlan_stubs.c -- stubs for the Android platform hooks that the vendor gen3
 * Wi-Fi driver calls into and that do not exist on a mainline/Ubuntu system.
 *
 * Part of the MT6771 port, phase 5 path A: docs/wifi-port-log.md.
 *
 *   register_set_p2p_mode_handler()  -- Android framework callback: the
 *                                      platform (frameworks/opt/net/wifi)
 *                                      registers a handler that turns P2P mode
 *                                      on/off. Nothing on mainline needs it.
 *   update_driver_loaded_status()    -- Android sysfs "driver loaded" flag.
 *   wifi_reset_start/end()           -- Android wifi HAL reset handshake.
 *   connectivity_export_show_stack() -- MTK adapter wrapper around show_stack()
 *                                      (see connectivity_build_in_adapter.h).
 *
 * Based on MediaTek/Motorola GPL-2.0 sources (wlan-core-gen3 @ 249649d8).
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/debug.h>

#include "gl_os.h"
#include "gl_rst.h"

/* ------------------------------------------------------- Android P2P hook --- */
static set_p2p_mode g_pfn_set_p2p_mode_handler;

void register_set_p2p_mode_handler(set_p2p_mode handler)
{
	g_pfn_set_p2p_mode_handler = handler;
	pr_info("wlan_stub: P2P mode handler %s\n", handler ? "registered" : "cleared");
}
EXPORT_SYMBOL(register_set_p2p_mode_handler);

/* ------------------------------------------------- Android file-buf hook ---- */
/* The Android platform (wmt adaptor / NVRAM service) registers a handler that
 * the framework can call to read the driver's NVRAM buffer. Nothing on
 * mainline pulls it, so we only remember the registration. */
static file_buf_handler g_pfn_file_buf_handler;
static PVOID g_pv_file_buf_ctx;

void register_file_buf_handler(file_buf_handler handler, PVOID ctx, UINT_8 ucType)
{
	g_pfn_file_buf_handler = handler;
	g_pv_file_buf_ctx = ctx;
	pr_info("wlan_stub: file buf handler for type %u registered (never called)\n",
		ucType);
}

/* --------------------------------------------- Android "driver loaded" ------ */
void update_driver_loaded_status(uint8_t loaded)
{
	/* Android exposes this through /sys/wlan/driver_loaded; on mainline the
	 * module state itself is the truth. */
	pr_debug("wlan_stub: driver_loaded=%u (ignored)\n", loaded);
}

/* ---------------------------------------------------- Android reset hooks --- */
int wifi_reset_start(VOID)
{
	pr_info("wlan_stub: wifi_reset_start() ignored\n");
	return 0;
}

int wifi_reset_end(ENUM_RESET_STATUS_T status)
{
	pr_info("wlan_stub: wifi_reset_end(%d) ignored\n", status);
	return 0;
}

/* --------------------------------------- MTK adapter show_stack wrapper ----- */
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

/* No MODULE_LICENSE()/MODULE_DESCRIPTION() here on purpose: the module-level
 * ones live in the vendor files (wmt_dev.c / gl_init.c). modpost uses every
 * definition it finds, so a second one would only duplicate the strings.
 */
