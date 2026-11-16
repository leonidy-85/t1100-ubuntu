# SPDX-License-Identifier: GPL-2.0
#
# T1100: out-of-tree build of the vendor MTK FM driver (MT6631).
# The vendor Makefile is meant for the in-tree ALPS connectivity package; this
# one keeps the same object list and defines but builds against our kernel out
# tree with the minimal compat headers in compat/.
#
# Build: scripts/build-fm-remote.sh

obj-m += fmradio_drv.o

fmradio_drv-objs := \
	chips/mt6631/pub/mt6631_fm_lib.o \
	chips/mt6631/pub/mt6631_fm_rds.o \
	core/fm_module.o \
	core/fm_main.o \
	core/fm_config.o \
	core/fm_rds_parser.o \
	core/fm_patch.o \
	core/fm_utils.o \
	core/fm_link.o \
	core/fm_eint.o \
	core/fm_cmd.o \
	core/fm_reg_utils.o \
	plat/legacy_wmt.o

ccflags-y += -DMT6631_FM
ccflags-y += -DCFG_FM_CONNAC2=0
ccflags-y += -DWMT_IDC_SUPPORT=0
ccflags-y += -DMTK_WCN_WMT_STP_EXP_SYMBOL_ABSTRACT
ccflags-y += -DCONFIG_MTK_WCN_ARM64

ccflags-y += -I$(src)/compat
ccflags-y += -I$(src)/inc
ccflags-y += -I$(src)/plat/inc
ccflags-y += -I$(src)/chips/mt6631/inc
