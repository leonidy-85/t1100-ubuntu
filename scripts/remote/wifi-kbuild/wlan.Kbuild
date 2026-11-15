# SPDX-License-Identifier: GPL-2.0
#
# Kbuild wrapper for the *vendor* MediaTek gen3 Wi-Fi driver (`wlan_drv_gen3.ko`)
# for MT6631 / CONSYS_6771, replacing the Android build glue.
#
# Chip selection in the vendor Makefile was:
#   WLAN_CHIP_ID = MT6631  if CONFIG_MTK_COMBO_CHIP in "CONSYS_6797 6759 6758 6775 6771"
# so here it is simply spelled out: -DMT6631 selects the MT6631 code paths
# (firmware name WIFI_RAM_CODE_6759, HIF ahb_sdioLike, plat/mt6771).
#
# Source layout expected (created by scripts/build-wifi-remote.sh):
#   <work>/wlan/            vendor sources (Motorola Pie-9, 249649d8)
#   <work>/compat/include/  our 4.14 -> 6.12 compat headers
#
# Build: make -C <kernel-out> M=<work>/wlan modules

obj-m += wlan_drv_gen3.o

# Our stubs (see scripts/remote/wifi-stubs/README.md)
wlan_drv_gen3-y += stubs/wlan_stubs.o

# wireless_send_event() lives in vmlinux only with CONFIG_WEXT_CORE (built-in
# bool, selected by CONFIG_CFG80211_WEXT). Our own kernel has it; a foreign
# out-tree without the option gets this no-op instead of a modpost failure.
# See scripts/remote/wifi-stubs/wext_stub.c.
ifeq ($(CONFIG_WEXT_CORE),)
wlan_drv_gen3-y += stubs/wext_stub.o
endif

wlan_drv_gen3-y += \
	common/dump.o \
	common/wlan_lib.o \
	common/wlan_oid.o \
	common/wlan_bow.o \
	common/debug.o \
	common/wlan_p2p.o \
	common/fwcfg.o \
	nic/nic.o \
	nic/nic_tx.o \
	nic/nic_rx.o \
	nic/nic_pwr_mgt.o \
	nic/nic_rate.o \
	nic/cmd_buf.o \
	nic/que_mgt.o \
	nic/nic_cmd_event.o \
	nic/p2p_nic.o \
	os/linux/gl_init.o \
	os/linux/gl_kal.o \
	os/linux/gl_bow.o \
	os/linux/gl_wext.o \
	os/linux/gl_wext_priv.o \
	os/linux/gl_ate_agent.o \
	os/linux/gl_qa_agent.o \
	os/linux/gl_hook_api.o \
	os/linux/gl_proc.o \
	os/linux/gl_rst.o \
	os/linux/gl_cfg80211.o \
	os/linux/gl_vendor.o \
	os/linux/platform.o \
	os/linux/t1100_stp_hif.o \
	os/linux/gl_p2p.o \
	os/linux/gl_p2p_cfg80211.o \
	os/linux/gl_p2p_init.o \
	os/linux/gl_p2p_kal.o \
	os/linux/hif/ahb_sdioLike/arm.o \
	os/linux/hif/ahb_sdioLike/ahb.o \
	os/linux/hif/ahb_sdioLike/sdio_bus_driver.o \
	os/linux/hif/ahb_sdioLike/ahb_cqdma.o \
	os/linux/plat/mt6771/plat_priv.o \
	mgmt/ais_fsm.o \
	mgmt/aaa_fsm.o \
	mgmt/assoc.o \
	mgmt/auth.o \
	mgmt/bss.o \
	mgmt/cnm.o \
	mgmt/cnm_timer.o \
	mgmt/cnm_mem.o \
	mgmt/hem_mbox.o \
	mgmt/mib.o \
	mgmt/privacy.o \
	mgmt/rate.o \
	mgmt/rlm.o \
	mgmt/rlm_domain.o \
	mgmt/rlm_obss.o \
	mgmt/rlm_protection.o \
	mgmt/rsn.o \
	mgmt/saa_fsm.o \
	mgmt/scan.o \
	mgmt/scan_fsm.o \
	mgmt/swcr.o \
	mgmt/roaming_fsm.o \
	mgmt/tkip_mic.o \
	mgmt/hs20.o \
	mgmt/tdls.o \
	mgmt/wnm.o \
	mgmt/wmm.o \
	mgmt/stats.o \
	mgmt/p2p_dev_fsm.o \
	mgmt/p2p_dev_state.o \
	mgmt/p2p_role_fsm.o \
	mgmt/p2p_role_state.o \
	mgmt/p2p_func.o \
	mgmt/p2p_scan.o \
	mgmt/p2p_ie.o \
	mgmt/p2p_rlm.o \
	mgmt/p2p_assoc.o \
	mgmt/p2p_bss.o \
	mgmt/p2p_rlm_obss.o \
	mgmt/wapi.o

