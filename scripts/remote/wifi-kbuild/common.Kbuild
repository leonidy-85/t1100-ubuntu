# SPDX-License-Identifier: GPL-2.0
#
# Kbuild wrapper for the *vendor* MediaTek connectivity WMT stack
# (`wmt_drv.ko`), replacing the Android build glue (Android.mk / the vendor
# Makefile in the source drop, which is driven by CONFIG_MTK_COMBO_CHIP
# filters and AUTOCONF_H).
#
# Rationale (docs/wifi-port-log.md, milestone 1 §2.1): the vendor Makefile
# silently selects a *different chip configuration* when
# CONFIG_MTK_COMBO_CHIP is passed without quotes ("CONSYS_6771"), and it can
# only build the whole object list that Android wanted. Here the object list
# and every -D are explicit, so the port is reproducible and reviewable.
#
# Source layout expected by this file (created by scripts/build-wifi-remote.sh
# on the build host):
#
#   <work>/common/            vendor sources (Motorola Pie-9, 3ff67212)
#   <work>/compat/include/    our 4.14->6.12 compat headers
#
# Build (out-of-tree):
#   make -C <kernel-out> M=<work>/common modules
#
# Dropped from the Android object list on purpose (see the port journal §6):
#   stp_uart.o, hif_sdio.o, stp_sdio.o, sdio_detect.o, wmt_step.o
# (STP-over-UART is BT-only, the SDIO transport is not the MT6631 HIF, and
# WMT_STEP is an MTK factory mode). Stubs for the few symbols they exported
# live in <work>/stubs/.

obj-m += wmt_drv.o

# Our stubs (see scripts/remote/wifi-stubs/README.md)
wmt_drv-y += stubs/wmt_stubs.o

wmt_drv-y += \
	common_detect/wmt_detect_pwr.o \
	common_detect/wmt_detect.o \
	common_detect/mtk_wcn_stub_alps.o \
	common_detect/wmt_gpio.o \
	common_detect/drv_init/fm_drv_init.o \
	common_detect/drv_init/conn_drv_init.o \
	common_detect/drv_init/bluetooth_drv_init.o \
	common_detect/drv_init/wlan_drv_init.o \
	common_detect/drv_init/common_drv_init.o \
	common_detect/drv_init/gps_drv_init.o \
	common_main/platform/mt6771.o \
	common_main/platform/wmt_plat_alps.o \
	common_main/platform/mtk_wcn_consys_hw.o \
	common_main/platform/mtk_wcn_cmb_hw.o \
	common_main/core/wmt_ic_6628.o \
	common_main/core/wmt_conf.o \
	common_main/core/stp_core.o \
	common_main/core/wmt_ctrl.o \
	common_main/core/wmt_func.o \
	common_main/core/wmt_core.o \
	common_main/core/psm_core.o \
	common_main/core/wmt_ic_soc.o \
	common_main/core/wmt_lib.o \
	common_main/core/wmt_ic_6620.o \
	common_main/core/stp_exp.o \
	common_main/core/wmt_ic_6632.o \
	common_main/core/wmt_exp.o \
	common_main/core/btm_core.o \
	common_main/core/wmt_ic_6630.o \
	common_main/linux/stp_btif.o \
	common_main/linux/stp_dbg_soc.o \
	common_main/linux/stp_dbg_combo.o \
	common_main/linux/osal.o \
	common_main/linux/wmt_dev.o \
	common_main/linux/bgw_desense.o \
	common_main/linux/wmt_idc.o \
	common_main/linux/wmt_dbg.o \
	common_main/linux/stp_dbg.o \
	debug_utility/ring.o \
	debug_utility/ring_emi.o \
	debug_utility/connsys_debug_utility.o

ccflags-y += -I$(src)/common_detect
ccflags-y += -I$(src)/common_detect/drv_init
ccflags-y += -I$(src)/common_main/include
ccflags-y += -I$(src)/common_main/core/include
ccflags-y += -I$(src)/common_main/linux/include
ccflags-y += -I$(src)/common_main/linux/pri/include
ccflags-y += -I$(src)/common_main/platform/include
ccflags-y += -I$(src)/debug_utility
ccflags-y += -I$(src)/../compat/include
ccflags-y += -I$(src)/common_detect/drv_init/inc

# 4.14 -> 6.12 API shims (struct timeval, do_gettimeofday, rtc_time_to_tm,
# rtc_gpio_enable_32k) are force-included into every vendor TU.
ccflags-y += -include $(src)/../compat/include/mtk_port_414.h

# --- chip / platform selection (was: CONFIG_MTK_COMBO_CHIP="CONSYS_6771") ---
ccflags-y += -DCONFIG_MTK_WCN_ARM64
ccflags-y += -DMTK_WCN_SOC_CHIP_SUPPORT		# CONSYS_* family, not MT66xx combo
ccflags-y += -DMTK_WCN_WLAN_GEN3		# gen3 Wi-Fi driver pairs with us
ccflags-y += -DWMT_PLAT_ALPS=1
ccflags-y += -DMTK_WCN_WMT_STP_EXP_SYMBOL_ABSTRACT

# --- features ---------------------------------------------------------------
ccflags-y += -DWMT_IDC_SUPPORT=0		# LTE/Wi-Fi IDC (modem is out of scope)
ccflags-y += -DWMT_UART_RX_MODE_WORK=0
ccflags-y += -DWMT_SDIO_MODE=1
ccflags-y += -DWMT_CREATE_NODE_DYNAMIC=1
ccflags-y += -DWMT_DBG_SUPPORT=1		# keep /proc/wmt debug nodes: they are
						# the only way to see power-on state
