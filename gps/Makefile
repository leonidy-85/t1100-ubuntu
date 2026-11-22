obj-m += gps_drv.o

gps_drv-objs := stp_chrdev_gps.o fw_log_gps.o gps_emi.o

ccflags-y += -I$(src)
ccflags-y += -I$(src)/compat
ccflags-y += -DMTK_WCN_WMT_STP_EXP_SYMBOL_ABSTRACT
ccflags-y += -DCONFIG_MTK_WCN_ARM64
ccflags-y += -DWMT_IDC_SUPPORT=0
ccflags-y += -DWMT_CREATE_NODE_DYNAMIC=1
ccflags-y += -DREMOVE_MK_NODE=0
ccflags-y += -DCONFIG_MTK_GPS_EMI
ccflags-y += -DCONFIG_MTK_CONNSYS_DEDICATED_LOG_PATH

# connsys_debug_utility.h живёт в дереве wmt, а не в репозитории.
# Путь можно переопределить: make T1100_WMT_COMMON=/path/to/common ...
T1100_WMT_COMMON ?= /home/l/t1100-wifi-build-own48/work/common
ccflags-y += -I$(T1100_WMT_COMMON)/debug_utility