ccflags-y += -I$(src)/include
ccflags-y += -I$(src)/include/nic
ccflags-y += -I$(src)/include/mgmt
ccflags-y += -I$(src)/os
ccflags-y += -I$(src)/os/linux/include
ccflags-y += -I$(src)/os/linux/hif/ahb_sdioLike/include
ccflags-y += -I$(src)/os/linux/plat/mt6771
ccflags-y += -I$(src)/../compat/include

# 4.14 -> 6.12 API shims (struct timeval, do_gettimeofday, rtc_time_to_tm,
# rtc_gpio_enable_32k) are force-included into every vendor TU.
ccflags-y += -include $(src)/../compat/include/mtk_port_414.h

# --- kernel-config assumptions of the vendor glue ---------------------------
# The vendor code hard-requires two kernel-side options and refuses to compile
# without them:
#   * CONFIG_NL80211_TESTMODE - gl_cfg80211.h/gl_p2p_ioctl.h have #error without
#     it, and it gates the testmode_cmd/testmode_dump fields of
#     `struct cfg80211_ops` (include/net/cfg80211.h), a struct the driver fills
#     and cfg80211.ko walks -> the module and cfg80211.ko MUST agree on it.
#   * CONFIG_WEXT_PRIV - gl_wext.c initialises `struct iw_handler_def`
#     .num_private/.private/.private_args, which only exist under that option.
#     This one is local to the driver (it only stores the struct in a variable;
#     wiphy->wext is written out only under CONFIG_CFG80211_WEXT), so defining
#     it for this module alone cannot desynchronise any kernel-side layout.
# Our own kernel gets both from configs/t1100-wifi.fragment, so the ifeqs below
# are no-ops there. They only fire when building against a foreign out-tree
# whose .config does not select them (the second developer's -touch-rot kernel,
# docs/wifi-port-log.md "M3: модули под -touch-rot"); such a build is only
# valid together with the cfg80211.ko from the same run.
ifeq ($(CONFIG_NL80211_TESTMODE),)
ccflags-y += -DCONFIG_NL80211_TESTMODE=1
endif
ifeq ($(CONFIG_WEXT_PRIV),)
ccflags-y += -DCONFIG_WEXT_PRIV=1
endif

# --- driver identity --------------------------------------------------------
ccflags-y += -DLINUX
ccflags-y += -DMT6631			# A-die 0x6771 -> firmware suffix 6759
# The vendor embeds a build timestamp; fix it (overridable) so that the
# resulting .ko are bit-reproducible and their sha256 is a stable fact.
DRIVER_BUILD_DATE ?= 20261111
ccflags-y += -DDRIVER_BUILD_DATE=\"$(DRIVER_BUILD_DATE)\"

# --- features (values mirror the vendor Makefile for CONSYS_6771) -----------
ccflags-y += -DCFG_SUPPORT_DEBUG_FS=0
ccflags-y += -DWLAN_INCLUDE_PROC
ccflags-y += -DCFG_SUPPORT_AGPS_ASSIST=1
ccflags-y += -DCFG_SUPPORT_TSF_USING_BOOTTIME=1
ccflags-y += -DARP_MONITER_ENABLE=1
ccflags-y += -DCFG_SUPPORT_CHNL_CONFLICT_REVISE=1
ccflags-y += -DCFG_SUPPORT_AEE=0	# Android AEE (kernel debugger) does not exist
ccflags-y += -DBUILD_QA_DBG=0
ccflags-y += -DCFG_SUPPORT_PASSPOINT=0
ccflags-y += -DCFG_HS20_DEBUG=0
ccflags-y += -DCFG_ENABLE_GTK_FRAME_FILTER=0
ccflags-y += -DCFG_MET_PACKET_TRACE_SUPPORT=0
ccflags-y += -DWMT_IDC_SUPPORT=0
ccflags-y += -DDBG=0
ccflags-y += -DCFG_ENABLE_EMI_MPU=0	# set by the vendor for CONSYS_6775/6771
ccflags-y += -DCFG_SUPPORT_WIFI_FW_LOG_UI=1
ccflags-y += -DFW_CFG_SUPPORT
ccflags-y += -DMTK_WCN_WMT_STP_EXP_SYMBOL_ABSTRACT
