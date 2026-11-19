# SPDX-License-Identifier: GPL-2.0
#
# Out-of-tree port of the MediaTek MT6771 vendor Vcodec AP-side char driver
# to mainline 6.12.y for the Fplus T1100.
#
# Build:
#   make -C /root/kbuild/linux-6.12.114 M=$(pwd) KBUILD_MODPOST_WARN=1 modules
#
obj-m := vcodec_kernel_driver.o

vcodec_kernel_driver-objs := \
	videocodec_kernel.o \
	mt6771/videocodec_kernel_driver.o \
	mt6771/common/val/src/val.o \
	mt6771/common/drv/src/drv_base.o \
	mt6771/common/drv/src/dvfs_v2.o

ccflags-y += \
	-I$(src)/compat \
	-I$(src)/include \
	-I$(src)/include/kernel \
	-I$(src)/mt6771/common/drv/inc
